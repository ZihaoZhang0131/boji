import { APIError, validateModelResult, type Submission } from './contracts.js';
import { Store } from './store.js';
import type { Provider } from './provider.js';

export type SafeLog = (event: { event: string; job_id?: string; code?: string }) => void;
export class Worker {
  private running = false;
  private stopped = false;
  private active?: { id: string; controller: AbortController };
  private work: Promise<void> = Promise.resolve();
  constructor(private store: Store, private provider: Provider, private log: SafeLog = () => {}) {}
  kick() {
    if (this.running || this.stopped) return;
    this.running = true;
    this.work = this.drain().catch(() => {
      // A disk failure may prevent writing a terminal state. Leave the durable job
      // untouched for restart recovery and never expose the underlying exception.
      this.log({ event: 'worker_storage_failed', code: 'internal_error' });
    }).finally(() => { this.running = false; });
  }
  private async drain() {
    for (let row = this.store.next(); row && !this.stopped; row = this.store.next()) {
      const start = Date.now();
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        const images = this.store.images(row);
        if (Date.now() - start >= this.store.config.executionTimeoutMS) throw new APIError('provider_timeout', 504);
        if (!this.store.claim(row.id)) continue;
        const controller = new AbortController(); this.active = { id: row.id, controller };
        const timeout = Math.min(this.store.config.providerTimeoutMS, this.store.config.executionTimeoutMS - (Date.now() - start));
        const deadline = new Promise<never>((_, reject) => {
          timer = setTimeout(() => { reject(new APIError('provider_timeout', 504)); controller.abort(); }, timeout);
          controller.signal.addEventListener('abort', () => reject(new APIError('cancelled', 409)), { once: true });
        });
        const result = await Promise.race([this.provider(JSON.parse(row.body!) as Submission, images, controller.signal), deadline]);
        // The production adapter validates too; injected adapters cannot bypass the final persistence boundary.
        const checked = validateModelResult({ recognized: true, ...result });
        this.store.policy(row.policy_version);
        this.store.finish(row.id, 'succeeded', null, {
          ...checked, source: 'model_estimate', provider: this.store.config.policy.provider, model: this.store.config.policy.model,
          prompt_version: this.store.config.policy.prompt_version, created_at: new Date(this.store.now()).toISOString(),
        });
        this.log({ event: 'job_finished', job_id: row.id });
      } catch (error) {
        const code = error instanceof APIError ? error.code : 'upstream_outcome_unknown';
        this.store.finish(row.id, 'failed', code); this.log({ event: 'job_failed', job_id: row.id, code });
      } finally { if (timer) clearTimeout(timer); this.active = undefined; }
    }
  }
  cancel(id: string) { if (this.active?.id === id) this.active.controller.abort(); }
  async idle() { await this.work; }
  async stop() {
    this.stopped = true;
    if (this.active) {
      this.store.finish(this.active.id, 'failed', 'upstream_outcome_unknown');
      this.active.controller.abort();
    }
    await this.work;
  }
}
