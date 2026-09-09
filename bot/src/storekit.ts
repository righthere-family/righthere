const APPLE_ROOT_G3_SHA256 = '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179';

const OID_STOREKIT_LEAF = [0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x0b, 0x01];
const OID_P256 = [0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07];
const OID_P384 = [0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22];
const OID_ECDSA_SHA256 = [0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02];
const OID_ECDSA_SHA384 = [0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03];
const OID_ECDSA_SHA512 = [0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x04];

export interface AppleTransaction {
  bundleId?: string;
  productId?: string;
  originalTransactionId?: string;
  transactionId?: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  environment?: string;
  type?: string;
  signedDate?: number;
}

export interface AppleNotification {
  notificationType?: string;
  subtype?: string;
  data?: {
    bundleId?: string;
    environment?: string;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
}

interface Node {
  tag: number;
  start: number;
  body: number;
  end: number;
}

function readNode(bytes: Uint8Array, offset: number): Node {
  if (offset + 2 > bytes.length) throw new Error('der: truncated');
  const tag = bytes[offset]!;
  let length = bytes[offset + 1]!;
  let body = offset + 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4 || body + count > bytes.length) throw new Error('der: bad length');
    length = 0;
    for (let i = 0; i < count; i++) length = (length << 8) | bytes[body + i]!;
    body += count;
  }
  const end = body + length;
  if (end > bytes.length) throw new Error('der: overflow');
  return { tag, start: offset, body, end };
}

function children(bytes: Uint8Array, node: Node): Node[] {
  const out: Node[] = [];
  let offset = node.body;
  while (offset < node.end) {
    const child = readNode(bytes, offset);
    out.push(child);
    offset = child.end;
  }
  return out;
}

function whole(bytes: Uint8Array, node: Node): Uint8Array {
  return bytes.subarray(node.start, node.end);
}

function content(bytes: Uint8Array, node: Node): Uint8Array {
  return bytes.subarray(node.body, node.end);
}

