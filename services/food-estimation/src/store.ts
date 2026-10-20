import { DatabaseSync } from 'node:sqlite';
import { chmodSync, mkdirSync, readFileSync, readdirSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { APIError, DAY, MAX_IMAGE, digest, type Submission, type ErrorCode } from './contracts.js';
import type { Config } from './config.js';

export type JobRow = {
  id: string; owner: string; request_id: string; digest: string; status: string; error: ErrorCode | null;
  body: string | null; result: string | null; created: number; started: number | null; terminal: number | null;
  record_id: string; input_revision: number; lifecycle_epoch: number; policy_version: string;
};
type Upload = { id: string; owner: string; sha256: string; bytes: number; expires: number; job_id: string | null };
export class Store {
  readonly db: DatabaseSync;
  readonly mediaDir: string;
  constructor(readonly config: Config, readonly now: () => number = Date.now) {
    mkdirSync(config.dataDir, { recursive: true, mode: 0o700 }); chmodSync(config.dataDir, 0o700);
    this.mediaDir = join(config.dataDir, 'uploads'); mkdirSync(this.mediaDir, { mode: 0o700, recursive: true });
    this.db = new DatabaseSync(join(config.dataDir, 'jobs.sqlite'));
    chmodSync(join(config.dataDir, 'jobs.sqlite'), 0o600);
    this.db.exec(`PRAGMA journal_mode=DELETE; PRAGMA secure_delete=ON; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;`);
    const version = this.db.prepare('PRAGMA user_version').get()!['user_version'];
    if (version !== 0 && version !== 1) { this.db.close(); throw new Error('Unsupported service schema'); }
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS jobs (
        id TEXT PRIMARY KEY, owner TEXT NOT NULL, request_id TEXT NOT NULL, digest TEXT NOT NULL,
        status TEXT NOT NULL, error TEXT, body TEXT, result TEXT, created INTEGER NOT NULL,
        started INTEGER, terminal INTEGER, record_id TEXT NOT NULL, input_revision INTEGER NOT NULL,
        lifecycle_epoch INTEGER NOT NULL, policy_version TEXT NOT NULL, UNIQUE(owner, request_id)
      ) STRICT;
      CREATE TABLE IF NOT EXISTS uploads (
        id TEXT PRIMARY KEY, owner TEXT NOT NULL, sha256 TEXT NOT NULL, bytes INTEGER NOT NULL,
        expires INTEGER NOT NULL, job_id TEXT REFERENCES jobs(id)
      ) STRICT;
      CREATE TABLE IF NOT EXISTS quota (owner TEXT NOT NULL, day TEXT NOT NULL, attempts INTEGER NOT NULL, PRIMARY KEY(owner,day)) STRICT;
      CREATE INDEX IF NOT EXISTS jobs_queue ON jobs(status,created);
      CREATE INDEX IF NOT EXISTS jobs_owner_created ON jobs(owner,created);
      PRAGMA user_version=1;
    `);
  }
  transaction<T>(body: () => T): T {
    this.db.exec('BEGIN IMMEDIATE');
    try { const result = body(); this.db.exec('COMMIT'); return result; }
    catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
  policy(version: string) { if (version !== this.config.policyVersion) throw new APIError('policy_changed', 409); }
  available() { if (!this.config.ready) throw new APIError('not_configured', 503); }
  async upload(owner: string, policy: string, mime: string, input: Buffer) {
    this.policy(policy); this.available();
    if (!input.length || input.length > MAX_IMAGE) throw new APIError('invalid_input', 413);
    const allowed: Record<string,string> = { 'image/jpeg':'jpeg', 'image/png':'png', 'image/webp':'webp' };
    if (!allowed[mime]) throw new APIError('invalid_input', 415);
    let data: Buffer;
    try {
      const image = sharp(input, { limitInputPixels: 50_000_000, failOn: 'warning' });
      const metadata = await image.metadata();
      if (metadata.format !== allowed[mime] || !metadata.width || !metadata.height || (metadata.pages ?? 1) !== 1) throw new Error();
      data = await image.rotate().flatten({ background: '#ffffff' }).jpeg({ quality: 85 }).toBuffer();
    } catch { throw new APIError('invalid_input', 415); }
    if (data.length > MAX_IMAGE) throw new APIError('invalid_input', 413);
    this.policy(policy);
    const count = this.db.prepare('SELECT count(*) AS n FROM uploads WHERE owner=?').get(owner)!['n'] as number;
    if (count >= 100) throw new APIError('rate_limited', 429, 60);
    const id = randomUUID(), path = this.imagePath(id), staging = path + '.partial';
    try {
      writeFileSync(staging, data, { mode: 0o600, flag: 'wx' }); renameSync(staging, path);
      const hash = digest(data), expires = this.now() + DAY;
      this.db.prepare('INSERT INTO uploads VALUES (?,?,?,?,?,NULL)').run(id, owner, hash, data.length, expires);
      return { image_ref: id, sha256: hash, bytes: data.length, mime_type: 'image/jpeg', expires_at: new Date(expires).toISOString() };
    } catch (error) { for (const p of [staging,path]) { try { unlinkSync(p); } catch {} } throw error; }
  }
  imagePath(id: string) { if (!/^[a-f0-9-]{36}$/.test(id)) throw new APIError('invalid_input'); return join(this.mediaDir, id + '.jpg'); }
  get(id: string): JobRow | undefined { return this.db.prepare('SELECT * FROM jobs WHERE id=?').get(id) as JobRow | undefined; }
  owned(owner: string, id: string): JobRow { const row = this.get(id); if (!row || row.owner !== owner) throw new APIError('not_found', 404); return row; }
  submit(owner: string, body: Submission): JobRow {
    const hash = digest(JSON.stringify(body));
    return this.transaction(() => {
      const old = this.db.prepare('SELECT * FROM jobs WHERE owner=? AND request_id=?').get(owner, body.request_id) as JobRow | undefined;
      if (old) { if (old.digest !== hash) throw new APIError('conflict', 409); return old; }
      this.policy(body.policy_version); this.available();
      const now = this.now(), first = Date.parse(body.request_created_at);
      if (now - first >= DAY || first - now > 300_000) throw new APIError('expired', 410);
      if (body.retry_of) this.owned(owner, body.retry_of);
      const recent = this.db.prepare('SELECT count(*) AS n FROM jobs WHERE owner=? AND created>?').get(owner, now - 60_000)!['n'] as number;
      if (recent >= this.config.minuteLimit) throw new APIError('rate_limited', 429, 60);
      let bytes = 0;
      for (const id of body.image_refs) {
        const u = this.db.prepare('SELECT * FROM uploads WHERE id=?').get(id) as Upload | undefined;
        if (!u || u.owner !== owner) throw new APIError('invalid_input');
        if (u.expires <= now) throw new APIError('expired', 410);
        if (u.job_id) throw new APIError('conflict', 409);
        bytes += u.bytes;
      }
      if (bytes > 9 * MAX_IMAGE) throw new APIError('invalid_input', 413);
      const id = randomUUID();
      this.db.prepare(`INSERT INTO jobs (id,owner,request_id,digest,status,body,created,record_id,input_revision,lifecycle_epoch,policy_version) VALUES (?,?,?,?,'queued',?,?,?,?,?,?)`)
        .run(id, owner, body.request_id, hash, JSON.stringify(body), now, body.record_id, body.input_revision, body.lifecycle_epoch, body.policy_version);
      for (const ref of body.image_refs) this.db.prepare('UPDATE uploads SET job_id=? WHERE id=?').run(id, ref);
      return this.get(id)!;
    });
  }
  next(): JobRow | undefined { return this.db.prepare("SELECT * FROM jobs WHERE status='queued' ORDER BY created,id LIMIT 1").get() as JobRow | undefined; }
  images(row: JobRow): Buffer[] {
    const body = JSON.parse(row.body!) as Submission;
    return body.image_refs.map(id => {
      const u = this.db.prepare('SELECT * FROM uploads WHERE id=? AND owner=? AND job_id=?').get(id, row.owner, row.id) as Upload | undefined;
      if (!u || u.expires <= this.now()) throw new APIError('expired', 410);
      const bytes = readFileSync(this.imagePath(id)); if (bytes.length !== u.bytes || digest(bytes) !== u.sha256) throw new APIError('invalid_input');
      return bytes;
    });
  }
  claim(id: string): boolean {
    return this.transaction(() => {
      const row = this.get(id); if (!row || row.status !== 'queued') return false;
      this.policy(row.policy_version); this.available();
      if (this.now() - row.created >= DAY) throw new APIError('expired', 410);
      const day = new Date(this.now()).toISOString().slice(0, 10);
      const used = this.db.prepare('SELECT attempts FROM quota WHERE owner=? AND day=?').get(row.owner, day)?.['attempts'] as number ?? 0;
      if (used >= this.config.dailyLimit) throw new APIError('quota_exceeded', 429);
      this.db.prepare('INSERT INTO quota VALUES (?,?,1) ON CONFLICT(owner,day) DO UPDATE SET attempts=attempts+1').run(row.owner, day);
      this.db.prepare("UPDATE jobs SET status='running',started=? WHERE id=?").run(this.now(), id);
      return true;
    });
  }
  finish(id: string, status: string, error: ErrorCode | null, result: unknown = null) {
    this.db.prepare("UPDATE jobs SET status=?,error=?,result=?,terminal=?,body=NULL WHERE id=? AND status IN ('queued','running')")
      .run(status, error, result === null ? null : JSON.stringify(result), this.now(), id);
    this.removeInputs(id);
  }
  cancel(owner: string, id: string) {
    this.owned(owner, id);
    this.db.prepare("UPDATE jobs SET status='cancelled',error='cancelled',result=NULL,body=NULL,terminal=COALESCE(terminal,?) WHERE id=?").run(this.now(), id);
    this.removeInputs(id); return this.get(id)!;
  }
  private removeUpload(id: string) {
    try { unlinkSync(this.imagePath(id)); } catch (e) { if ((e as NodeJS.ErrnoException).code !== 'ENOENT') throw e; }
    this.db.prepare('DELETE FROM uploads WHERE id=?').run(id);
  }
  private removeInputs(id: string) {
    for (const row of this.db.prepare('SELECT id FROM uploads WHERE job_id=?').all(id)) this.removeUpload(row['id'] as string);
  }
  recover() {
    for (const row of this.db.prepare("SELECT id FROM jobs WHERE status='running'").all()) this.finish(row['id'] as string, 'failed', 'upstream_outcome_unknown');
    this.cleanup();
  }
  cleanup() {
    const now = this.now();
    for (const row of this.db.prepare("SELECT id FROM jobs WHERE status='queued' AND created<=?").all(now - DAY)) this.finish(row['id'] as string, 'expired', 'expired');
    for (const row of this.db.prepare('SELECT id FROM jobs WHERE terminal IS NOT NULL').all()) this.removeInputs(row['id'] as string);
    for (const row of this.db.prepare('SELECT id FROM uploads WHERE expires<=?').all(now)) this.removeUpload(row['id'] as string);
    this.db.prepare("UPDATE jobs SET body=NULL,result=NULL,status='expired',error='expired' WHERE terminal<=?").run(now - DAY);
    this.db.prepare('DELETE FROM jobs WHERE terminal<=?').run(now - 7 * DAY);
    this.db.prepare('DELETE FROM quota WHERE day<?').run(new Date(now).toISOString().slice(0, 10));
    const known = new Set(this.db.prepare('SELECT id FROM uploads').all().map(x => `${x['id']}.jpg`));
    for (const name of readdirSync(this.mediaDir)) if (!known.has(name)) unlinkSync(join(this.mediaDir, name));
  }
  view(row: JobRow) {
    return { job_id: row.id, record_id: row.record_id, input_revision: row.input_revision, lifecycle_epoch: row.lifecycle_epoch,
      status: row.status, error_code: row.error, created_at: new Date(row.created).toISOString(),
      ...(row.result === null ? {} : { result: JSON.parse(row.result) }) };
  }
  close() { this.db.close(); }
}
