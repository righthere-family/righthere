import type { UserFromGetMe } from 'grammy/types';
import { handleAdmin } from './admin';
import { signVoiceLink, verifyVoiceLink, LINK_TTL_SECONDS } from './links';
import { syncStorefront } from './storefront';
import { tgCall } from './telegram';
import { makeBot } from './bot';
import { runCronTick } from './checkin';
import { oggOpusToCaf } from './remux';
import { db } from './db';
import landingPage from './landing.html';
import landingPageEn from './landing-en.html';
import privacyPage from './privacy.html';
import privacyPageEn from './privacy-en.html';

let botInfo: UserFromGetMe | undefined;

const STOREFRONT_STAMP = 'storefront/checked-at';
const STOREFRONT_INTERVAL_MS = 24 * 60 * 60 * 1000;

async function storefrontDue(env: Env): Promise<boolean> {
  try {
    const last = Number((await env.SYSTEM.get(STOREFRONT_STAMP)) ?? '0');
    return !Number.isFinite(last) || Date.now() - last >= STOREFRONT_INTERVAL_MS;
  } catch {

    return false;
  }
}

async function reconcileStorefront(env: Env): Promise<void> {
  await env.SYSTEM.put(STOREFRONT_STAMP, String(Date.now())).catch(() => undefined);
  const report = await syncStorefront(env.TELEGRAM_BOT_TOKEN);
  if (report.failed.length > 0) {
    await db(env).logEvent('error', 'storefront', report.failed.join('; ').slice(0, 400));
    return;
  }
  if (report.changed.length > 0) {
    await db(env).logEvent('warn', 'storefront', `restored ${report.changed.join(', ')}`);
  }
}

let webhookChecked = false;

const ALLOWED_UPDATES = [
  'message',
  'callback_query',
  'message_reaction',

  'my_chat_member',
];

let cachedTgPath: string | null = null;

async function telegramPath(env: Env): Promise<string> {
  if (cachedTgPath) return cachedTgPath;
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(env.TELEGRAM_WEBHOOK_SECRET),
  );
  cachedTgPath = [...new Uint8Array(digest)]
    .slice(0, 12)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return cachedTgPath;
}

async function ensureWebhook(env: Env): Promise<void> {
  const desired = `https://api.righthere.family/tg/${await telegramPath(env)}`;

  const info = await tgCall(env.TELEGRAM_BOT_TOKEN, 'getWebhookInfo');
  if (info.kind !== 'ok') {
    webhookChecked = false;
    return;
  }
  const current = info.result as
    | { url?: string; allowed_updates?: string[]; pending_update_count?: number }
    | undefined;

  const subscribed = current?.allowed_updates ?? [];
  const complete = ALLOWED_UPDATES.every((kind) => subscribed.includes(kind));
  if (current?.url === desired && complete) return;
  const set = await tgCall(env.TELEGRAM_BOT_TOKEN, 'setWebhook', {
    url: desired,
    secret_token: env.TELEGRAM_WEBHOOK_SECRET,
    allowed_updates: ALLOWED_UPDATES,
  });
  if (set.kind === 'ok') {
    await db(env).logEvent('warn', 'webhook-move', `webhook moved to ${desired}`);
    return;
  }

  webhookChecked = false;
  await db(env).logEvent(
    'error',
    'webhook-move',
    `setWebhook failed: ${set.kind === 'retry' ? set.description : JSON.stringify(set)}`,
  );
}

export interface Env {
  POSTCARD_PHOTOS: KVNamespace;
  SYSTEM: KVNamespace;

  ADMIN_MAIL?: { send(message: { to: string; from: string; subject: string; text: string }): Promise<unknown> };
  TELEGRAM_BOT_TOKEN: string;
  TELEGRAM_WEBHOOK_SECRET: string;
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  RC_WEBHOOK_AUTH: string;
  ADMIN_EMAIL?: string;
  PREVIEW_KEY?: string;
  APNS_TOPIC?: string;
  APNS_TEAM_ID?: string;
  APNS_KEY_ID?: string;
  APNS_P8?: string;
}

