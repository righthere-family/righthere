const PER_IP_LIMIT = 5;
const PER_IP_LOCKOUT_SECONDS = 3600;

const GLOBAL_LIMIT = 30;
const GLOBAL_LOCKOUT_SECONDS = 900;

interface Counter {
  failures: number;
  lockedUntil: number;
}

function counterKey(scope: string, id: string): string {
  return `throttle/${scope}/${id}`;
}

async function read(kv: KVNamespace, key: string): Promise<Counter> {
  try {
    const stored = await kv.get<Counter>(key, 'json');
    if (stored && typeof stored.failures === 'number') return stored;
  } catch {

  }
  return { failures: 0, lockedUntil: 0 };
}

async function write(kv: KVNamespace, key: string, value: Counter, ttl: number): Promise<void> {
  await kv
    .put(key, JSON.stringify(value), { expirationTtl: Math.max(60, ttl) })
    .catch(() => undefined);
}

export interface LockState {
  locked: boolean;
  retryAfterSec: number;
  scope: 'ip' | 'global' | null;
}

export async function checkLock(kv: KVNamespace, ip: string): Promise<LockState> {
  const now = Date.now();
  const [perIp, global] = await Promise.all([
    read(kv, counterKey('admin-ip', ip)),
    read(kv, counterKey('admin', 'global')),
  ]);
  if (perIp.lockedUntil > now) {
    return { locked: true, retryAfterSec: Math.ceil((perIp.lockedUntil - now) / 1000), scope: 'ip' };
  }
  if (global.lockedUntil > now) {
    return {
      locked: true,
      retryAfterSec: Math.ceil((global.lockedUntil - now) / 1000),
      scope: 'global',
    };
  }
  return { locked: false, retryAfterSec: 0, scope: null };
}

export interface FailureResult {
  ipFailures: number;
  globalFailures: number;
  lockedScope: 'ip' | 'global' | null;
}

export async function noteFailure(kv: KVNamespace, ip: string): Promise<FailureResult> {
  const now = Date.now();
  const ipKey = counterKey('admin-ip', ip);
  const globalKey = counterKey('admin', 'global');
  const [perIp, global] = await Promise.all([read(kv, ipKey), read(kv, globalKey)]);

  perIp.failures += 1;
  global.failures += 1;
  let lockedScope: 'ip' | 'global' | null = null;

  if (perIp.failures >= PER_IP_LIMIT) {
    perIp.lockedUntil = now + PER_IP_LOCKOUT_SECONDS * 1000;
    perIp.failures = 0;
    lockedScope = 'ip';
  }
  if (global.failures >= GLOBAL_LIMIT) {
    global.lockedUntil = now + GLOBAL_LOCKOUT_SECONDS * 1000;
    global.failures = 0;
    lockedScope = 'global';
  }

  await Promise.all([
    write(kv, ipKey, perIp, PER_IP_LOCKOUT_SECONDS),
    write(kv, globalKey, global, GLOBAL_LOCKOUT_SECONDS),
  ]);
  return { ipFailures: perIp.failures, globalFailures: global.failures, lockedScope };
}

export async function noteSuccess(kv: KVNamespace, ip: string): Promise<void> {
  await kv.delete(counterKey('admin-ip', ip)).catch(() => undefined);
}
