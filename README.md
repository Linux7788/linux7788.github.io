# iLinux Marketplace — current as of 21 August 2026

**This folder matches what is live right now.** Replace your old Desktop
folder with this one.

## Read this before you ever run `git push`

Your old folder was pushed once and it wiped the live site. If you push
from a folder that is behind, it happens again.

Safest habit — never push from a stale folder:

```bash
cd ~/Desktop/ilinux
git pull            # get what's live FIRST
# ...then make changes, then push
```

If you are unsure, upload files through github.com instead. It cannot
overwrite history the way a force push can.

## What is live

| Thing | Where |
|---|---|
| Landing page | linux7788.github.io (has a Parts Marketplace nav link) |
| Marketplace | linux7788.github.io/market.html |
| Database | Supabase project `lkxeafrgachxnfwibxjy` |
| Telegram bot | approve / reject buttons working |
| Paystack | live mode, webhook set |

## Files here

| File | What it is |
|---|---|
| `market.html` | The marketplace. Goes in your repo root. |
| `api.js` | Talks to the database. Already has your URL and key. Repo root. |
| `schema.sql` | Full database schema, including product photos. Already applied. |
| `supabase/functions/` | The four edge functions. Already deployed. Stays on your Mac. |
| `telegram-setup.sh` | Only needed if you rebuild from scratch. |
| `REFERENCE.md` | Manual commands, if you ever want to do it by hand. |

Only `market.html` and `api.js` belong in the GitHub repo. Nothing else.

## The one thing still outstanding

Your Paystack account is **live**. If the secret key stored in Supabase is
a test key, real payments will fail at the webhook.

Check: Paystack → Settings → API Keys & Webhooks → click the eye on Live
Secret Key. If it does not match what you gave the setup script:

```bash
npx supabase secrets set PAYSTACK_SECRET_KEY=sk_live_your_key_here
```

## First real test

1. Sign in on market.html
2. My Shop → list one part you actually have, with photos
3. Approve it from Telegram
4. Buy it yourself for a small amount
5. Confirm delivery, check the payout shows in Admin → Payouts due

Do this with a cheap item before a customer's large order is the first
live transaction.

## Things worth revisiting

- **15% commission.** On a GHS 420 screen that is GHS 63. Watch whether
  sellers accept it or drift back to WhatsApp. Change it in one line at
  the top of `api.js`.
- **Old files in the repo** — `admin.html`, `auth.html`, `dashboard.html`,
  `marketplace.html`, `sell.html`, `supabase-config.js`, `script.js`,
  `.DS_Store`. These belong to the earlier version and point at tables
  that no longer exist. Deleting them is safe but is your call.
- **`notify-admin` is callable without a login.** Someone who finds the
  URL could send you fake alerts. Annoying, not dangerous — the Approve
  buttons still check the database. Worth tightening later.
- **`verify-payment`** is an old function still deployed. Unused.
- **Payout number.** Your seller record uses 024 714 1413. If your MoMo
  payout number differs, change it in the `sellers` table — that is where
  your money lands.
