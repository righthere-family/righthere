import type { Env } from './index';
import { pushToFamily } from './apns';
import { db } from './db';
import { syncStorefront } from './storefront';
import { tgCall } from './telegram';
import { checkLock, noteFailure, noteSuccess } from './throttle';
import {
  clearedSessionCookie,
  issueCode,
  issueSession,
  readSessionCookie,
  sessionCookie,
  verifyCode,
  verifySession,
} from './otp';

export async function handleAdmin(req: Request, env: Env): Promise<Response> {
  const url = new URL(req.url);

  if (url.pathname === '/admin' && req.method === 'GET') {

    const opening = readSessionCookie(req);
    const signedIn =
      !!env.TELEGRAM_WEBHOOK_SECRET &&
      opening !== '' &&
      (await verifySession(env.TELEGRAM_WEBHOOK_SECRET, opening));
    return new Response(signedIn ? PAGE.replace('<html lang="ru">', '<html lang="ru" class="authed">') : PAGE, {
      headers: {
        'content-type': 'text/html; charset=utf-8',

        'cache-control': 'private, no-store',
      },
    });
  }

  if (!env.ADMIN_MAIL || !env.ADMIN_EMAIL) {
    return new Response('ADMIN_EMAIL is not configured', { status: 503 });
  }

  const secret = env.TELEGRAM_WEBHOOK_SECRET;
  if (!secret) {
    return new Response('signing secret is not configured', { status: 503 });
  }

  const json = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });

  if (url.pathname === '/admin/logout' && req.method === 'POST') {
    return new Response(JSON.stringify({ ok: true }), {
      headers: { 'content-type': 'application/json', 'set-cookie': clearedSessionCookie() },
    });
  }

  if (url.pathname === '/admin/otp/request' && req.method === 'POST') {
    const issued = await issueCode(env.SYSTEM, secret);
    if (!issued.code) {
      return json({ error: 'too soon', retry_after: issued.retryAfterSec }, 429);
    }
    try {
      await env.ADMIN_MAIL.send({
        to: env.ADMIN_EMAIL,
        from: 'no-reply@righthere.family',
        subject: 'Код для входа в админку «Мама, я рядом»',
        text:
          `Код: ${issued.code}\n\n` +
          'Он действует 10 минут и срабатывает один раз.\n\n' +
          'Если код запрашивали не вы — значит кто-то знает адрес панели. ' +
          'Сам по себе код ему ничего не даёт, но ключ администратора стоит сменить.',
      });
    } catch (err) {
      await db(env).logEvent('error', 'admin-otp', String(err).slice(0, 200));
      return json({ error: 'could not send' }, 502);
    }
    return json({ ok: true });
  }

  if (url.pathname === '/admin/otp/verify' && req.method === 'POST') {
    const ipForCode = req.headers.get('CF-Connecting-IP') ?? 'unknown';
    const codeLock = await checkLock(env.SYSTEM, ipForCode);
    if (codeLock.locked) {
      return json({ error: 'too many attempts', retry_after: codeLock.retryAfterSec }, 429);
    }
    const body = await req.json<{ code?: string }>().catch(() => ({ code: undefined }));
    const code = (body.code ?? '').trim();
    if (!/^\d{6}$/.test(code) || !(await verifyCode(env.SYSTEM, secret, code))) {
      await noteFailure(env.SYSTEM, ipForCode);
      return json({ error: 'wrong code' }, 403);
    }
    await noteSuccess(env.SYSTEM, ipForCode);
    return new Response(JSON.stringify({ ok: true }), {
      headers: {
        'content-type': 'application/json',
        'set-cookie': sessionCookie(await issueSession(secret)),
      },
    });
  }

  const session = readSessionCookie(req);
  if (session && (await verifySession(secret, session))) {
    return handleAuthorised(req, env, url);
  }
  return new Response('forbidden', { status: 403 });
}

