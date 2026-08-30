// Регистрация вебхука Telegram с secret_token и нужными allowed_updates.
// Использование: TELEGRAM_BOT_TOKEN=... TELEGRAM_WEBHOOK_SECRET=... WORKER_URL=https://mama-bot.<acc>.workers.dev node scripts/set-webhook.mjs
const token = process.env.TELEGRAM_BOT_TOKEN;
const secret = process.env.TELEGRAM_WEBHOOK_SECRET;
const base = process.env.WORKER_URL;
if (!token || !secret || !base) {
  console.error('Нужны TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET, WORKER_URL');
  process.exit(1);
}
const res = await fetch(`https://api.telegram.org/bot${token}/setWebhook`, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({
    url: `${base}/tg/${secret.slice(0, 16)}`,
    secret_token: secret,
    // message_reaction обязателен: 👍 на утреннем сообщении = чек-ин
    allowed_updates: ['message', 'callback_query', 'message_reaction', 'my_chat_member'],
    drop_pending_updates: true,
  }),
});
console.log(await res.json());
