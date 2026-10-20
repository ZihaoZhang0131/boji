import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { APIError, MAX_IMAGE, digest, submission } from './contracts.js';
import { Store } from './store.js';
import { Worker, type SafeLog } from './worker.js';
import { chatCompletions, type Provider } from './provider.js';
import type { Config } from './config.js';

function readBody(req: IncomingMessage, max: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    let length = 0; const chunks: Buffer[] = []; let exceeded = false;
    req.on('data', (data: Buffer) => {
      length += data.length;
      if (length > max) { if (!exceeded) { exceeded = true; chunks.length = 0; reject(new APIError('invalid_input', 413)); } }
      else if (!exceeded) chunks.push(data);
    });
    req.on('end', () => { if (!exceeded) resolve(Buffer.concat(chunks)); });
    req.on('error', () => reject(new APIError('invalid_input')));
    req.on('aborted', () => reject(new APIError('invalid_input')));
  });
}
function send(res: ServerResponse, status: number, body: unknown, retryAfter?: number) {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', ...(retryAfter ? { 'Retry-After': String(retryAfter) } : {}) });
  res.end(JSON.stringify(body));
}
export function createService(config: Config, options: { now?: () => number; provider?: Provider; log?: SafeLog; manualWorker?: boolean } = {}) {
  const log = options.log ?? ((event) => process.stdout.write(JSON.stringify(event) + '\n'));
  const store = new Store(config, options.now);
  const worker = new Worker(store, options.provider ?? chatCompletions(config), log);
  const auth = (req: IncomingMessage): string => {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ') || header.length < 50 || header.length > 1024) throw new APIError('unauthorized', 401);
    const hash = Buffer.from(digest(header.slice(7)), 'hex');
    const owner = Object.entries(config.owners).find(([,expected]) => timingSafeEqual(hash, Buffer.from(expected, 'hex')))?.[0];
    if (!owner) throw new APIError('unauthorized', 401); return owner;
  };
  const server = createServer({ maxHeaderSize: 8192, requestTimeout: 30_000, headersTimeout: 10_000 }, (req, res) => {
    void (async () => {
      try {
        const url = new URL(req.url ?? '/', 'http://localhost');
        if (url.pathname === '/health' && req.method === 'GET') { send(res, 200, { status: 'ok' }); return; }
        const owner = auth(req);
        if (req.method === 'GET' && url.pathname === '/v1/config') {
          send(res, 200, { available: config.ready, policy_version: config.policyVersion, ...config.policy,
            limits: { images: 9, image_bytes: MAX_IMAGE, total_image_bytes: 9 * MAX_IMAGE, note_characters: 8000, jobs_per_minute: config.minuteLimit, attempts_per_utc_day: config.dailyLimit },
            capabilities: { images: ['image/jpeg','image/png','image/webp'], structured_output: true },
          }); return;
        }
        if (req.method === 'POST' && url.pathname === '/v1/uploads') {
          const policy = String(req.headers['x-boji-policy-version'] ?? ''); store.policy(policy); store.available();
          const bytes = await readBody(req, MAX_IMAGE);
          send(res, 201, await store.upload(owner, policy, String(req.headers['content-type']), bytes)); return;
        }
        if (req.method === 'POST' && url.pathname === '/v1/food-estimates') {
          if (req.headers['content-type'] !== 'application/json') throw new APIError('invalid_input', 415);
          let raw: unknown; try { raw = JSON.parse((await readBody(req, 64 * 1024)).toString('utf8')); } catch (e) { if (e instanceof APIError) throw e; throw new APIError('invalid_input'); }
          const row = store.submit(owner, submission(raw)); send(res, 202, store.view(row));
          if (!options.manualWorker) worker.kick(); return;
        }
        const match = /^\/v1\/food-estimates\/([\w-]{1,128})$/.exec(url.pathname);
        if (match && req.method === 'GET') { store.cleanup(); send(res, 200, store.view(store.owned(owner, match[1]!))); return; }
        if (match && req.method === 'DELETE') {
          const row = store.cancel(owner, match[1]!); worker.cancel(row.id); send(res, 200, store.view(row)); return;
        }
        throw new APIError('not_found', 404);
      } catch (error) {
        const safe = error instanceof APIError ? error : new APIError('internal_error', 500);
        log({ event: 'request_failed', code: safe.code });
        if (!res.headersSent) send(res, safe.status, { error: { code: safe.code } }, safe.retryAfter);
        req.resume();
      }
    })();
  });
  let interval: ReturnType<typeof setInterval> | undefined;
  return {
    store, worker, server,
    async listen(port = config.port) {
      await new Promise<void>((resolve, reject) => { server.once('error', reject); server.listen(port, config.host, () => { server.off('error', reject); resolve(); }); });
      store.recover();
      interval = setInterval(() => { try { store.cleanup(); if (!options.manualWorker) worker.kick(); } catch { log({ event: 'maintenance_failed', code: 'internal_error' }); } }, 60_000);
      interval.unref(); if (!options.manualWorker) worker.kick();
      const address = server.address(); if (!address || typeof address === 'string') throw new Error('Missing address');
      return `http://${config.host}:${address.port}`;
    },
    async close() {
      if (interval) clearInterval(interval);
      await new Promise<void>(resolve => { server.close(() => resolve()); server.closeIdleConnections(); });
      await worker.stop(); store.close();
    },
  };
}
