# iLinux — Paystack + Telegram setup

## 1. Telegram bot

1. Message **@BotFather** on Telegram → `/newbot` → pick a name → it gives you a token.
2. Send your new bot any message.
3. Open `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates` in a browser and copy the `chat.id` number.

## 2. Paystack

1. Sign up at paystack.com, choose Ghana, submit your business documents. **Mobile money will not work in live mode until they approve you** — that usually takes a few days, so start it now.
2. Dashboard → Settings → API Keys & Webhooks.
3. Copy your **secret key** (`sk_test_...` for now).
4. Set the webhook URL to:
   `https://YOUR-PROJECT.supabase.co/functions/v1/paystack-webhook`

## 3. Store the secrets

These never go in your GitHub repo. GitHub Pages serves every file publicly — a leaked secret key lets a stranger move your money.

```bash
npx supabase login
npx supabase link --project-ref YOUR-PROJECT-REF

npx supabase secrets set PAYSTACK_SECRET_KEY=sk_test_xxxxx
npx supabase secrets set TELEGRAM_BOT_TOKEN=1234567:AAxxxxx
npx supabase secrets set TELEGRAM_CHAT_ID=987654321
```

## 4. Deploy

Put the four folders under `supabase/functions/`, then:

```bash
npx supabase functions deploy paystack-init
npx supabase functions deploy notify-admin
npx supabase functions deploy paystack-webhook  --no-verify-jwt
npx supabase functions deploy telegram-webhook  --no-verify-jwt
```

The `--no-verify-jwt` matters on those two. Paystack and Telegram send their own
signature headers, not a Supabase login token, so JWT checking would reject every
real callback.

## 5. Point Telegram at your bot

Pick any long random string as a webhook secret, save it, then tell Telegram where to send taps:

```bash
npx supabase secrets set TELEGRAM_WEBHOOK_SECRET=some-long-random-string

curl "https://api.telegram.org/bot<YOUR_TOKEN>/setWebhook" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://YOUR-PROJECT.supabase.co/functions/v1/telegram-webhook",
    "secret_token": "some-long-random-string",
    "allowed_updates": ["callback_query"]
  }'
```

Now seller applications and new listings arrive in Telegram with Approve and
Reject buttons. Tapping one updates the database and edits the message to show
what you decided. Two guards are built in: only your own chat ID can decide
anything, and approving a locked-device listing with no proof or IMEI is refused
even from Telegram.

## 6. Calling it from the site

```js
const { data, error } = await db.functions.invoke('paystack-init', {
  body: { order_ref: order.ref, momo_phone: '024xxxxxxx', momo_network: 'MTN' }
});
// show data.display_text — "approve the prompt on your phone"
// then poll the order row, or subscribe to it:

db.channel('order-' + order.ref)
  .on('postgres_changes',
      { event:'UPDATE', schema:'public', table:'orders', filter:'ref=eq.' + order.ref },
      p => { if (p.new.status === 'held') showPaidScreen(); })
  .subscribe();
```

## Testing

Paystack test mode has MoMo test numbers in their docs. For the webhook, use their dashboard's "Send test webhook" — do not trust a payment that only succeeded in the browser.

## Two things to watch

**Amounts are in pesewas everywhere.** ₵420.00 is `42000`. The webhook refuses to mark an order paid if Paystack's amount does not match the order row, which is what stops someone editing the price in their browser.

**Paystack's fee comes off before you see the money.** Roughly 1.95% on MoMo in Ghana. If you charge 15% commission and pay the seller 85%, that fee comes out of *your* 15%, not theirs — worth checking against your margin once real orders start.
