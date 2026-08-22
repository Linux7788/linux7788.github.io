// supabase/functions/notify-admin/index.ts
// Pings your Telegram when something needs a decision — with the
// decision buttons attached, so you never open the dashboard for a routine yes.

const TOKEN   = Deno.env.get('TELEGRAM_BOT_TOKEN')!;
const CHAT_ID = Deno.env.get('TELEGRAM_CHAT_ID')!;
const SITE = 'https://linux7788.github.io/index.html';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    const b = await req.json();
    let text = '', keyboard: unknown[][] = [];

    if (b.type === 'seller') {
      text =
        `🧾 <b>New seller application</b>\n\n` +
        `<b>${b.name}</b>\n` +
        `📍 ${b.location}\n` +
        `📞 ${b.payout_net ?? ''} ${b.payout_phone ?? ''}\n\n` +
        `<i>${b.stock_desc ?? ''}</i>`;
      keyboard = [[
        { text: '✅ Approve', callback_data: `sok:${b.id}` },
        { text: '❌ Reject',  callback_data: `sno:${b.id}` },
      ]];

    } else if (b.type === 'listing') {
      const locked = b.locked
        ? (b.proof && b.imei
            ? `\n🔒 Locked device — IMEI <code>${b.imei}</code>, proof uploaded`
            : `\n🔒 <b>Locked device with NO proof or IMEI</b> — approving will be blocked`)
        : '';
      text =
        `📦 <b>Listing awaiting approval</b>\n\n` +
        `<b>${b.name}</b>\n` +
        `<code>${b.sku}</code>  ·  ₵${((b.price_pesewas ?? 0) / 100).toFixed(2)}\n` +
        `Seller: ${b.seller ?? '—'}` + locked;
      keyboard = [[
        { text: '✅ Approve', callback_data: `lok:${b.id}` },
        { text: '❌ Reject',  callback_data: `lno:${b.id}` },
      ]];
      // Proof has to be viewed in the dashboard — signed links expire,
      // and putting one in a chat message leaks it to anyone with the chat.
      if (b.locked) keyboard.push([{ text: '🔍 Open dashboard to see proof', url: SITE }]);

    } else {
      return new Response(JSON.stringify({ error: 'Unknown type' }), { status: 400, headers: cors });
    }

    await fetch(`https://api.telegram.org/bot${TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: CHAT_ID, text, parse_mode: 'HTML',
        reply_markup: { inline_keyboard: keyboard },
      }),
    });

    return new Response(JSON.stringify({ sent: true }), {
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 400, headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});