async function handleAuthorised(req: Request, env: Env, url: URL): Promise<Response> {
  const d = db(env);
  const json = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });

  if (url.pathname === '/admin/api/overview' && req.method === 'GET') {
    return json(await d.adminOverview());
  }
  const famMatch = url.pathname.match(/^\/admin\/api\/family\/([0-9a-f-]{36})$/);
  if (famMatch && req.method === 'GET') {
    return json(await d.adminFamily(famMatch[1]!));
  }
  const parentMatch = url.pathname.match(/^\/admin\/api\/parent\/([0-9a-f-]{36})$/);
  if (parentMatch && req.method === 'PATCH') {
    const body = await req.json<Record<string, unknown>>();
    return json({ ok: await d.adminParentUpdate(parentMatch[1]!, body) });
  }

  const pushMatch = url.pathname.match(/^\/admin\/api\/family\/([0-9a-f-]{36})\/test-push$/);
  if (pushMatch && req.method === 'POST') {
    const devices = (await d.pushTargets(pushMatch[1]!)).length;
    if (devices === 0) return json({ ok: false, result: 'no-devices' });
    await pushToFamily(env, pushMatch[1]!, {
      title: 'Мама, я рядом',
      body: {
        ru: 'Тестовое уведомление — пуши доходят ✅',
        en: 'Test notification — pushes are coming through ✅',
      },
      level: 'time-sensitive',
      category: 'SERVICE',
    });

    return json({ ok: true, devices });
  }

  if (url.pathname === '/admin/api/broadcast' && req.method === 'POST') {
    const body = await req
      .json<{ title?: string; ru?: string; en?: string; family_ids?: string[] }>()
      .catch(() => ({}) as { title?: string; ru?: string; en?: string; family_ids?: string[] });
    const ruRaw = body.ru?.trim();
    const enRaw = body.en?.trim();
    if (!ruRaw && !enRaw) return json({ error: 'empty' }, 400);
    const ru = ruRaw || enRaw!;
    const en = enRaw || ruRaw!;
    const title = body.title?.trim() || 'Мама, я рядом';
    let ids = (body.family_ids ?? []).filter((v) => /^[0-9a-f-]{36}$/.test(v));
    if (ids.length === 0) {
      ids = await d.allFamilyIds();
    }
    let spent = 1;
    let sent = 0;
    let deferredFamilies = 0;
    for (const id of ids) {
      if (spent > 38) {
        deferredFamilies += 1;
        continue;
      }
      spent += await pushToFamily(
        env,
        id,
        { title, body: { ru, en }, level: 'active', category: 'SERVICE' },
        40 - spent,
      );
      sent += 1;
    }
    return json({ ok: true, sent, deferred: deferredFamilies });
  }

  if (url.pathname === '/admin/api/bot-broadcast' && req.method === 'POST') {
    const body = await req
      .json<{ ru?: string; en?: string; audience?: string }>()
      .catch(() => ({}) as { ru?: string; en?: string; audience?: string });
    const ruRaw = body.ru?.trim();
    const enRaw = body.en?.trim();
    if (!ruRaw && !enRaw) return json({ error: 'empty' }, 400);
    const ru = ruRaw || enRaw!;
    const en = enRaw || ruRaw!;
    const audience =
      body.audience === 'parents' || body.audience === 'waitlist' ? body.audience : 'all';
    const people = await d.botAudience(audience);
    let spent = 2;
    let sent = 0;
    let failed = 0;
    let deferred = 0;
    for (const person of people) {
      if (spent >= 38) {
        deferred += 1;
        continue;
      }
      spent += 1;
      const delivery = await d.send(person.telegram_user_id, {
        text: person.lang === 'en' ? en : ru,
      });
      if (delivery.kind === 'ok') sent += 1;
      else failed += 1;
    }
    await d.logEvent('warn', 'broadcast', `${audience}: sent ${sent}, failed ${failed}, deferred ${deferred}`);
    return json({ ok: true, total: people.length, sent, failed, deferred });
  }

  const grantMatch = url.pathname.match(/^\/admin\/api\/family\/([0-9a-f-]{36})\/premium$/);
  if (grantMatch && req.method === 'POST') {
    const body = await req.json<{ entitlement?: 'premium' | 'family' }>();
    const result = await d.adminGrantPremium(grantMatch[1]!, body.entitlement ?? 'premium');
    return json({ ok: result === 'ok', result });
  }
  if (grantMatch && req.method === 'DELETE') {
    const result = await d.adminRevokePremium(grantMatch[1]!);
    return json({ ok: result === 'ok' || result === 'nothing', result });
  }

  if (url.pathname === '/admin/api/storefront' && req.method === 'POST') {
    return json(await syncStorefront(env.TELEGRAM_BOT_TOKEN));
  }

  if (url.pathname === '/admin/api/webhook' && req.method === 'GET') {
    const info = await tgCall(env.TELEGRAM_BOT_TOKEN, 'getWebhookInfo');
    return json(info.kind === 'ok' ? info.result : { error: info });
  }

  if (url.pathname === '/admin/api/questions' && req.method === 'GET') {
    return json(await d.adminQuestions());
  }
  if (url.pathname === '/admin/api/questions' && req.method === 'POST') {
    const body = await req.json<{ text?: string; lang?: string }>();
    if (!body.text?.trim()) return json({ error: 'empty' }, 400);
    await d.adminQuestionAdd(body.text.trim(), body.lang === 'en' ? 'en' : 'ru');
    return json({ ok: true });
  }
  const qMatch = url.pathname.match(/^\/admin\/api\/questions\/([0-9a-f-]{36})$/);
  if (qMatch && req.method === 'PATCH') {
    const body = await req.json<{ text?: string; active?: boolean }>();
    await d.adminQuestionUpdate(qMatch[1]!, body);
    return json({ ok: true });
  }
  if (qMatch && req.method === 'DELETE') {
    await d.adminQuestionDelete(qMatch[1]!);
    return json({ ok: true });
  }

  const wlMatch = url.pathname.match(/^\/admin\/api\/waitlist\/(\d{1,15})(\/invite)?$/);
  if (wlMatch && wlMatch[2] && req.method === 'POST') {
    const result = await d.adminWaitlistInvite(Number(wlMatch[1]));
    return json({ ok: result === 'ok', result });
  }
  if (wlMatch && !wlMatch[2] && req.method === 'DELETE') {
    await d.adminWaitlistDelete(Number(wlMatch[1]));
    return json({ ok: true });
  }

  if (url.pathname === '/admin/api/texts' && req.method === 'GET') {
    return json(await d.adminTexts());
  }
  if (url.pathname === '/admin/api/texts' && req.method === 'POST') {
    const body = await req.json<{ group_key?: string; text?: string; lang?: string }>();
    if (!TEXT_GROUP_KEYS.includes(body.group_key ?? '') || !body.text?.trim()) {
      return json({ error: 'bad request' }, 400);
    }
    await d.adminTextAdd(body.group_key!, body.text.trim(), body.lang === 'en' ? 'en' : 'ru');
    return json({ ok: true });
  }
  const tMatch = url.pathname.match(/^\/admin\/api\/texts\/([0-9a-f-]{36})$/);
  if (tMatch && req.method === 'PATCH') {
    const body = await req.json<{ text?: string; active?: boolean }>();
    await d.adminTextUpdate(tMatch[1]!, body);
    return json({ ok: true });
  }
  if (tMatch && req.method === 'DELETE') {
    await d.adminTextDelete(tMatch[1]!);
    return json({ ok: true });
  }

  return new Response('not found', { status: 404 });
}

const TEXT_GROUP_KEYS = [
  'morning', 'ok_reply', 'reping', 'missed', 'meds', 'evening', 'story_ask',
  'digest_full', 'digest_most', 'digest_few',
  'milestone_7', 'milestone_30', 'milestone_100', 'milestone_365',
  'beta_invite',
];

