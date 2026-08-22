// supabase/functions/telegram-webhook/index.ts
// Lets you approve or reject from the Telegram message itself.
// Deploy with --no-verify-jwt — Telegram sends its own secret header.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const TOKEN   = Deno.env.get('TELEGRAM_BOT_TOKEN')!;
const CHAT_ID = Deno.env.get('TELEGRAM_CHAT_ID')!;
const SECRET  = Deno.env.get('TELEGRAM_WEBHOOK_SECRET')!;

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const tg = (method: string, body: unknown) =>
  fetch(`https://api.telegram.org/bot${TOKEN}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

Deno.serve(async (req) => {
  // Without this check, anyone who finds the URL can approve sellers.
  if (req.headers.get('x-telegram-bot-api-secret-token') !== SECRET) {
    return new Response('no', { status: 401 });
  }

  const update = await req.json();
  const cb = update.callback_query;
  if (!cb) return new Response('ok');

  // Only your own chat may decide anything.
  if (String(cb.message?.chat?.id) !== String(CHAT_ID)) {
    await tg('answerCallbackQuery', { callback_query_id: cb.id, text: 'Not authorised.' });
    return new Response('ok');
  }

  const [action, id] = String(cb.data).split(':');
  let note = '';

  try {
    if (action === 'sok') {
      await admin.from('sellers').update({ status: 'approved', reviewed_at: new Date().toISOString() }).eq('id', id);
      note = '✅ Approved — they can list now';

    } else if (action === 'sno') {
      await admin.from('sellers').update({ status: 'rejected', reviewed_at: new Date().toISOString() }).eq('id', id);
      note = '❌ Rejected';

    } else if (action === 'lok') {
      // Check the locked-stock rule here too, so a fast tap on the phone
      // can't do what the dashboard would have stopped.
      const { data: l } = await admin.from('listings').select('*').eq('id', id).single();
      if (!l) {
        note = '⚠️ Listing not found';
      } else if (l.is_locked && (!l.proof_url || !l.imei)) {
        note = '🔒 Blocked — locked device with no proof or IMEI';
      } else {
        const { error } = await admin.from('listings')
          .update({ status: 'live', reviewed_at: new Date().toISOString() }).eq('id', id);
        note = error ? '⚠️ ' + error.message : '✅ Live on the site';
      }

    } else if (action === 'lno') {
      await admin.from('listings').update({ status: 'rejected', reviewed_at: new Date().toISOString() }).eq('id', id);
      note = '❌ Rejected';
    } else {
      note = 'Unknown action';
    }
  } catch (e) {
    note = '⚠️ ' + (e as Error).message;
  }

  await tg('answerCallbackQuery', { callback_query_id: cb.id, text: note });

  // Replace the buttons with the outcome so the message shows what you decided.
  await tg('editMessageText', {
    chat_id: cb.message.chat.id,
    message_id: cb.message.message_id,
    text: cb.message.text + '\n\n— ' + note,
    reply_markup: { inline_keyboard: [] },
  });

  return new Response('ok');
});