function joinPage(token: string): string {
  return `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Мама, я рядом — приглашение в семью</title>
<style>
  body { margin: 0; background: #F5F0E7; color: #33291F;
         font: 17px/1.5 -apple-system, "SF Pro Text", system-ui, sans-serif;
         display: flex; min-height: 100vh; align-items: center; justify-content: center; }
  .card { background: #fff; border-radius: 24px; padding: 36px 28px; max-width: 340px;
          margin: 20px; box-shadow: 0 14px 40px rgba(51,41,31,.10); text-align: center; }
  h1 { font-family: Georgia, "Times New Roman", serif; font-weight: 600;
       font-size: 28px; margin: 18px 0 10px; }
  p { color: #7A6F62; font-size: 15px; margin: 0 0 22px; }
  .btn { display: block; background: #9A6410; color: #fff; text-decoration: none;
         font-weight: 600; font-size: 16px; padding: 15px 20px; border-radius: 16px; }
  .hint { font-size: 13px; color: #7A6F62; margin-top: 16px; }
  .mark { height: 26px; }
</style>
</head>
<body>
  <div class="card">
    <svg class="mark" viewBox="0 0 60 30" xmlns="http://www.w3.org/2000/svg">
      <path d="M 8 26 Q 30 -6 52 26" fill="none" stroke="#33291F" stroke-opacity=".35"
            stroke-width="1.6" stroke-linecap="round" stroke-dasharray="0.1 5"/>
      <circle cx="8" cy="26" r="3.4" fill="#B8791A"/>
      <circle cx="52" cy="26" r="3.4" fill="#33291F"/>
    </svg>
    <h1>Вас пригласили в&nbsp;семью</h1>
    <p>Откройте эту страницу на iPhone с установленным приложением «Мама, я рядом» — и вы будете видеть ту же карточку, что и вся семья.</p>
    <a class="btn" href="righthere://join/${token}">Открыть в приложении</a>
    <div class="hint">Приложение ещё не установлено? Попросите ссылку на TestFlight у того, кто вас пригласил.</div>
  </div>
</body>
</html>`;
}

function logApexHit(req: Request, url: URL): void {
  const ua = req.headers.get('User-Agent') ?? '';

  const path = url.pathname.startsWith('/join/') ? '/join/…' : url.pathname;
  console.log(JSON.stringify({
    tag: 'apex',
    path,
    ref: req.headers.get('Referer') ?? '',
    country: (req.cf?.country as string | undefined) ?? '',

    bot: /bot|crawl|spider|scan|curl|wget|python|headless|http-client|okhttp/i.test(ua),
    ua: ua.slice(0, 160),
  }));
}

