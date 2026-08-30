const CODE_TTL_SECONDS = 600;
const CODE_ATTEMPTS = 5;

const SESSION_TTL_SECONDS = 7 * 24 * 60 * 60;

const RESEND_COOLDOWN_SECONDS = 60;

const CODE_KEY = 'admin-otp/current';
const COOLDOWN_KEY = 'admin-otp/cooldown';

export const SESSION_COOKIE = 'rh_admin';

interface StoredCode {
  hash: string;
  expiresAt: number;
  attempts: number;
}

function toHex(buffer: ArrayBuffer): string {
  let out = '';
  for (const byte of new Uint8Array(buffer)) out += byte.toString(16).padStart(2, '0');
  return out;
}

async function digest(secret: string, info: string, payload: string): Promise<string> {
  const raw = new TextEncoder().encode(`${secret}:${info}:${payload}`);
  return toHex(await crypto.subtle.digest('SHA-256', raw));
}

function equalConstantTime(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function freshCode(): string {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return String(bytes[0]! % 1_000_000).padStart(6, '0');
}

export interface IssuedCode {
  code: string | null;
  retryAfterSec: number;
}

export async function issueCode(kv: KVNamespace, secret: string): Promise<IssuedCode> {
  if (!secret) throw new Error('signing secret is not configured');
  const cooling = await kv.get(COOLDOWN_KEY);
  if (cooling) {
    return { code: null, retryAfterSec: Number(cooling) || RESEND_COOLDOWN_SECONDS };
  }

  const code = freshCode();
  const stored: StoredCode = {
    hash: await digest(secret, 'admin-otp', code),
    expiresAt: Date.now() + CODE_TTL_SECONDS * 1000,
    attempts: 0,
  };
  await kv.put(CODE_KEY, JSON.stringify(stored), { expirationTtl: CODE_TTL_SECONDS });
  await kv.put(COOLDOWN_KEY, String(RESEND_COOLDOWN_SECONDS), {
    expirationTtl: RESEND_COOLDOWN_SECONDS,
  });
  return { code, retryAfterSec: 0 };
}

export async function verifyCode(
  kv: KVNamespace,
  secret: string,
  candidate: string,
): Promise<boolean> {
  if (!secret) return false;
  const raw = await kv.get<StoredCode>(CODE_KEY, 'json');
  if (!raw || raw.expiresAt < Date.now()) return false;

  const matches = equalConstantTime(raw.hash, await digest(secret, 'admin-otp', candidate));
  if (matches) {
    await kv.delete(CODE_KEY).catch(() => undefined);
    return true;
  }

  const attempts = raw.attempts + 1;
  if (attempts >= CODE_ATTEMPTS) {
    await kv.delete(CODE_KEY).catch(() => undefined);
    return false;
  }
  const ttl = Math.max(60, Math.ceil((raw.expiresAt - Date.now()) / 1000));
  await kv
    .put(CODE_KEY, JSON.stringify({ ...raw, attempts }), { expirationTtl: ttl })
    .catch(() => undefined);
  return false;
}

export async function issueSession(secret: string): Promise<string> {
  if (!secret) throw new Error('signing secret is not configured');
  const expiresAt = Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS;
  return `${expiresAt}.${await digest(secret, 'admin-session', String(expiresAt))}`;
}

export async function verifySession(secret: string, value: string): Promise<boolean> {

  if (!secret) return false;
  const [rawExpiry, signature] = value.split('.');
  if (!rawExpiry || !signature) return false;
  const expiresAt = Number(rawExpiry);
  if (!Number.isFinite(expiresAt) || expiresAt < Math.floor(Date.now() / 1000)) return false;
  return equalConstantTime(await digest(secret, 'admin-session', rawExpiry), signature);
}

export function sessionCookie(value: string): string {
  return (
    `${SESSION_COOKIE}=${value}; HttpOnly; Secure; SameSite=Lax; ` +
    `Path=/; Max-Age=${SESSION_TTL_SECONDS}`
  );
}

export function clearedSessionCookie(): string {
  return `${SESSION_COOKIE}=; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=0`;
}

export function readSessionCookie(req: Request): string {
  const match = (req.headers.get('Cookie') ?? '').match(/rh_admin=([^;\s]+)/);
  return match?.[1] ?? '';
}