function includesBytes(haystack: Uint8Array, needle: number[]): boolean {
  outer: for (let i = 0; i + needle.length <= haystack.length; i++) {
    for (let j = 0; j < needle.length; j++) {
      if (haystack[i + j] !== needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

function sameBytes(a: Uint8Array, b: number[]): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < b.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

function parseTime(bytes: Uint8Array, node: Node): number {
  const text = new TextDecoder().decode(content(bytes, node));
  const digits = node.tag === 0x17 ? `${Number(text.slice(0, 2)) >= 50 ? '19' : '20'}${text}` : text;
  const year = Number(digits.slice(0, 4));
  const month = Number(digits.slice(4, 6));
  const day = Number(digits.slice(6, 8));
  const hour = Number(digits.slice(8, 10));
  const minute = Number(digits.slice(10, 12));
  const second = Number(digits.slice(12, 14));
  return Date.UTC(year, month - 1, day, hour, minute, second);
}

interface Certificate {
  tbs: Uint8Array;
  signatureOid: Uint8Array;
  signature: Uint8Array;
  spki: Uint8Array;
  notBefore: number;
  notAfter: number;
}

function parseCertificate(der: Uint8Array): Certificate {
  const root = readNode(der, 0);
  const [tbsNode, algNode, sigNode] = children(der, root);
  if (!tbsNode || !algNode || !sigNode) throw new Error('cert: shape');
  const algOid = children(der, algNode)[0];
  if (!algOid) throw new Error('cert: algorithm');

  const fields = children(der, tbsNode);
  const shift = fields[0]?.tag === 0xa0 ? 1 : 0;
  const validity = fields[shift + 3];
  const spki = fields[shift + 5];
  if (!validity || !spki) throw new Error('cert: fields');
  const [notBefore, notAfter] = children(der, validity);
  if (!notBefore || !notAfter) throw new Error('cert: validity');

  return {
    tbs: whole(der, tbsNode),
    signatureOid: whole(der, algOid),
    signature: content(der, sigNode).subarray(1),
    spki: whole(der, spki),
    notBefore: parseTime(der, notBefore),
    notAfter: parseTime(der, notAfter),
  };
}

function curveOf(spki: Uint8Array): { name: 'P-256' | 'P-384'; size: number } | null {
  if (includesBytes(spki, OID_P256)) return { name: 'P-256', size: 32 };
  if (includesBytes(spki, OID_P384)) return { name: 'P-384', size: 48 };
  return null;
}

function hashOf(oid: Uint8Array): 'SHA-256' | 'SHA-384' | 'SHA-512' | null {
  if (sameBytes(oid, OID_ECDSA_SHA256)) return 'SHA-256';
  if (sameBytes(oid, OID_ECDSA_SHA384)) return 'SHA-384';
  if (sameBytes(oid, OID_ECDSA_SHA512)) return 'SHA-512';
  return null;
}

function derSignatureToRaw(der: Uint8Array, size: number): Uint8Array {
  const seq = readNode(der, 0);
  const [r, s] = children(der, seq);
  if (!r || !s) throw new Error('sig: shape');
  const out = new Uint8Array(size * 2);
  for (const [index, node] of [r, s].entries()) {
    let value = content(der, node);
    while (value.length > size && value[0] === 0) value = value.subarray(1);
    if (value.length > size) throw new Error('sig: size');
    out.set(value, index * size + (size - value.length));
  }
  return out;
}

async function verifyWithSpki(
  spki: Uint8Array,
  hash: 'SHA-256' | 'SHA-384' | 'SHA-512',
  signature: Uint8Array,
  data: Uint8Array,
): Promise<boolean> {
  const curve = curveOf(spki);
  if (!curve) return false;
  const key = await crypto.subtle.importKey('spki', spki, { name: 'ECDSA', namedCurve: curve.name }, false, ['verify']);
  return crypto.subtle.verify({ name: 'ECDSA', hash }, key, signature, data);
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return Array.from(digest, (b) => b.toString(16).padStart(2, '0')).join('');
}

function base64ToBytes(text: string): Uint8Array {
  const normalized = text.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

export async function verifyCertificateChain(certs: Uint8Array[], now = Date.now()): Promise<boolean> {
  if (certs.length < 2) return false;
  const root = certs[certs.length - 1]!;
  if ((await sha256Hex(root)) !== APPLE_ROOT_G3_SHA256) return false;

  for (let i = 0; i < certs.length; i++) {
    const cert = parseCertificate(certs[i]!);
    if (now < cert.notBefore || now > cert.notAfter) return false;
    if (i === certs.length - 1) continue;
    const issuer = parseCertificate(certs[i + 1]!);
    const hash = hashOf(cert.signatureOid);
    const curve = curveOf(issuer.spki);
    if (!hash || !curve) return false;
    const raw = derSignatureToRaw(cert.signature, curve.size);
    if (!(await verifyWithSpki(issuer.spki, hash, raw, cert.tbs))) return false;
  }
  return true;
}

export async function verifyJwsSignature(spki: Uint8Array, jws: string): Promise<boolean> {
  const [header, payload, signature] = jws.split('.');
  if (!header || !payload || !signature) return false;
  const raw = base64ToBytes(signature);
  if (raw.length !== 64) return false;
  const data = new TextEncoder().encode(`${header}.${payload}`);
  return verifyWithSpki(spki, 'SHA-256', raw, data);
}

export async function verifyAppleJWS<T>(jws: string, now = Date.now()): Promise<T | null> {
  try {
    const parts = jws.split('.');
    if (parts.length !== 3) return null;
    const header = JSON.parse(new TextDecoder().decode(base64ToBytes(parts[0]!))) as {
      alg?: string;
      x5c?: unknown;
    };
    if (header.alg !== 'ES256' || !Array.isArray(header.x5c) || header.x5c.length < 2) return null;
    const certs = header.x5c.map((item) => base64ToBytes(String(item)));
    if (!(await verifyCertificateChain(certs, now))) return null;

    const leaf = certs[0]!;
    if (!includesBytes(leaf, OID_STOREKIT_LEAF)) return null;
    const { spki } = parseCertificate(leaf);
    if (curveOf(spki)?.name !== 'P-256') return null;
    if (!(await verifyJwsSignature(spki, jws))) return null;

    return JSON.parse(new TextDecoder().decode(base64ToBytes(parts[1]!))) as T;
  } catch {
    return null;
  }
}

export function entitlementFor(productId: string | undefined): 'premium' | 'family' | null {
  if (!productId) return null;
  if (productId === 'righthere.family.yearly') return 'family';
  if (productId.startsWith('righthere.premium.')) return 'premium';
  return null;
}

export function subscriptionStatus(tx: AppleTransaction, now = Date.now()): 'active' | 'expired' | 'revoked' {
  if (tx.revocationDate) return 'revoked';
  if (tx.expiresDate && tx.expiresDate < now) return 'expired';
  return 'active';
}
