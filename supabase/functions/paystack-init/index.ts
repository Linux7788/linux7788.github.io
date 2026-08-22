// supabase/functions/paystack-init/index.ts
// Starts a mobile money charge. The amount is read from the database,
// never from the browser — otherwise anyone can pay ₵1 for a ₵1,400 screen.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const PAYSTACK_SECRET = Deno.env.get('PAYSTACK_SECRET_KEY')!;

// Paystack provider codes for Ghana. Telecel still uses Vodafone's old code.
const PROVIDER: Record<string, string> = {
  MTN: 'mtn',
  Telecel: 'vod',
  AT: 'atl',
};

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    const { order_ref, momo_phone, momo_network } = await req.json();

    if (!PROVIDER[momo_network]) {
      throw new Error('Choose MTN, Telecel or AT.');
    }

    // act as the signed-in user so RLS still applies to the read
    const supa = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } },
    );

    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error('Sign in to pay.');

    const { data: order, error } = await supa
      .from('orders').select('*').eq('ref', order_ref).single();
    if (error || !order) throw new Error('Order not found.');
    if (order.buyer_id !== user.id) throw new Error('Not your order.');
    if (order.status !== 'awaiting_payment') throw new Error('This order is already paid.');

    // amount comes from the order row, in pesewas, exactly as Paystack expects
    const res = await fetch('https://api.paystack.co/charge', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${PAYSTACK_SECRET}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email: user.email,
        amount: order.total_pesewas,
        currency: 'GHS',
        reference: order.ref,
        mobile_money: { phone: momo_phone, provider: PROVIDER[momo_network] },
        metadata: { order_id: order.id, buyer_phone: order.buyer_phone },
      }),
    });

    const body = await res.json();
    if (!body.status) throw new Error(body.message ?? 'Paystack refused the charge.');

    // 'pay_offline' means: the customer now approves the prompt on their handset.
    // The real confirmation arrives at the webhook, not here.
    return new Response(JSON.stringify({
      status: body.data.status,
      display_text: body.data.display_text ??
        'Approve the prompt on your phone to complete payment.',
      reference: body.data.reference,
    }), { headers: { ...cors, 'Content-Type': 'application/json' } });

  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 400,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});
