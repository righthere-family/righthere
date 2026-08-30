export type TgOutcome =
  | { kind: 'ok'; result: unknown }
  | { kind: 'retry'; afterSec: number; description: string }
  | { kind: 'gone'; description: string }
  | { kind: 'migrate'; chatId: number }
  | { kind: 'failed'; status: number; description: string };

const API_BASE = 'https://api.telegram.org';

const MAX_RETRY_SEC = 3600;

const DEFAULT_RETRY_SEC = 5;

const NETWORK_RETRY_SEC = 2;

const GONE: readonly { code: number; needle: string }[] = [
  { code: 403, needle: 'bot was blocked by the user' },
  { code: 403, needle: 'user is deactivated' },
  { code: 403, needle: 'bot was kicked from' },
  { code: 400, needle: 'chat not found' },
  { code: 400, needle: 'have no access to the user' },
];

const RETRY_CAP = { auth: 3, unknown: 5 } as const;
const tally = { auth: 0, unknown: 0 };

export async function tgCall(
  token: string,
  method: string,
  body?: unknown,
): Promise<TgOutcome> {
  return send(token, method, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {}),
  });
}

export async function tgUpload(
  token: string,
  method: string,
  form: FormData,
): Promise<TgOutcome> {

  return send(token, method, { method: 'POST', body: form });
}

export function isPermanent(outcome: TgOutcome): boolean {
  return outcome.kind === 'gone' || outcome.kind === 'failed';
}

async function send(token: string, method: string, init: RequestInit): Promise<TgOutcome> {
  let status: number;
  let retryAfterHeader: string | null;
  let raw: string;
  try {
    const res = await fetch(`${API_BASE}/bot${token}/${method}`, init);
    status = res.status;
    retryAfterHeader = res.headers.get('retry-after');

    raw = redact(await res.text().catch(() => ''), token);
  } catch (err) {
    return {
      kind: 'retry',
      afterSec: NETWORK_RETRY_SEC,
      description: redact(`network: ${String(err)}`, token),
    };
  }
  return classify(status, retryAfterHeader, parseEnvelope(raw), raw);
}

function classify(
  status: number,
  retryAfterHeader: string | null,
  envelope: TgEnvelope | null,
  raw: string,
): TgOutcome {
  if (envelope?.ok === true) {
    noteAnswered(true);
    return { kind: 'ok', result: envelope.result };
  }

  if (envelope === null) {
    if (status === 429 || status >= 500) {
      return {
        kind: 'retry',
        afterSec: retryAfterSec(undefined, retryAfterHeader),
        description: `${status} without a Telegram envelope: ${snippet(raw)}`,
      };
    }
    return capped('unknown', status, `no Telegram envelope: ${snippet(raw)}`);
  }

  const code = envelope.error_code ?? status;
  const description = envelope.description ?? `HTTP ${status}`;
  noteAnswered(code !== 401);

  const migrateTo = envelope.parameters?.migrate_to_chat_id;
  if (typeof migrateTo === 'number') {
    return { kind: 'migrate', chatId: migrateTo };
  }

  if (code < 400) {
    return capped('unknown', code, description);
  }

  if (code === 429 || code >= 500) {
    return {
      kind: 'retry',
      afterSec: retryAfterSec(envelope.parameters, retryAfterHeader),
      description,
    };
  }

  if (code === 401) {
    return capped('auth', code, description);
  }

  const lowered = description.toLowerCase();
  for (const entry of GONE) {
    if (code === entry.code && lowered.includes(entry.needle)) {
      return { kind: 'gone', description };
    }
  }

  return { kind: 'failed', status: code, description };
}

function capped(
  bucket: keyof typeof RETRY_CAP,
  status: number,
  description: string,
): TgOutcome {
  tally[bucket] += 1;
  const seen = tally[bucket];
  if (seen > RETRY_CAP[bucket]) {
    return { kind: 'failed', status, description: `${description} (${seen}x in a row)` };
  }
  return { kind: 'retry', afterSec: clampSec(DEFAULT_RETRY_SEC * seen), description };
}

function noteAnswered(tokenAccepted: boolean): void {
  tally.unknown = 0;
  if (tokenAccepted) tally.auth = 0;
}

interface TgParameters {
  retry_after?: number;
  migrate_to_chat_id?: number;
}

interface TgEnvelope {
  ok: boolean;
  result?: unknown;
  error_code?: number;
  description?: string;
  parameters?: TgParameters;
}

function parseEnvelope(raw: string): TgEnvelope | null {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof value !== 'object' || value === null) return null;
  const body = value as Record<string, unknown>;
  if (typeof body.ok !== 'boolean') return null;
  const params = body.parameters;
  const p =
    typeof params === 'object' && params !== null ? (params as Record<string, unknown>) : null;
  return {
    ok: body.ok,
    result: body.result,
    error_code: typeof body.error_code === 'number' ? body.error_code : undefined,
    description: typeof body.description === 'string' ? body.description : undefined,
    parameters: p
      ? {
          retry_after: typeof p.retry_after === 'number' ? p.retry_after : undefined,
          migrate_to_chat_id:
            typeof p.migrate_to_chat_id === 'number' ? p.migrate_to_chat_id : undefined,
        }
      : undefined,
  };
}

function retryAfterSec(params: TgParameters | undefined, header: string | null): number {

  if (typeof params?.retry_after === 'number' && Number.isFinite(params.retry_after)) {
    return clampSec(params.retry_after);
  }

  const fromHeader = header === null ? NaN : Number(header.trim());
  if (Number.isFinite(fromHeader) && fromHeader > 0) {
    return clampSec(fromHeader);
  }
  return DEFAULT_RETRY_SEC;
}

function clampSec(seconds: number): number {
  return Math.min(Math.max(Math.ceil(seconds), 1), MAX_RETRY_SEC);
}

function snippet(raw: string): string {
  const flat = raw.replace(/\s+/g, ' ').trim();
  if (flat === '') return '(empty body)';
  return flat.length > 120 ? `${flat.slice(0, 120)}…` : flat;
}

function redact(text: string, token: string): string {
  return token === '' ? text : text.split(token).join('[token]');
}
