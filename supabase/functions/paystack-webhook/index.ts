// supabase/functions/paystack-webhook/index.ts
// Paystack tells us here whether the money actually arrived.
// Deploy with --no-verify-jwt: Paystack sends a signature, not a Supabase token.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const PAYSTACK_SECRET = Deno.env.get('PAYSTACK_SECRET_KEY')!;
const TELEGRAM_TOKEN  = Deno.env.get('TELEGRAM_BOT_TOKEN')!;
const TELEGRAM_CHAT   = Deno.env.get('TELEGRAM_CHAT_ID')!;

// service role: the webhook is not a logged-in user, so it bypasses RLS.
// This key must only ever live in edge function secrets.
const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// Paystack signs the raw body with HMAC SHA-512 using your secret key.
// An unverified webhook means anyone can POST "payment succeeded" to your site.
async function verify(raw: string, signature: string | null): Promise<boolean> {
  if (!signature) return false;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(PAYSTACK_SECRET),
    { name: 'HMAC', hash: 'SHA-512' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(raw));
  const hex = [...new Uint8Array(mac)].map(b => b.toString(16).padStart(2, '0')).join('');
  // constant-time compare
  if (hex.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < hex.length; i++) diff |= hex.charCodeAt(i) ^ signature.charCodeAt(i);
  return diff === 0;
}

async function tell(text: string) {
  try {
    await fetch(`https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: TELEGRAM_CHAT, text, parse_mode: 'HTML' }),
    });
  } catch (_) { /* an alert failing must never fail the payment */ }
}

const cedis = (p: number) => '₵' + (p / 100).toLocaleString('en-GH', { minimumFractionDigits: 2 });

Deno.serve(async (req) => {
  const raw = await req.text();

  if (!await verify(raw, req.headers.get('x-paystack-signature'))) {
    return new Response('Invalid signature', { status: 401 });
  }

  const event = JSON.parse(raw);
  const ref = event?.data?.reference;
  if (!ref) return new Response('ok');   // always 200 or Paystack keeps retrying

  if (event.event === 'charge.success') {
    const { data: order } = await admin
      .from('orders').select('*').eq('ref', ref).single();

    if (!order) return new Response('ok');
    if (order.status !== 'awaiting_payment') return new Response('ok'); // already handled

    // Paystack sends amounts in pesewas. If it does not match, do not mark it paid.
    if (event.data.amount !== order.total_pesewas) {
      await tell(`⚠️ <b>Amount mismatch</b> on ${ref}\nExpected ${cedis(order.total_pesewas)}, got ${cedis(event.data.amount)}. Not marked paid.`);
      return new Response('ok');
    }

    await admin.from('orders').update({
      status: 'held',
      paid_at: new Date().toISOString(),
      paystack_ref: event.data.reference,
    }).eq('id', order.id);

    // decrement stock on the parts that were bought
    const { data: items } = await admin
      .from('order_items').select('listing_id, qty').eq('order_id', order.id);
    for (const it of items ?? []) {
      if (it.listing_id) {
        await admin.rpc('decrement_stock', { p_listing: it.listing_id, p_qty: it.qty });
      }
    }

    await tell(
      `💰 <b>Payment received</b>\n` +
      `${ref} — ${cedis(order.total_pesewas)}\n` +
      `${order.buyer_name}, ${order.delivery_area}\n` +
      `📞 ${order.buyer_phone}\n\n` +
      `Held. Ship the parts; funds release when the buyer confirms.`,
    );
  }

  if (event.event === 'charge.failed') {
    await tell(`❌ Payment failed on ${ref}. Buyer may retry.`);
  }

  return new Response('ok');
});
