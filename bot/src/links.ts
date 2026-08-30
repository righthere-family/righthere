const SIGNING_INFO = 'story-voice-link';

export const LINK_TTL_SECONDS = 600;

async function signingKey(secret: string): Promise<CryptoKey> {

  if (!secret) throw new Error('signing secret is not configured');
  const raw = new TextEncoder().encode(`${secret}:${SIGNING_INFO}`);
  const digest = await crypto.subtle.digest('SHA-256', raw);
  return crypto.subtle.importKey('raw', digest, { name: 'HMAC', hash: 'SHA-256' }, false, [
    'sign',
  ]);
}

function toHex(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let out = '';
  for (const byte of bytes) out += byte.toString(16).padStart(2, '0');
  return out;
}

async function sign(secret: string, fileId: string, expiresAt: number): Promise<string> {
  const key = await signingKey(secret);
  const payload = new TextEncoder().encode(`${fileId}:${expiresAt}`);
  return toHex(await crypto.subtle.sign('HMAC', key, payload));
}

export interface VoiceLink {
  expiresAt: number;
  signature: string;
}

export async function signVoiceLink(secret: string, fileId: string): Promise<VoiceLink> {
  const expiresAt = Math.floor(Date.now() / 1000) + LINK_TTL_SECONDS;
  return { expiresAt, signature: await sign(secret, fileId, expiresAt) };
}

function equalConstantTime(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function verifyVoiceLink(
  secret: string,
  fileId: string,
  expiresAt: number,
  signature: string,
): Promise<boolean> {
  if (!secret) return false;
  if (!Number.isFinite(expiresAt) || expiresAt < Math.floor(Date.now() / 1000)) return false;
  return equalConstantTime(await sign(secret, fileId, expiresAt), signature);
}