const PAGE = `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Мама, я рядом — Админка</title>
<link rel="icon" type="image/png" sizes="64x64" href="data:image/png;base64,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">
<link rel="apple-touch-icon" sizes="180x180" href="data:image/png;base64,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">
<script>
</script>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; background: #F5F0E7; color: #33291F;
         font: 14px/1.5 -apple-system, system-ui, sans-serif; }
  .wrap { max-width: 960px; margin: 0 auto; padding: 28px 20px 60px; }
  h1 { font-family: Georgia, serif; font-size: 26px; margin: 0 0 22px; }
  h2 { font-size: 13px; letter-spacing: .06em; text-transform: uppercase;
       margin: 30px 0 12px; color: #9A6410; }
  .card { background: #fff; border-radius: 18px; padding: 18px 20px;
          box-shadow: 0 3px 14px rgba(51,41,31,.06); }
  #login { min-height: 100vh; display: flex; align-items: center; justify-content: center;
           padding: 20px; }
  html.authed #login { display: none; }
  #app { display: none; }
  html.authed #app { display: block; }
  .loginWrap { width: 100%; max-width: 320px; }
  #login h1 { text-align: center; font-size: 21px; margin: 0 0 18px; }
  .loginCard { padding: 24px 22px 20px; }
  .lead { margin: 0 0 16px; color: #7A6F62; font-size: 14px; line-height: 1.5; text-align: center; }
  button.wide { width: 100%; }
  .codeInput { width: 100%; box-sizing: border-box; margin-bottom: 12px; padding: 12px 0 12px 8px;
               font-size: 24px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
               letter-spacing: 8px; text-indent: 8px; text-align: center;
               border: 1px solid #E0D6C4; border-radius: 12px; background: #FFFDF8;
               color: #33291F; }
  .codeInput:focus { outline: none; border-color: #9A6410; }
  .codeInput.wrong { border-color: #8E3A4C; background: #FCF6F7; }
  button.linkish { width: 100%; margin-top: 10px; background: none; color: #7A6F62;
                   border: 0; padding: 8px; font-size: 13px; cursor: pointer; }
  button.linkish:hover { color: #9A6410; }
  button.linkish:disabled { color: #B9AE9E; cursor: default; }
  .hint { margin-top: 12px; font-size: 13px; line-height: 1.4; text-align: center;
          color: #7A6F62; min-height: 18px; }
  .hint.bad { color: #8E3A4C; }
  .stats { display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 10px; }
  .stat { background: #fff; border-radius: 16px; padding: 14px 16px;
          box-shadow: 0 3px 12px rgba(51,41,31,.05); }
  .stat b { display: block; font-size: 24px; font-family: Georgia, serif; }
  .stat span { font-size: 12px; color: #8C7F6D; }
  .chart { display: flex; align-items: flex-end; gap: 5px; height: 90px; padding-top: 6px; }
  .chart .col { flex: 1; display: flex; flex-direction: column; justify-content: flex-end;
                align-items: center; gap: 2px; height: 100%; }
  .chart .bar { width: 100%; border-radius: 4px 4px 0 0; min-height: 2px; }
  .chart .ok { background: #3F7A4E; }
  .chart .bad { background: #8E3A4C; border-radius: 0; }
  .chart .lbl { font-size: 9.5px; color: #A99C8B; white-space: nowrap; }
  table { border-collapse: collapse; width: 100%; }
  th, td { text-align: left; padding: 8px 12px 8px 0; border-bottom: 1px solid #F0EAE0;
           font-size: 13px; vertical-align: top; }
  tr:last-child td { border-bottom: none; }
  th { color: #8C7F6D; font-weight: 500; font-size: 12px; }
  input[type=text], input[type=password] {
    width: 100%; padding: 9px 11px; border: 1px solid #E0D6C4;
    border-radius: 10px; font-size: 14px; background: #FFFDF8; }
  button { background: #9A6410; color: #fff; border: 0; border-radius: 10px;
           padding: 8px 15px; font-size: 13px; cursor: pointer; }
  button.ghost { background: transparent; color: #9A6410; }
  button.danger { background: transparent; color: #8E3A4C; }
  .row { display: flex; gap: 8px; align-items: center; margin-bottom: 8px; }
  .muted { color: #8C7F6D; }
  .error { color: #8E3A4C; font-size: 13px; margin-top: 8px; min-height: 18px; }
  .pill { display: inline-block; border-radius: 99px; padding: 1px 9px; font-size: 11px; }
  .pill.active { background: #EAF0E6; color: #3F7A4E; }
  .pill.paused { background: #F5EEDF; color: #A5751B; }
  .pill.blocked, .pill.stopped { background: #F5E8EA; color: #8E3A4C; }
  .pill.invited, .pill.onboarding { background: #F0EAE0; color: #8C7F6D; }
  .pill.off { background: #F0EAE0; color: #8C7F6D; }
  .pill.lang { background: #EBE3F2; color: #6B4F8A; font-weight: 600; }
  .streak { color: #9A6410; font-weight: 600; }
  .stat.alert { background: #F9EDEF; }
  .stat.alert b { color: #8E3A4C; }
  .attention { background: #FBF4E3; border: 1px solid #EAD9AE; border-radius: 18px;
               padding: 14px 20px; margin-bottom: 18px; }
  .attention div { padding: 3px 0; }
  .lvl { display: inline-block; border-radius: 6px; padding: 0 6px; font-size: 11px;
         font-weight: 600; }
  .lvl.error { background: #F5E8EA; color: #8E3A4C; }
  .lvl.warn { background: #F5EEDF; color: #A5751B; }
  .famrow { cursor: pointer; }
  .famrow:hover td { background: #FCFAF4; }
  .famdetail { background: #FAF6EE; border-radius: 12px; padding: 14px 16px; }
  .pcard { border-top: 1px solid #EFE8DB; padding-top: 10px; margin-top: 10px; }
  .strip i { display: inline-block; width: 9px; height: 9px; border-radius: 50%;
             margin-right: 3px; }
  select { padding: 5px 8px; border: 1px solid #E0D6C4; border-radius: 8px;
           background: #FFFDF8; font-size: 13px; }
  .tabs { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 22px; }
  .tabs a { text-decoration: none; color: #7A6F62; font-size: 13px;
            padding: 7px 14px; border-radius: 99px; background: transparent; }
  .tabs a:hover { background: #EFE8DB; }
  .tabs a.active { background: #9A6410; color: #fff; }
  .tabs a.logout { margin-left: auto; color: #8E3A4C; }
  .tabs a.logout:hover { background: #F3E3E6; }
  section h2:first-child { margin-top: 0; }
  .saveflag { font-size: 12px; white-space: nowrap; min-width: 90px; }
  .wl-actions { text-align: right; white-space: nowrap; width: 1%; vertical-align: middle; }
  .wl-actions button { padding: 5px 12px; }
  #waitlist td { vertical-align: middle; }
  .saveflag.ok { color: #3F7A4E; }
  .saveflag.fail { color: #8E3A4C; }
  .chips { display: flex; gap: 8px; flex-wrap: wrap; }
  .chip { border: 1px solid #E0D6C4; border-radius: 99px; padding: 5px 14px;
          font-size: 13px; cursor: pointer; user-select: none; background: #FFFDF8;
          color: #7A6F62; }
  .chip:hover { border-color: #9A6410; }
  .chip.on { background: #9A6410; border-color: #9A6410; color: #fff; }
  .tgroup { margin-bottom: 18px; }
  .tgroup h3 { font-size: 13px; margin: 0 0 2px; }
  .tgroup .vars { font-size: 12px; color: #8C7F6D; margin-bottom: 8px; }
  textarea { width: 100%; padding: 8px 11px; border: 1px solid #E0D6C4;
             border-radius: 10px; font: 13px/1.45 -apple-system, system-ui, sans-serif;
             background: #FFFDF8; resize: vertical; }
</style>
</head>
<body>

<div id="login">
  <div class="loginWrap">
    <h1>Мама, я рядом</h1>
    <div class="card loginCard">
      <div id="askStep">
        <p class="lead">Пришлём одноразовый код на почту администратора.</p>
        <button class="wide" onclick="requestCode(this)">Прислать код</button>
      </div>

      <div id="codeStep" hidden>
        <p class="lead">Код отправлен на почту. Он действует 10 минут.</p>
        <input id="code" class="codeInput" inputmode="numeric" autocomplete="one-time-code"
               maxlength="6" aria-label="Код из письма"
               oninput="onCodeInput()" onkeydown="if(event.key==='Enter')submitCode()">
        <button class="wide" onclick="submitCode()">Войти</button>
        <button class="linkish" onclick="requestCode(this)">Прислать ещё раз</button>
      </div>

      <div id="codeHint" class="hint"></div>
    </div>
  </div>
</div>

<div id="app" class="wrap">
  <h1>Мама, я рядом — админка</h1>

  <nav class="tabs">
    <a href="#overview">Обзор</a>
    <a href="#families">Семьи</a>
    <a href="#broadcast">Рассылка</a>
    <a href="#texts">Тексты бота</a>
    <a href="#questions">Вопросы недели</a>
    <a href="#waitlist">Лист ожидания</a>
    <a href="#journal">Журнал</a>
    <a href="#" class="logout" onclick="logout();return false">Выйти</a>
  </nav>

  <section id="page-overview">
    <div id="attention"></div>
    <div class="stats" id="stats"></div>
    <h2>Телеграм</h2>
    <div class="card">
      <div id="webhook" class="muted">…</div>
      <div style="margin-top:10px">
        <button class="ghost" onclick="syncStorefront(this)">Сверить витрину бота</button>
        <span id="storefrontResult" class="muted"></span>
      </div>
    </div>
    <h2>Чек-ины за 14 дней</h2>
    <div class="card"><div class="chart" id="chart"></div></div>
  </section>

  <section id="page-families">
    <div class="card"><table id="families"></table></div>
  </section>

  <section id="page-broadcast">
    <div class="card">
      <div class="tgroup"><h3>Пуш-рассылка семьям</h3>
        <div class="vars">Каждое устройство получит текст своего языка. Достаточно одного языка — второй подставится.</div>
        <div class="row"><input type="text" id="bcTitle" placeholder="Заголовок (по умолчанию: Мама, я рядом)"></div>
        <div class="row"><textarea id="bcRu" rows="2" placeholder="Текст по-русски…"></textarea></div>
        <div class="row"><textarea id="bcEn" rows="2" placeholder="Text in English (optional)"></textarea></div>
        <div class="vars" style="margin-top:6px">Кому: ничего не выбрано — всем семьям; клик по семье выбирает, повторный — снимает.</div>
        <div class="chips" id="bcFamilies" style="margin-bottom:12px"></div>
        <div class="row">
          <button onclick="sendBroadcast(this)">Отправить</button>
          <span class="saveflag"></span>
        </div>
      </div>
    </div>
    <div class="card">
      <div class="tgroup"><h3>Сообщение в бота</h3>
        <div class="vars">Уйдёт в Telegram от имени бота — так люди узнают о новых функциях. Каждый получит текст своего языка; хватит одного, второй подставится.</div>
        <div class="row"><textarea id="tbRu" rows="4" placeholder="Текст по-русски…"></textarea></div>
        <div class="row"><textarea id="tbEn" rows="4" placeholder="Text in English (optional)"></textarea></div>
        <div class="row" style="gap:16px; flex-wrap:wrap">
          <label><input type="radio" name="tbAud" value="parents" checked> родителям в боте</label>
          <label><input type="radio" name="tbAud" value="waitlist"> листу ожидания</label>
          <label><input type="radio" name="tbAud" value="all"> всем</label>
        </div>
        <div class="row">
          <button onclick="sendBotBroadcast(this)">Отправить</button>
          <span class="saveflag"></span>
        </div>
      </div>
    </div>
  </section>

  <section id="page-texts">
    <div class="card">
      <div class="muted" style="margin-bottom:10px">
        Подстановки: {имя} — как бот обращается к родителю, {ребёнок}, {лекарство}, {вопрос},
        {дней}, {ответов}; в английских текстах — {name}, {child}, {medication}, {question},
        {days}, {answers}. Каждый родитель получает тексты своего языка (выбирается
        в приложении). Правки доезжают до бота в течение пары минут.
        Если выключить все варианты группы — бот вернётся к встроенному тексту этого языка.
      </div>
      <div id="texts"></div>
    </div>
  </section>

  <section id="page-questions">
    <div class="card">
      <div id="questions"></div>
      <div class="row" style="margin-top:12px">
        <select id="newQuestionLang"><option value="ru">RU</option><option value="en">EN</option></select>
        <input type="text" id="newQuestion" placeholder="Новый вопрос…"
               onkeydown="if(event.key==='Enter')addQuestion()">
        <button onclick="addQuestion()">Добавить</button>
      </div>
    </div>
  </section>

  <section id="page-waitlist">
    <div class="card"><table id="waitlist"></table></div>
    <div class="card"><table id="webleads"></table></div>
  </section>

  <section id="page-journal">
    <div class="card"><table id="events"></table></div>
  </section>
</div>

<script>
const api = (path, opts = {}) =>
  fetch('/admin/api/' + path, {
    ...opts,
    headers: { 'content-type': 'application/json', ...(opts.headers || {}) },
  }).then(r => { if (!r.ok) throw new Error(r.status); return r.json(); });

async function logout() {
  try {
    await fetch('/admin/logout', { method: 'POST' });
  } catch (e) {
  }
  location.reload();
}

function hint(text, bad) {
  const box = document.getElementById('codeHint');
  box.textContent = text;
  box.className = bad ? 'hint bad' : 'hint';
}

async function requestCode(button) {
  button.disabled = true;
  hint('отправляем…');
  try {
    const res = await fetch('/admin/otp/request', { method: 'POST' });
    const data = await res.json().catch(() => ({}));
    if (res.status === 429) {
      hint('код уже отправлен — следующий можно через ' + (data.retry_after || 60) + ' с', true);
    } else if (res.status === 503) {
      hint('почта не настроена — задайте ADMIN_EMAIL', true);
    } else if (!res.ok) {
      hint('не удалось отправить письмо', true);
    } else {
      document.getElementById('askStep').hidden = true;
      document.getElementById('codeStep').hidden = false;
      hint('');
      document.getElementById('code').focus();
    }
  } catch (e) {
    hint('не удалось отправить письмо', true);
  }
  setTimeout(() => { button.disabled = false; }, 60000);
}

function onCodeInput() {
  const field = document.getElementById('code');
  field.value = field.value.replace(/[^0-9]/g, '').slice(0, 6);
  field.classList.remove('wrong');
  if (field.value.length === 6) submitCode();
}

let submitting = false;

async function submitCode() {
  if (submitting) return;
  const field = document.getElementById('code');
  const code = field.value.trim();
  if (code.length !== 6) { hint('в коде шесть цифр', true); return; }

  submitting = true;
  hint('проверяем…');
  try {
    const res = await fetch('/admin/otp/verify', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ code }),
    });
    if (res.ok) {
      hint('');
      boot();
      return;
    }
    const data = await res.json().catch(() => ({}));
    field.classList.add('wrong');
    field.value = '';
    field.focus();
    hint(res.status === 429
      ? 'слишком много попыток — подождите ' + Math.ceil((data.retry_after || 3600) / 60) + ' мин'
      : 'код не подошёл', true);
  } catch (e) {
    hint('сеть не отвечает', true);
  }
  submitting = false;
}

async function loadWebhook() {
  const box = document.getElementById('webhook');
  try {
    const info = await api('webhook');
    if (info.error) { box.textContent = 'Телеграм не ответил'; return; }
    const pending = info.pending_update_count || 0;
    const updates = (info.allowed_updates || []).join(', ') || 'по умолчанию';
    const lastError = info.last_error_date
      ? new Date(info.last_error_date * 1000).toLocaleString('ru-RU')
      : 'не было';
    box.innerHTML =
      'В очереди: <b>' + pending + '</b>' +
      (pending > 50 ? ' — очередь растёт, проверьте воркер' : '') +
      '<br>Подписка: ' + esc(updates) +
      '<br>Последняя ошибка доставки: ' + esc(lastError) +
      ' <span class="muted">(телеграм не сбрасывает эту дату после успеха)</span>';
  } catch (e) {
    box.textContent = 'Не удалось прочитать статус';
  }
}

async function syncStorefront(button) {
  const out = document.getElementById('storefrontResult');
  button.disabled = true;
  out.textContent = ' сверяю…';
  try {
    const report = await api('storefront', { method: 'POST' });
    if (report.failed && report.failed.length) {
      out.textContent = ' ошибки: ' + report.failed.join('; ');
    } else if (report.changed && report.changed.length) {
      out.textContent = ' поправлено: ' + report.changed.join(', ');
    } else {
      out.textContent = ' всё совпадает (' + report.checked + ' проверок)';
    }
  } catch (e) {
    out.textContent = ' не получилось';
  }
  button.disabled = false;
}

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

const PAGES = ['overview', 'families', 'broadcast', 'texts', 'questions', 'waitlist', 'journal'];
function route() {
  const page = PAGES.includes(location.hash.slice(1)) ? location.hash.slice(1) : 'overview';
  PAGES.forEach(p => {
    document.getElementById('page-' + p).style.display = p === page ? '' : 'none';
  });
  document.querySelectorAll('.tabs a').forEach(a =>
    a.classList.toggle('active', a.getAttribute('href') === '#' + page));
}
window.addEventListener('hashchange', route);

function flag(el, ok, okText, failText) {
  const f = el.closest('.row') && el.closest('.row').querySelector('.saveflag');
  if (!f) return;
  f.textContent = ok ? (okText || '✓ сохранено') : (failText || 'не сохранилось');
  f.className = 'saveflag ' + (ok ? 'ok' : 'fail');
  clearTimeout(f._t);
  if (ok) f._t = setTimeout(() => { f.textContent = ''; }, 1600);
}

async function boot() {
  try {
    const data = await api('overview');
    document.documentElement.className = 'authed';
    renderAttention(data.attention);
    renderStats(data.stats);
    renderChart(data.daily);
    renderFamilies(data.families);
    renderWaitlist(data.waitlist);
    renderWebLeads(data.web_leads);
    renderEvents(data.events);
    loadWebhook();
    route();
    await loadQuestions();
    await loadTexts();
  } catch (e) {
    document.documentElement.className = '';
    if (e.message === '503') hint('почта не настроена — задайте ADMIN_EMAIL', true);
    else if (e.message !== '403') hint('ошибка: ' + e.message, true);
  }
}

function renderStats(s) {
  const items = [
    [s.families, 'семей'],
    [s.parents_active, 'активных родителей'],
    [s.checkins_today, 'чек-инов сегодня'],
    [s.checkins_7d, 'за 7 дней'],
    [s.stories, 'историй'],
    [s.postcards, 'открыток доставлено'],
    [s.waitlist, 'в листе ожидания'],
    [s.web_leads, 'заявок с сайта'],
    [s.errors_24h, 'ошибок за 24 часа', s.errors_24h > 0 ? 'alert' : '', 'journal'],
  ];
  document.getElementById('stats').innerHTML = items.map(([n, label, cls, link]) =>
    '<div class="stat ' + (cls || '') + '"' +
    (link ? ' style="cursor:pointer" onclick="location.hash=\\'' + link + '\\'"' : '') +
    '><b>' + (n ?? 0) + '</b><span>' + label + '</span></div>').join('');
}

const attentionText = {
  undelivered: 'утреннее сообщение сегодня не доставилось',
  blocked: 'заблокировала бота',
  stopped: 'остановила бота командой /stop',
  unlinked: 'приглашена, но так и не открыла бота',
};

function renderAttention(list) {
  const box = document.getElementById('attention');
  if (!list || !list.length) { box.innerHTML = ''; return; }
  box.innerHTML = '<div class="attention">' + list.map(a => {
    const who = esc(a.parent) + (a.child ? ' <span class="muted">(семья ' + esc(a.child) + ')</span>' : '');
    const what = a.kind === 'silent'
      ? 'молчит уже ' + a.days + ' ' + plural(a.days, 'день', 'дня', 'дней')
      : (attentionText[a.kind] || esc(a.kind));
    return '<div>⚠️ ' + who + ' — ' + what + '</div>';
  }).join('') + '</div>';
}

function plural(n, one, few, many) {
  const m10 = n % 10, m100 = n % 100;
  if (m10 === 1 && m100 !== 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

function renderEvents(events) {
  const rows = (events || []).map(e =>
    '<tr><td class="muted" style="white-space:nowrap">' + esc(e.at) + '</td>' +
    '<td><span class="lvl ' + esc(e.level) + '">' + esc(e.level) + '</span></td>' +
    '<td>' + esc(e.kind) + '</td><td class="muted">' + esc(e.detail) + '</td></tr>').join('');
  document.getElementById('events').innerHTML =
    rows || '<tr><td class="muted">тихо — ошибок не было</td></tr>';
}

function renderChart(daily) {
  const max = Math.max(1, ...daily.map(d => d.ok + d.not_ok));
  document.getElementById('chart').innerHTML = daily.map(d => {
    const okH = Math.round(d.ok / max * 64);
    const badH = Math.round(d.not_ok / max * 64);
    return '<div class="col">' +
      (d.not_ok ? '<div class="bar bad" style="height:' + badH + 'px"></div>' : '') +
      '<div class="bar ok" style="height:' + okH + 'px"></div>' +
      '<div class="lbl">' + esc(d.date) + '</div></div>';
  }).join('');
}

function renderFamilies(families) {
  const rows = families.map(f => {
    const parents = (f.parents || []).map(p =>
      '<div>' + esc(p.display_name) + ' · ' + esc(p.city || '—') +
      ' <span class="pill lang">' + esc((p.lang || 'ru').toUpperCase()) + '</span>' +
      ' <span class="pill ' + esc(p.bot_state) + '">' + esc(p.bot_state) + '</span>' +
      (p.last_date ? ' · чекин ' + esc(p.last_date) + ' (' + esc(p.last_status) + ')' : ' · чекинов не было') +
      (p.streak > 1 ? ' · <span class="streak">✦ ' + p.streak + '</span>' : '') +
      '</div>'
    ).join('');
    return '<tr class="famrow" onclick="toggleFamily(\\'' + f.id + '\\')">' +
      '<td>' + esc(f.child || '—') + '<div class="muted">' + esc(f.created_at) +
      ' · членов: ' + f.members + ' · историй: ' + f.stories + '</div></td><td>' + parents + '</td></tr>' +
      '<tr id="fam-' + f.id + '" class="detail" style="display:none"><td colspan="2"></td></tr>';
  }).join('');
  document.getElementById('families').innerHTML =
    '<tr><th>Семья</th><th>Родители</th></tr>' + rows;
  document.getElementById('bcFamilies').innerHTML = families.map(f =>
    '<span class="chip" data-id="' + f.id + '" onclick="this.classList.toggle(\\'on\\')">' +
    esc(f.child || f.id.slice(0, 8)) + '</span>').join('');
}

async function sendBroadcast(btn) {
  const ru = document.getElementById('bcRu').value.trim();
  const en = document.getElementById('bcEn').value.trim();
  if (!ru && !en) { alert('Напиши текст — хватит любого одного языка.'); return; }
  const picked = [...document.querySelectorAll('#bcFamilies .chip.on')].map(c => c.dataset.id);
  const who = picked.length ? picked.length + ' выбранным семьям' : 'ВСЕМ семьям';
  if (!confirm('Отправить пуш ' + who + '?')) return;
  btn.disabled = true;
  try {
    const r = await api('broadcast', { method: 'POST', body: JSON.stringify({
      title: document.getElementById('bcTitle').value,
      ru, en, family_ids: picked,
    })});
    flag(btn, true, '✓ отправлено');
    alert('Отправлено семьям: ' + r.sent + (r.deferred ? '; не влезло в лимит: ' + r.deferred + ' — повтори для них отдельно' : ''));
  } catch (e) {
    flag(btn, false, null, 'не отправилось');
  }
  btn.disabled = false;
}

async function sendBotBroadcast(btn) {
  const ru = document.getElementById('tbRu').value.trim();
  const en = document.getElementById('tbEn').value.trim();
  if (!ru && !en) { alert('Напиши текст — хватит любого одного языка.'); return; }
  const audience = document.querySelector('input[name="tbAud"]:checked').value;
  const who = { parents: 'родителям в боте', waitlist: 'листу ожидания', all: 'всем, кто есть в боте' }[audience];
  if (!confirm('Отправить сообщение в бота ' + who + '?')) return;
  btn.disabled = true;
  try {
    const r = await api('bot-broadcast', { method: 'POST', body: JSON.stringify({ ru, en, audience }) });
    flag(btn, true, '✓ отправлено');
    alert('Получателей: ' + r.total + ', доставлено: ' + r.sent +
      (r.failed ? ', не доставлено: ' + r.failed : '') +
      (r.deferred ? ', не влезло в лимит: ' + r.deferred + ' — повтори позже' : ''));
    document.getElementById('tbRu').value = '';
    document.getElementById('tbEn').value = '';
  } catch (e) {
    flag(btn, false, null, 'не отправилось');
  }
  btn.disabled = false;
}

async function familyPush(id, btn) {
  const inputs = btn.closest('.row').querySelectorAll('input');
  const title = inputs[0].value;
  const ru = inputs[1].value.trim();
  const en = inputs[2].value.trim();
  if (!ru && !en) { alert('Напиши текст пуша — хватит любого одного языка.'); return; }
  btn.disabled = true;
  try {
    const r = await api('broadcast', { method: 'POST', body: JSON.stringify({
      title, ru, en, family_ids: [id],
    })});
    flag(btn, r.ok, '✓ отправлено', 'не отправилось');
    inputs.forEach(i => { i.value = ''; });
  } catch (e) {
    flag(btn, false, null, 'не отправилось');
  }
  btn.disabled = false;
}

async function toggleFamily(id) {
  const row = document.getElementById('fam-' + id);
  if (row.style.display !== 'none') { row.style.display = 'none'; return; }
  row.style.display = '';
  row.firstChild.innerHTML = '<span class="muted">Загрузка…</span>';
  const f = await api('family/' + id);
  row.firstChild.innerHTML = renderFamilyDetail(f);
}

function stripDots(strip) {
  const color = s => s === 'ok' || s === 'accidental_ok' ? '#3F7A4E'
    : s === 'not_ok' ? '#8E3A4C' : '#D8CDBB';
  return '<span class="strip">' + strip.map(d =>
    '<i title="' + esc(d.d) + '" style="background:' + color(d.s) + '"></i>').join('') + '</span>';
}

function renderFamilyDetail(f) {
  const joinURL = 'https://righthere.family/join/' + f.app_token;
  const sub = f.subscription
    ? esc(f.subscription.entitlement) + ' (' + esc(f.subscription.source) + ')'
    : 'нет';
  const parents = (f.parents || []).map(p => {
    const meds = (p.meds || []).map(m => esc(m.title) + ' — ' + (m.times || []).join(', ')).join('; ') || 'нет';
    return '<div class="pcard">' +
      '<b>' + esc(p.display_name) + '</b> · ' + esc(p.city || '—') + ' · ' + esc(p.timezone) +
      (p.connected ? '' : ' · <span class="pill off">не подключена</span>') +
      '<div style="margin:6px 0">' + stripDots(p.strip || []) + '</div>' +
      '<div class="muted">Лекарства: ' + meds + '</div>' +
      '<div class="row" style="margin-top:10px;flex-wrap:wrap">' +
        sel('Утро', p.id, 'checkin_time', ['07:00','08:00','09:00','10:00','11:00'], p.checkin_time) +
        sel('Вечер', p.id, 'evening_time', ['', '19:00','20:00','21:00','22:00'], p.evening_time || '') +
        sel('Окно', p.id, 'window_min', ['120','180','240'], String(p.window_min)) +
        sel('Бот', p.id, 'bot_state', ['active','paused'], p.bot_state) +
        sel('Язык', p.id, 'lang', ['ru','en'], p.lang || 'ru') +
        '<span class="saveflag"></span>' +
      '</div></div>';
  }).join('');
  const stories = (f.stories || []).map(s =>
    '<div style="margin-bottom:8px"><span class="muted">' + esc(s.question) + '</span><br>' +
    (s.answer ? '«' + esc(s.answer) + '»' : '') + (s.has_voice ? ' 🎙' : '') +
    ' <span class="muted">' + esc(s.at) + '</span></div>').join('') || '<span class="muted">пока нет</span>';
  return '<div class="famdetail">' +
    '<div class="row" style="flex-wrap:wrap"><span class="muted">Ссылка восстановления:</span>' +
    '<input type="text" readonly value="' + esc(joinURL) + '" style="max-width:340px" onclick="this.select()">' +
    '<button class="ghost" onclick="navigator.clipboard.writeText(\\'' + esc(joinURL) + '\\')">копировать</button></div>' +
    '<div class="row"><span class="muted">Подписка: ' + sub + '</span>' +
    '<button class="ghost" onclick="grant(\\'' + f.id + '\\', \\'premium\\')">выдать Премиум</button>' +
    '<button class="ghost" onclick="grant(\\'' + f.id + '\\', \\'family\\')">выдать Семейную</button>' +
    '<button class="danger" onclick="revoke(\\'' + f.id + '\\')">снять выданную</button>' +
    '<button class="ghost" onclick="testPush(\\'' + f.id + '\\', this)">тестовый пуш</button></div>' +
    '<div class="row" style="flex-wrap:wrap"><input type="text" placeholder="Заголовок (Мама, я рядом)" style="max-width:220px">' +
    '<input type="text" placeholder="Текст по-русски…" style="max-width:280px">' +
    '<input type="text" placeholder="Text in English" style="max-width:200px">' +
    '<button class="ghost" onclick="familyPush(\\'' + f.id + '\\', this)">отправить пуш</button>' +
    '<span class="saveflag"></span></div>' +
    parents +
    '<div style="margin-top:10px"><span class="muted">Истории:</span><div style="margin-top:6px">' + stories + '</div></div>' +
    '</div>';
}

function sel(label, parentId, field, options, current) {
  const opts = options.map(o =>
    '<option value="' + o + '"' + (o === current ? ' selected' : '') + '>' + (o || '—') + '</option>').join('');
  return '<label class="muted" style="display:flex;gap:4px;align-items:center">' + label +
    ' <select onchange="patchParent(\\'' + parentId + '\\', \\'' + field + '\\', this)">' + opts + '</select></label>';
}

async function patchParent(id, field, el) {
  const body = {};
  body[field] = field === 'window_min' ? Number(el.value) : (el.value || null);
  try {
    await api('parent/' + id, { method: 'PATCH', body: JSON.stringify(body) });
    flag(el, true);
  } catch (e) {
    flag(el, false);
  }
}

const grantErrors = {
  'rc-managed': 'Эту подписку ведёт RevenueCat — руками её снимать нельзя.',
  'nothing': 'Подписки и так нет.',
};

async function grant(id, entitlement) {
  const r = await api('family/' + id + '/premium', { method: 'POST', body: JSON.stringify({ entitlement }) });
  if (!r.ok) alert(grantErrors[r.result] || 'Не получилось: ' + r.result);
  await toggleFamily(id); await toggleFamily(id);
}

async function revoke(id) {
  const r = await api('family/' + id + '/premium', { method: 'DELETE' });
  if (!r.ok || r.result === 'nothing') alert(grantErrors[r.result] || 'Не получилось: ' + r.result);
  await toggleFamily(id); await toggleFamily(id);
}

async function testPush(id, btn) {
  btn.disabled = true;
  try {
    const r = await api('family/' + id + '/test-push', { method: 'POST' });
    alert(r.ok
      ? 'Отправлено на ' + r.devices + ' устройств(о). Если баннер не пришёл — смотри Журнал.'
      : 'Ни одного устройства с пуш-токеном в этой семье — открой приложение и разреши уведомления.');
  } catch (e) {
    alert('Не получилось отправить.');
  }
  btn.disabled = false;
}

const MOM_CHANNEL_LABELS = {
  telegram: 'Telegram',
  whatsapp: 'WhatsApp',
  sms: 'звонки и СМС',
  unknown: 'не знает',
};

function renderWaitlist(list) {
  const rows = (list || []).map(w => {
    const nick = w.username
      ? '<a href="https://t.me/' + esc(w.username) + '" target="_blank">@' + esc(w.username) + '</a>'
      : '<span class="muted">без ника</span>';
    const status = w.invited_at
      ? '<span class="pill active">приглашён ' + esc(w.invited_at) + '</span>'
      : '<button class="ghost" onclick="inviteWaitlist(' + w.telegram_user_id + ', this)">пригласить</button>';
    return '<tr id="wl-' + w.telegram_user_id + '"><td>' + esc(w.first_name || '—') +
      ' <span class="pill lang">' + esc((w.lang || 'ru').toUpperCase()) + '</span></td>' +
      '<td>' + nick + '</td>' +
      '<td>' + (w.mom_channel
        ? '<span class="pill">' + esc(MOM_CHANNEL_LABELS[w.mom_channel] || w.mom_channel) + '</span>'
        : '<span class="muted">—</span>') + '</td>' +
      '<td class="muted">' + esc(w.created_at) + '</td>' +
      '<td class="wl-actions">' + status +
      '<button class="danger" onclick="removeWaitlist(' + w.telegram_user_id + ')">удалить</button></td></tr>';
  }).join('');
  document.getElementById('waitlist').innerHTML =
    '<tr><th>Имя</th><th>Ник</th><th>Мама</th><th>Записался</th><th></th></tr>' +
    (rows || '<tr><td class="muted" colspan="5">пусто</td></tr>');
}

function renderWebLeads(list) {
  const rows = (list || []).map(l => {
    return '<tr><td>' + esc(l.email) +
      ' <span class="pill lang">' + esc((l.lang || 'ru').toUpperCase()) + '</span></td>' +
      '<td>' + (l.mom_channel
        ? '<span class="pill">' + esc(MOM_CHANNEL_LABELS[l.mom_channel] || l.mom_channel) + '</span>'
        : '<span class="muted">—</span>') + '</td>' +
      '<td class="muted">' + esc(l.created_at) + '</td></tr>';
  }).join('');
  document.getElementById('webleads').innerHTML =
    '<tr><th>Почта с сайта</th><th>Мама</th><th>Оставил</th></tr>' +
    (rows || '<tr><td class="muted" colspan="3">пусто</td></tr>');
}

const inviteErrors = {
  'template-incomplete':
    'В тексте приглашения остался незаполненный {…} — впиши ссылку на TestFlight во вкладке «Тексты бота».',
  'send-failed': 'Telegram не принял сообщение — возможно, человек заблокировал бота.',
};

async function inviteWaitlist(userId, btn) {
  if (!confirm('Отправить приглашение в бету?')) return;
  try {
    const r = await api('waitlist/' + userId + '/invite', { method: 'POST' });
    if (!r.ok) { alert(inviteErrors[r.result] || 'Не получилось: ' + r.result); return; }
    btn.outerHTML = '<span class="pill active">приглашён только что</span>';
  } catch (e) {
    alert('Не получилось отправить — проверь сеть и попробуй ещё раз.');
  }
}

async function removeWaitlist(userId) {
  if (!confirm('Убрать из листа ожидания?')) return;
  await api('waitlist/' + userId, { method: 'DELETE' });
  const row = document.getElementById('wl-' + userId);
  if (row) row.remove();
}

const langOrder = { ru: 0, en: 1 };

async function loadQuestions() {
  const questions = await api('questions');
  questions.sort((a, b) => (langOrder[a.lang] ?? 0) - (langOrder[b.lang] ?? 0));
  document.getElementById('questions').innerHTML = questions.map(q =>
    '<div class="row">' +
    '<span class="pill lang">' + esc((q.lang || 'ru').toUpperCase()) + '</span>' +
    '<span class="pill ' + (q.active ? 'active' : 'off') + '">' + (q.active ? 'вкл' : 'выкл') + '</span>' +
    '<input type="text" value="' + esc(q.text) + '" onchange="updateText(\\'' + q.id + '\\', this)">' +
    '<button class="ghost" onclick="toggle(\\'' + q.id + '\\', ' + !q.active + ')">' + (q.active ? 'выкл' : 'вкл') + '</button>' +
    '<button class="danger" onclick="removeQ(\\'' + q.id + '\\')">удалить</button>' +
    '<span class="saveflag"></span>' +
    '</div>').join('');
}

async function addQuestion() {
  const input = document.getElementById('newQuestion');
  const lang = document.getElementById('newQuestionLang').value;
  if (!input.value.trim()) return;
  await api('questions', { method: 'POST', body: JSON.stringify({ text: input.value, lang }) });
  input.value = '';
  await loadQuestions();
}

async function updateText(id, el) {
  if (!el.value.trim()) { flag(el, false); return; }
  try {
    await api('questions/' + id, { method: 'PATCH', body: JSON.stringify({ text: el.value }) });
    flag(el, true);
  } catch (e) {
    flag(el, false);
  }
}

async function toggle(id, active) {
  await api('questions/' + id, { method: 'PATCH', body: JSON.stringify({ active }) });
  await loadQuestions();
}

async function removeQ(id) {
  if (!confirm('Удалить вопрос?')) return;
  await api('questions/' + id, { method: 'DELETE' });
  await loadQuestions();
}

const TEXT_GROUPS = [
  ['morning', 'Утреннее приветствие', true],
  ['ok_reply', 'Ответ на «Всё хорошо»', true],
  ['reping', 'Повторный вопрос утром', true],
  ['missed', 'Утро прошло без ответа', false],
  ['meds', 'Напоминание о лекарстве', false],
  ['evening', 'Вечерний вопрос', false],
  ['story_ask', 'Вопрос недели (обёртка)', false],
  ['digest_full', 'Итоги недели: все дни', false],
  ['digest_most', 'Итоги недели: большинство дней', false],
  ['digest_few', 'Итоги недели: почти не виделись', false],
  ['milestone_7', 'Веха: неделя вместе', false],
  ['milestone_30', 'Веха: месяц', false],
  ['milestone_100', 'Веха: сто дней', false],
  ['milestone_365', 'Веха: год', false],
  ['beta_invite', 'Приглашение в бету', false],
];

async function loadTexts() {
  const rows = await api('texts');
  const byGroup = {};
  rows.forEach(t => (byGroup[t.group_key] ??= []).push(t));
  document.getElementById('texts').innerHTML = TEXT_GROUPS.map(([key, title, isPool]) => {
    const groupRows = (byGroup[key] || []).slice()
      .sort((a, b) => (langOrder[a.lang] ?? 0) - (langOrder[b.lang] ?? 0));
    const items = groupRows.map(t => {
      const lines = Math.max(1, Math.ceil(t.text.length / 90) + (t.text.match(/\\n/g) || []).length);
      return '<div class="row">' +
        '<span class="pill lang">' + esc((t.lang || 'ru').toUpperCase()) + '</span>' +
        '<span class="pill ' + (t.active ? 'active' : 'off') + '">' + (t.active ? 'вкл' : 'выкл') + '</span>' +
        '<textarea rows="' + lines + '" onchange="patchText(\\'' + t.id + '\\', this)">' + esc(t.text) + '</textarea>' +
        '<button class="ghost" onclick="toggleText(\\'' + t.id + '\\', ' + !t.active + ')">' + (t.active ? 'выкл' : 'вкл') + '</button>' +
        (isPool ? '<button class="danger" onclick="removeText(\\'' + t.id + '\\')">удалить</button>' : '') +
        '<span class="saveflag"></span>' +
        '</div>';
    }).join('');
    const adder = isPool
      ? '<div class="row"><select><option value="ru">RU</option><option value="en">EN</option></select>' +
        '<input type="text" placeholder="Новый вариант…" ' +
        'onkeydown="if(event.key===\\'Enter\\')addText(\\'' + key + '\\', this)">' +
        '<button onclick="addText(\\'' + key + '\\', this.previousElementSibling)">Добавить</button></div>'
      : '';
    return '<div class="tgroup"><h3>' + title + (isPool ? ' <span class="muted">(пул)</span>' : '') + '</h3>' +
      items + adder + '</div>';
  }).join('');
}

async function patchText(id, el) {
  if (!el.value.trim()) { flag(el, false); return; }
  try {
    await api('texts/' + id, { method: 'PATCH', body: JSON.stringify({ text: el.value }) });
    flag(el, true);
  } catch (e) {
    flag(el, false);
  }
}

async function toggleText(id, active) {
  await api('texts/' + id, { method: 'PATCH', body: JSON.stringify({ active }) });
  await loadTexts();
}

async function addText(group, input) {
  if (!input.value.trim()) return;
  const lang = input.previousElementSibling ? input.previousElementSibling.value : 'ru';
  await api('texts', { method: 'POST', body: JSON.stringify({ group_key: group, text: input.value, lang }) });
  await loadTexts();
}

async function removeText(id) {
  if (!confirm('Удалить вариант текста?')) return;
  await api('texts/' + id, { method: 'DELETE' });
  await loadTexts();
}

boot();
</script>
</body>
</html>`;
