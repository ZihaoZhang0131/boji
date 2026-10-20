import { resolve } from 'node:path';
import { digest } from './contracts.js';

export type Config = ReturnType<typeof readConfig>;
export function readConfig(env: NodeJS.ProcessEnv = process.env) {
  let owners: Record<string, string>;
  try { owners = JSON.parse(env.BOJI_OWNERS_JSON ?? '{}'); } catch { throw new Error('BOJI_OWNERS_JSON must map owner IDs to SHA-256 token hashes'); }
  if (!owners || Array.isArray(owners) || !Object.keys(owners).length || Object.entries(owners).some(([k,v]) => !/^[\w-]{1,80}$/.test(k) || typeof v !== 'string' || !/^[a-f0-9]{64}$/.test(v))) throw new Error('BOJI_OWNERS_JSON requires at least one owner and token hash');
  const supplied = [env.PROVIDER_URL, env.PROVIDER_NAME, env.PROVIDER_MODEL, env.PROVIDER_KEY];
  const ready = supplied.every(x => !!x);
  if (supplied.some(Boolean) && !ready) throw new Error('Provider configuration must be complete or entirely absent');
  let providerURL: string | null = null;
  if (ready) {
    const u = new URL(env.PROVIDER_URL!);
    if (u.protocol !== 'https:' || u.username || u.password || u.hash || u.search) throw new Error('PROVIDER_URL must be an HTTPS chat-completions endpoint without credentials or query');
    providerURL = u.href;
    if (!env.POLICY_VERSION?.trim() || !env.PROVIDER_RETENTION?.trim()) throw new Error('POLICY_VERSION and PROVIDER_RETENTION are required');
  }
  const int = (key: string, fallback: number, max: number) => {
    const value = Number(env[key] ?? fallback);
    if (!Number.isSafeInteger(value) || value < 1 || value > max) throw new Error(`${key} is outside its supported range`);
    return value;
  };
  const policy = {
    provider: env.PROVIDER_NAME ?? null, model: env.PROVIDER_MODEL ?? null,
    revision: env.POLICY_VERSION ?? 'unconfigured', provider_retention: env.PROVIDER_RETENTION ?? '未配置',
    sent_data: ['选择的饮食照片', '该餐备注'], server_raw_retention_hours: 24, metadata_retention_days: 7,
    fee_payer: '使用服务部署者的模型账户；请求次数不是金额预算。', prompt_version: 'food-v1',
  };
  const policyVersion = `${policy.revision}:${digest(JSON.stringify({ ...policy, providerURL })).slice(0, 24)}`;
  return {
    owners, ready, providerURL, providerKey: env.PROVIDER_KEY ?? null, policy, policyVersion,
    dataDir: resolve(env.DATA_DIR ?? './data'), host: '127.0.0.1', port: int('PORT', 8787, 65535),
    dailyLimit: int('DAILY_ATTEMPTS', 50, 10000), minuteLimit: int('MINUTE_JOBS', 5, 100),
    providerTimeoutMS: 90_000, executionTimeoutMS: 120_000,
  };
}
