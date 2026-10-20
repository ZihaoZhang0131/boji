import { createHash } from 'node:crypto';
import { Decimal } from 'decimal.js';

export const DAY = 86_400_000;
export const MAX_IMAGE = 2 * 1024 * 1024;
export type ErrorCode = 'unauthorized' | 'invalid_input' | 'not_found' | 'not_configured' | 'policy_changed' | 'conflict' | 'quota_exceeded' | 'rate_limited' | 'provider_timeout' | 'upstream_outcome_unknown' | 'provider_unavailable' | 'invalid_model_output' | 'cannot_recognize' | 'cancelled' | 'expired' | 'internal_error';
export class APIError extends Error {
  constructor(public code: ErrorCode, public status = 400, public retryAfter?: number) { super(code); }
}
export const digest = (input: string | Buffer): string => createHash('sha256').update(input).digest('hex');
export type Submission = {
  request_id: string; request_created_at: string; record_id: string;
  input_revision: number; lifecycle_epoch: number; image_refs: string[];
  note: string; locale: string; policy_version: string; retry_of?: string;
};
export type FoodResult = {
  items: { name: string; estimated_grams: number | null; kcal: number; assumptions: string[] }[];
  total_kcal: number; estimate_range: { low: number; high: number } | null; questions: string[];
};
export function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new APIError('invalid_input');
  return value as Record<string, unknown>;
}
function text(value: unknown, max: number, allowEmpty = false): string {
  if (typeof value !== 'string' || value.length > max || (!allowEmpty && !value.trim())) throw new APIError('invalid_input');
  return value;
}
const identifier = (v: unknown) => {
  const s = text(v, 128); if (!/^[a-zA-Z0-9_-]+$/.test(s)) throw new APIError('invalid_input'); return s;
};
export function submission(value: unknown): Submission {
  const v = object(value);
  const allowed = ['request_id', 'request_created_at', 'record_id', 'input_revision', 'lifecycle_epoch', 'image_refs', 'note', 'locale', 'policy_version', 'retry_of'];
  if (Object.keys(v).some(k => !allowed.includes(k))) throw new APIError('invalid_input');
  for (const n of [v.input_revision, v.lifecycle_epoch]) if (!Number.isSafeInteger(n) || (n as number) < 0) throw new APIError('invalid_input');
  if (!Array.isArray(v.image_refs) || v.image_refs.length > 9) throw new APIError('invalid_input');
  const refs = v.image_refs.map(identifier);
  if (new Set(refs).size !== refs.length) throw new APIError('invalid_input');
  const note = text(v.note, 8000, true);
  if (!refs.length && !note.trim()) throw new APIError('invalid_input');
  const date = text(v.request_created_at, 32);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/.test(date) || !Number.isFinite(Date.parse(date))) throw new APIError('invalid_input');
  return {
    request_id: identifier(v.request_id), request_created_at: date, record_id: identifier(v.record_id),
    input_revision: v.input_revision as number, lifecycle_epoch: v.lifecycle_epoch as number,
    image_refs: refs, note, locale: text(v.locale, 32), policy_version: text(v.policy_version, 200),
    ...(v.retry_of === undefined ? {} : { retry_of: identifier(v.retry_of) }),
  };
}
export function validateModelResult(value: unknown): FoodResult {
  try {
    const v = object(value);
    if (v.recognized === false) throw new APIError('cannot_recognize', 422);
    if (v.recognized !== true || !Array.isArray(v.items) || !v.items.length || v.items.length > 100) throw new Error();
    const numeric = (x: unknown, max = 10000) => {
      if (typeof x !== 'number' || !Number.isFinite(x) || x < 0 || x > max) throw new Error();
      return x;
    };
    const strings = (x: unknown) => {
      if (!Array.isArray(x) || x.length > 30) throw new Error();
      return x.map(s => text(s, 1000));
    };
    const items = v.items.map(raw => {
      const item = object(raw);
      return { name: text(item.name, 200), estimated_grams: item.estimated_grams === null ? null : numeric(item.estimated_grams, 100000), kcal: numeric(item.kcal), assumptions: strings(item.assumptions) };
    });
    const total = numeric(v.total_kcal);
    if (!items.reduce((sum, x) => sum.plus(x.kcal), new Decimal(0)).equals(new Decimal(total))) throw new Error();
    let range: FoodResult['estimate_range'] = null;
    if (v.estimate_range !== null && v.estimate_range !== undefined) {
      const r = object(v.estimate_range); range = { low: numeric(r.low), high: numeric(r.high) };
      if (range.low > total || range.high < total) throw new Error();
    }
    return { items, total_kcal: total, estimate_range: range, questions: strings(v.questions) };
  } catch (error) {
    if (error instanceof APIError && error.code === 'cannot_recognize') throw error;
    throw new APIError('invalid_model_output', 502);
  }
}