function comingSoonPage(lang: 'ru' | 'en'): string {
  const title = lang === 'ru' ? 'Мама, я рядом' : 'Mom, I’m Right Here';
  const text =
    lang === 'ru'
      ? 'Скоро здесь появится кое-что тёплое: одна кнопка утром — и близкие знают, что всё хорошо.'
      : 'Something warm is coming: one button in the morning — and the family knows all is well.';
  const description =
    lang === 'ru'
      ? 'Одна кнопка утром — и близкие знают, что всё хорошо. Скоро.'
      : 'One button in the morning — and the family knows all is well. Soon.';
  const switcher =
    lang === 'ru' ? '<a class="lang" href="/en">EN</a>' : '<a class="lang" href="/">RU</a>';
  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<meta name="description" content="${description}">
<style>
  body { margin: 0; background: #F5F0E7; color: #33291F;
         font: 17px/1.6 -apple-system, "SF Pro Text", system-ui, sans-serif;
         display: flex; min-height: 100vh; align-items: center; justify-content: center;
         text-align: center; }
  .card { max-width: 380px; padding: 24px; }
  h1 { font-family: Georgia, "Times New Roman", serif; font-weight: 600;
       font-size: 34px; margin: 22px 0 12px; }
  p { color: #7A6F62; font-size: 16px; margin: 0 0 26px; }
  .mark { height: 34px; }
  .lang { position: fixed; top: 20px; right: 24px; color: #9A6410;
          text-decoration: none; font-size: 14px; }
</style>
</head>
<body>
  ${switcher}
  <div class="card">
    <svg class="mark" viewBox="0 0 60 30" xmlns="http://www.w3.org/2000/svg">
      <path d="M 8 26 Q 30 -6 52 26" fill="none" stroke="#33291F" stroke-opacity=".35"
            stroke-width="1.6" stroke-linecap="round" stroke-dasharray="0.1 5"/>
      <circle cx="8" cy="26" r="3.4" fill="#B8791A"/>
      <circle cx="52" cy="26" r="3.4" fill="#33291F"/>
    </svg>
    <h1>${title}</h1>
    <p>${text}</p>
  </div>
</body>
</html>`;
}

function previewLoginPage(wrongKey: boolean): string {
  return `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Предпросмотр</title>
<style>
  body { margin: 0; background: #F5F0E7; color: #33291F;
         font: 15px/1.5 -apple-system, system-ui, sans-serif;
         display: flex; min-height: 100vh; align-items: center; justify-content: center; }
  form { width: 300px; padding: 24px; background: #fff; border-radius: 18px;
         box-shadow: 0 3px 14px rgba(51,41,31,.06); }
  input { width: 100%; box-sizing: border-box; padding: 10px 12px; margin-bottom: 10px;
          border: 1px solid #E0D6C4; border-radius: 10px; font-size: 15px; background: #FFFDF8; }
  button { width: 100%; background: #9A6410; color: #fff; border: 0; border-radius: 10px;
           padding: 10px; font-size: 14px; cursor: pointer; }
  .err { color: #8E3A4C; font-size: 13px; margin: 0 0 10px; }
</style>
</head>
<body>
  <form method="post">
    ${wrongKey ? '<p class="err">Не подошло</p>' : ''}
    <input type="password" name="key" placeholder="Ключ предпросмотра" autofocus>
    <button>Смотреть лендинг</button>
  </form>
</body>
</html>`;
}

const PREVIEW_COOKIE = 'rh_preview';

function previewCookieValue(req: Request): string {
  const match = (req.headers.get('Cookie') ?? '').match(/rh_preview=([^;\s]+)/);
  return match?.[1] ?? '';
}

async function handleApex(req: Request, env: Env, url: URL): Promise<Response> {
  const html = (page: string, status = 200) =>
    new Response(page, { status, headers: { 'content-type': 'text/html; charset=utf-8' } });

  if (req.method === 'GET') logApexHit(req, url);

  const joinMatch = url.pathname.match(/^\/join\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/);
  if (req.method === 'GET' && joinMatch) {
    return html(joinPage(joinMatch[1]!));
  }

  if ((url.pathname === '/' || url.pathname === '/en') && req.method === 'GET') {
    const lang = url.pathname === '/en' ? 'en' : 'ru';
    const unlocked =
      !!env.PREVIEW_KEY && timingSafeEqual(previewCookieValue(req), env.PREVIEW_KEY);
    if (!unlocked) return html(comingSoonPage(lang));
    return html(lang === 'en' ? landingPageEn : landingPage);
  }

  if (url.pathname === '/privacy' && req.method === 'GET') {
    return html(privacyPage);
  }
  if (url.pathname === '/en/privacy' && req.method === 'GET') {
    return html(privacyPageEn);
  }

  if (url.pathname === '/preview') {
    if (req.method === 'POST' && env.PREVIEW_KEY) {
      const form = await req.formData();
      const key = String(form.get('key') ?? '');
      if (timingSafeEqual(key, env.PREVIEW_KEY)) {
        return new Response(null, {
          status: 303,
          headers: {
            Location: '/',
            'Set-Cookie':
              `${PREVIEW_COOKIE}=${key}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=2592000`,
          },
        });
      }
      return html(previewLoginPage(true), 403);
    }
    return html(previewLoginPage(false));
  }

  return new Response('not found', { status: 404 });
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);

    if (url.protocol === 'http:') {
      url.protocol = 'https:';
      return Response.redirect(url.toString(), 301);
    }

    if (url.hostname === 'righthere.family') {
      return handleApex(req, env, url);
    }

    if (url.hostname === 'admin.righthere.family' && !url.pathname.startsWith('/admin')) {
      if (url.pathname === '/' && req.method === 'GET') {
        return handleAdmin(new Request(new URL('/admin', url), req), env);
      }
      return new Response('not found', { status: 404 });
    }

    if (url.pathname === '/health') return new Response('ok');

    if (url.pathname === '/admin' || url.pathname.startsWith('/admin/')) {
      return handleAdmin(req, env);
    }

    const joinMatch = url.pathname.match(/^\/join\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/);
    if (req.method === 'GET' && joinMatch) {
      return new Response(joinPage(joinMatch[1]!), {
        headers: { 'content-type': 'text/html; charset=utf-8' },
      });
    }

    if (req.method === 'POST' && url.pathname === `/tg/${await telegramPath(env)}`) {
      const header = req.headers.get('X-Telegram-Bot-Api-Secret-Token') ?? '';
      if (!timingSafeEqual(header, env.TELEGRAM_WEBHOOK_SECRET)) {
        return new Response('forbidden', { status: 403 });
      }
      const bot = makeBot(env, botInfo);
      const update = await req.json();

      ctx.waitUntil(
        (async () => {
          try {
            if (!botInfo) {
              await bot.init();
              botInfo = bot.botInfo;
            }
            await bot.handleUpdate(update as never);
          } catch (err) {

            await db(env).logEvent('error', 'webhook', String(err));
          }
        })(),
      );
      return new Response('ok');
    }

    if (req.method === 'POST' && url.pathname === '/postcard-photo') {
      const token = req.headers.get('X-App-Token') ?? '';

      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(token)) {
        return new Response('forbidden', { status: 403 });
      }

      const MAX_PHOTO_BYTES = 5_000_000;
      const claimed = Number(req.headers.get('Content-Length') ?? '0');
      if (claimed > MAX_PHOTO_BYTES) {
        return new Response('too large', { status: 413 });
      }
      const bytes = await req.arrayBuffer();
      if (bytes.byteLength === 0 || bytes.byteLength > MAX_PHOTO_BYTES) {
        return new Response('too large', { status: 413 });
      }
      const path = await db(env).storePostcardPhoto(token, bytes);
      if (path === 'quota') return new Response('too many', { status: 429 });
      if (!path) return new Response('forbidden', { status: 403 });
      return new Response(JSON.stringify({ path }), {
        headers: { 'content-type': 'application/json' },
      });
    }

    if (req.method === 'POST' && url.pathname === '/story-voice/link') {
      const token = req.headers.get('X-App-Token') ?? '';
      const body = await req.json<{ file?: string }>().catch(() => ({ file: undefined }));
      const fileId = body.file ?? '';
      if (!/^[0-9a-f-]{36}$/.test(token) || !fileId) {
        return new Response('forbidden', { status: 403 });
      }
      const owns = await db(env).storyVoiceBelongs(token, fileId);
      if (!owns) return new Response('forbidden', { status: 403 });
      const link = await signVoiceLink(env.TELEGRAM_WEBHOOK_SECRET, fileId);
      const play = new URL('/story-voice', url.origin);
      play.searchParams.set('f', fileId);
      play.searchParams.set('e', String(link.expiresAt));
      play.searchParams.set('s', link.signature);
      return new Response(
        JSON.stringify({ url: play.toString(), expires_in: LINK_TTL_SECONDS }),
        { headers: { 'content-type': 'application/json' } },
      );
    }

    if (req.method === 'GET' && url.pathname === '/story-voice') {
      const fileId = url.searchParams.get('f') ?? '';
      const expiresAt = Number(url.searchParams.get('e') ?? '0');
      const signature = url.searchParams.get('s') ?? '';
      if (!fileId || !signature) return new Response('forbidden', { status: 403 });
      const valid = await verifyVoiceLink(
        env.TELEGRAM_WEBHOOK_SECRET,
        fileId,
        expiresAt,
        signature,
      );
      if (!valid) return new Response('forbidden', { status: 403 });
      const info = await fetch(
        `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/getFile?file_id=${encodeURIComponent(fileId)}`,
      ).then((r) => r.json<{ ok: boolean; result?: { file_path?: string } }>());
      const path = info.result?.file_path;
      if (!info.ok || !path) return new Response('not found', { status: 404 });
      const file = await fetch(`https://api.telegram.org/file/bot${env.TELEGRAM_BOT_TOKEN}/${path}`);

      const cache = { 'cache-control': 'private, max-age=300' };

      if (/\.(oga|ogg)$/i.test(path)) {
        try {
          const caf = oggOpusToCaf(new Uint8Array(await file.arrayBuffer()));
          return new Response(caf.buffer as ArrayBuffer, {
            headers: { ...cache, 'content-type': 'audio/x-caf' },
          });
        } catch (err) {
          await db(env).logEvent('warn', 'voice-remux', String(err));
          const retry = await fetch(`https://api.telegram.org/file/bot${env.TELEGRAM_BOT_TOKEN}/${path}`);
          return new Response(retry.body, {
            headers: { ...cache, 'content-type': 'audio/ogg' },
          });
        }
      }

      const type = /\.(jpe?g)$/i.test(path) ? 'image/jpeg'
        : /\.png$/i.test(path) ? 'image/png'
        : 'application/octet-stream';
      return new Response(file.body, { headers: { ...cache, 'content-type': type } });
    }

    if (req.method === 'POST' && url.pathname === '/rc-webhook') {
      const auth = req.headers.get('Authorization') ?? '';
      if (!timingSafeEqual(auth, env.RC_WEBHOOK_AUTH)) {
        return new Response('forbidden', { status: 403 });
      }
      const payload = await req.json<never>();
      ctx.waitUntil(db(env).applyRevenueCatEvent(payload));
      return new Response('ok');
    }

    return new Response('not found', { status: 404 });
  },

  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {

    const storefront = await storefrontDue(env);

    const reserve = (storefront ? 17 : 0) + (webhookChecked ? 0 : 3);
    ctx.waitUntil(runCronTick(env, reserve));
    if (storefront) {
      ctx.waitUntil(reconcileStorefront(env));
    }
    if (!webhookChecked) {
      webhookChecked = true;
      ctx.waitUntil(ensureWebhook(env));
    }
  },
} satisfies ExportedHandler<Env>;
