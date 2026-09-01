import type { Env } from './index';
import { db } from './db';

export interface Push {
  title: string;
  body: string | { ru: string; en: string };
  level: 'passive' | 'active' | 'time-sensitive';
  silent?: boolean;
  category?: 'CHECKIN_OK' | 'NOT_OK' | 'ESCALATION' | 'SERVICE' | 'MESSAGE';
}

let jwtCache: { token: string; at: number } | null = null;

async function apnsJWT(env: Env): Promise<string | null> {
  if (!env.APNS_TEAM_ID || !env.APNS_KEY_ID || !env.APNS_P8) return null;
  if (jwtCache && Date.now() - jwtCache.at < 50 * 60_000) return jwtCache.token;

  const pem = env.APNS_P8.replace(/-----[A-Z ]+-----|\s/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );

  const b64url = (data: Uint8Array | string) => {
    const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data;
    let bin = '';
    for (const b of bytes) bin += String.fromCharCode(b);
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  };

  const header = b64url(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID }));
  const claims = b64url(
    JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) }),
  );
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const token = `${header}.${claims}.${b64url(new Uint8Array(signature))}`;
  jwtCache = { token, at: Date.now() };
  return token;
}

function isNight(timezone: string): boolean {
  try {
    const hour = Number(
      new Intl.DateTimeFormat('en-GB', { hour: 'numeric', hourCycle: 'h23', timeZone: timezone })
        .format(new Date()),
    );
    return hour >= 23 || hour < 8;
  } catch {
    return false;
  }
}

const MAX_PUSH_DEVICES = 10;

export async function pushToFamily(
  env: Env,
  familyId: string,
  push: Push,
  maxSubrequests = Infinity,
): Promise<number> {
  const jwt = await apnsJWT(env);
  if (!jwt) return 0;

  const d = db(env);
  const targets = await d.pushTargets(familyId);
  let spent = 1;
  let reached = 0;
  for (const target of targets) {

    if (push.level !== 'time-sensitive' && isNight(target.tz)) continue;

    if (reached >= MAX_PUSH_DEVICES || spent + 2 > maxSubrequests) break;
    reached += 1;

    const host =
      target.apns_env === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
    const res = await fetch(`https://${host}/3/device/${target.apns_token}`, {
      method: 'POST',
      headers: {
        authorization: `bearer ${jwt}`,
        'apns-topic': env.APNS_TOPIC ?? '',
        'apns-push-type': 'alert',
        'apns-priority': push.level === 'passive' ? '5' : '10',
        'apns-expiration': String(Math.floor(Date.now() / 1000) + 4 * 3600),
      },
      body: JSON.stringify({
        aps: {
          alert: {
            title: push.title,
            body:
              typeof push.body === 'string'
                ? push.body
                : target.lang === 'en'
                  ? push.body.en
                  : push.body.ru,
          },
          sound: push.level === 'passive' || push.silent ? undefined : 'default',
          'interruption-level': push.level,
          category: push.category,
        },
      }),
    }).catch(() => null);
    spent += 1;

    if (!res) continue;
    if (res.status === 410 || res.status === 400) {
      const reason = await res
        .json<{ reason?: string }>()
        .then((r) => r.reason)
        .catch(() => undefined);
      if (reason === 'Unregistered' || reason === 'BadDeviceToken') {
        await d.clearPushToken(target.user_id, familyId);
        spent += 1;
      } else if (res.status !== 410) {
        await d.logEvent('warn', 'apns', `${res.status} ${reason ?? ''} for family ${familyId}`);
        spent += 1;
      }
    } else if (!res.ok) {
      await d.logEvent('warn', 'apns', `${res.status} for family ${familyId}`);
      spent += 1;
    }
  }
  if (reached >= MAX_PUSH_DEVICES && targets.length > MAX_PUSH_DEVICES) {
    await d.logEvent('warn', 'apns', `family ${familyId}: ${targets.length} devices, capped at ${MAX_PUSH_DEVICES}`);
    spent += 1;
  }
  return spent;
}
