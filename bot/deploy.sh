#!/usr/bin/env bash
# First-time deploy: worker + secrets + Telegram webhook.
# Secrets are read interactively or generated locally — nothing is echoed,
# nothing lands in shell history or chat.
set -euo pipefail
cd "$(dirname "$0")"

SUPABASE_URL="https://spfdqxgaetgfxzaltjlr.supabase.co"

read -r -s -p "Telegram bot token (from BotFather): " TG_TOKEN; echo
read -r -s -p "Supabase secret key (sb_secret_...): " SB_SECRET; echo
if [[ -z "$TG_TOKEN" || -z "$SB_SECRET" ]]; then
  echo "Both values are required." >&2
  exit 1
fi

WEBHOOK_SECRET=$(openssl rand -hex 32)
RC_AUTH=$(openssl rand -hex 24)

echo "==> Deploying worker"
DEPLOY_OUT=$(npx wrangler deploy 2>&1 | tee /dev/stderr)
WORKER_URL=$(echo "$DEPLOY_OUT" | grep -oE 'https://[a-z0-9.-]+\.workers\.dev' | head -1)
if [[ -z "$WORKER_URL" ]]; then
  echo "Could not detect workers.dev URL in deploy output." >&2
  exit 1
fi

echo "==> Setting secrets"
printf '%s' "$TG_TOKEN"        | npx wrangler secret put TELEGRAM_BOT_TOKEN
printf '%s' "$WEBHOOK_SECRET"  | npx wrangler secret put TELEGRAM_WEBHOOK_SECRET
printf '%s' "$SUPABASE_URL"    | npx wrangler secret put SUPABASE_URL
printf '%s' "$SB_SECRET"       | npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
printf '%s' "$RC_AUTH"         | npx wrangler secret put RC_WEBHOOK_AUTH

echo "==> Registering Telegram webhook"
# message_reaction is NOT delivered unless explicitly requested.
curl -s "https://api.telegram.org/bot${TG_TOKEN}/setWebhook" \
  --data-urlencode "url=${WORKER_URL}/tg/${WEBHOOK_SECRET:0:16}" \
  --data-urlencode "secret_token=${WEBHOOK_SECRET}" \
  --data-urlencode 'allowed_updates=["message","callback_query","message_reaction","my_chat_member"]' \
  --data-urlencode "drop_pending_updates=true"
echo

echo "==> Webhook status"
curl -s "https://api.telegram.org/bot${TG_TOKEN}/getWebhookInfo"
echo
echo "Done. Worker: ${WORKER_URL}"
