#!/bin/bash

# ============================================================
# iLiNuX Marketplace — Telegram + Payments Setup
# ============================================================
#
# Run:
#
#   bash telegram-setup.sh
#
# Run this from your marketplace project folder.
#
# This script:
#
# 1. Checks Telegram bot
# 2. Checks Telegram chat
# 3. Links Supabase
# 4. Saves Telegram secrets
# 5. Saves Paystack secret
# 6. Creates notify-admin
# 7. Creates telegram-webhook
# 8. Creates paystack-init
# 9. Creates paystack-webhook
# 10. Deploys all functions
# 11. Connects Telegram webhook
#
# NEVER put the Telegram or Paystack secret in api.js.
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

ok(){
  echo -e "${GREEN}✓${RESET} $1"
}

warn(){
  echo -e "${YELLOW}!${RESET} $1"
}

fail(){
  echo -e "${RED}✗${RESET} $1"
  exit 1
}

echo ""
echo -e "${BOLD}iLiNuX Marketplace — Backend Setup${RESET}"
echo "================================================"
echo ""

# ============================================================
# CHECK PROJECT
# ============================================================

[ -d "supabase" ] || fail \
"Run this script from the project folder containing the supabase directory."

mkdir -p \
  supabase/functions/notify-admin \
  supabase/functions/telegram-webhook \
  supabase/functions/paystack-init \
  supabase/functions/paystack-webhook

ok "Supabase functions folders ready"

# ============================================================
# CHECK COMMANDS
# ============================================================

command -v curl >/dev/null 2>&1 ||
  fail "curl is required."

command -v openssl >/dev/null 2>&1 ||
  fail "openssl is required."

command -v npx >/dev/null 2>&1 ||
  fail "Node.js/npm is required."

# ============================================================
# TELEGRAM TOKEN
# ============================================================

echo ""
echo -e "${BOLD}Telegram Bot Token${RESET}"
echo "Get this from @BotFather."
echo ""

read -s -p "Bot token: " TG_TOKEN
echo ""

[ -n "$TG_TOKEN" ] ||
  fail "Telegram token cannot be empty."

echo ""
echo "Checking Telegram..."

ME_JSON=$(
  curl -fsS \
  "https://api.telegram.org/bot${TG_TOKEN}/getMe"
) || fail "Could not contact Telegram."

echo "$ME_JSON" |
  grep -q '"ok":true' ||
  fail "Telegram rejected the bot token."

BOTNAME=$(
  echo "$ME_JSON" |
  sed -n 's/.*"username":"\([^"]*\)".*/\1/p'
)

ok "Telegram bot verified: @${BOTNAME}"

# ============================================================
# TELEGRAM CHAT ID
# ============================================================

echo ""
echo -e "${BOLD}Telegram Admin Chat ID${RESET}"
echo ""
echo "Open Telegram and send a message to your bot."
echo ""
echo "Then use:"
echo ""
echo "https://api.telegram.org/bot<TOKEN>/getUpdates"
echo ""

read -p "Chat ID: " TG_CHAT

[ -n "$TG_CHAT" ] ||
  fail "Chat ID cannot be empty."

echo ""
echo "Testing Telegram chat..."

TEST_JSON=$(
  curl -fsS \
  "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\":\"${TG_CHAT}\",
    \"text\":\"✅ iLiNuX backend setup test — Telegram connection works.\"
  }"
) || fail "Telegram request failed."

echo "$TEST_JSON" |
  grep -q '"ok":true' ||
  fail "Telegram rejected the chat ID."

ok "Telegram chat verified"

# ============================================================
# SUPABASE PROJECT
# ============================================================

echo ""
echo -e "${BOLD}Supabase Project Ref${RESET}"
echo ""
echo "Example:"
echo "lkxeafrgachxnfwibxjy"
echo ""

read -p "Project ref: " PROJECT_REF

[ -n "$PROJECT_REF" ] ||
  fail "Supabase project ref cannot be empty."

echo ""
echo "Opening Supabase login..."

npx --yes supabase login

echo ""
echo "Linking Supabase project..."

npx --yes supabase link \
  --project-ref "$PROJECT_REF"

ok "Supabase project linked"

# ============================================================
# PAYSTACK SECRET
# ============================================================

echo ""
echo -e "${BOLD}Paystack Secret Key${RESET}"
echo ""
echo "Use your Paystack TEST secret while testing."
echo "Use your LIVE secret only after everything works."
echo ""

read -s -p "Paystack secret key: " PAYSTACK_SECRET
echo ""

[ -n "$PAYSTACK_SECRET" ] ||
  fail "Paystack secret key cannot be empty."

# ============================================================
# TELEGRAM WEBHOOK SECRET
# ============================================================

TG_SECRET=$(
  openssl rand -hex 32
)

# ============================================================
# SAVE SECRETS
# ============================================================

echo ""
echo "Saving backend secrets to Supabase..."

npx --yes supabase secrets set \
  TELEGRAM_BOT_TOKEN="$TG_TOKEN" \
  TELEGRAM_CHAT_ID="$TG_CHAT" \
  TELEGRAM_WEBHOOK_SECRET="$TG_SECRET" \
  PAYSTACK_SECRET_KEY="$PAYSTACK_SECRET"

ok "Backend secrets saved"

# ============================================================
# CREATE notify-admin
# ============================================================

cat > supabase/functions/notify-admin/index.ts <<'EOF'
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const TELEGRAM_TOKEN =
  Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";

const CHAT_ID =
  Deno.env.get("TELEGRAM_CHAT_ID") ?? "";

const TG_API =
  `https://api.telegram.org/bot${TELEGRAM_TOKEN}`;

function json(data: unknown,status=200){
  return new Response(
    JSON.stringify(data),
    {
      status,
      headers:{
        "content-type":"application/json"
      }
    }
  );
}

async function telegram(
  method:string,
  body:Record<string,unknown>
){

  const response =
    await fetch(
      `${TG_API}/${method}`,
      {
        method:"POST",
        headers:{
          "content-type":"application/json"
        },
        body:JSON.stringify(body)
      }
    );

  return await response.json();
}

Deno.serve(async req => {

  try{

    if(req.method !== "POST"){
      return json(
        {error:"Method not allowed"},
        405
      );
    }

    const body =
      await req.json();

    if(!body?.type || !body?.id){
      return json(
        {error:"Invalid notification"},
        400
      );
    }

    if(body.type === "seller"){

      const text =
`🟢 iLiNuX — NEW SELLER APPLICATION

🏪 Shop: ${body.name ?? "Unknown"}
📍 Location: ${body.location ?? "Unknown"}
📱 Payout: ${body.payout_net ?? ""} ${body.payout_phone ?? ""}

📦 Stock:
${body.stock_desc ?? "Not provided"}

Seller ID:
${body.id}`;

      const result =
        await telegram(
          "sendMessage",
          {
            chat_id:CHAT_ID,
            text,
            reply_markup:{
              inline_keyboard:[
                [
                  {
                    text:"✅ Approve",
                    callback_data:
                      `seller:approve:${body.id}`
                  },
                  {
                    text:"❌ Reject",
                    callback_data:
                      `seller:reject:${body.id}`
                  }
                ]
              ]
            }
          }
        );

      return json(result);
    }

    if(body.type === "listing"){

      const price =
        Number(body.price_pesewas || 0) / 100;

      const text =
`🟢 iLiNuX — NEW LISTING

📦 ${body.name ?? "Unknown"}
🔖 SKU: ${body.sku ?? ""}
💰 ₵${price.toFixed(2)}
🔒 Locked: ${body.locked ? "YES" : "NO"}
📄 Proof: ${body.proof ? "YES" : "NO"}
📱 IMEI: ${body.imei ?? "N/A"}

Listing ID:
${body.id}`;

      const result =
        await telegram(
          "sendMessage",
          {
            chat_id:CHAT_ID,
            text,
            reply_markup:{
              inline_keyboard:[
                [
                  {
                    text:"✅ Approve",
                    callback_data:
                      `listing:approve:${body.id}`
                  },
                  {
                    text:"❌ Reject",
                    callback_data:
                      `listing:reject:${body.id}`
                  }
                ]
              ]
            }
          }
        );

      return json(result);
    }

    return json(
      {error:"Unknown notification type"},
      400
    );

  }catch(error){

    console.error(error);

    return json(
      {
        error:
          error instanceof Error
            ? error.message
            : String(error)
      },
      500
    );

  }

});
EOF

ok "notify-admin created"

# ============================================================
# CREATE telegram-webhook
# ============================================================

cat > supabase/functions/telegram-webhook/index.ts <<'EOF'
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const TOKEN =
  Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";

const CHAT_ID =
  Deno.env.get("TELEGRAM_CHAT_ID") ?? "";

const WEBHOOK_SECRET =
  Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";

const SUPABASE_URL =
  Deno.env.get("SUPABASE_URL") ?? "";

const SECRET_KEYS =
  JSON.parse(
    Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"
  );

const SUPABASE_SECRET =
  SECRET_KEYS.default ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "";

const admin =
  createClient(
    SUPABASE_URL,
    SUPABASE_SECRET
  );

const API =
  `https://api.telegram.org/bot${TOKEN}`;

function json(data:unknown,status=200){
  return new Response(
    JSON.stringify(data),
    {
      status,
      headers:{
        "content-type":"application/json"
      }
    }
  );
}

async function tg(
  method:string,
  body:Record<string,unknown>
){

  const response =
    await fetch(
      `${API}/${method}`,
      {
        method:"POST",
        headers:{
          "content-type":"application/json"
        },
        body:JSON.stringify(body)
      }
    );

  return await response.json();
}

async function answerCallback(
  id:string,
  text:string
){

  await tg(
    "answerCallbackQuery",
    {
      callback_query_id:id,
      text,
      show_alert:false
    }
  );

}

Deno.serve(async req => {

  try{

    if(req.method !== "POST"){
      return json(
        {error:"Method not allowed"},
        405
      );
    }

    const secret =
      req.headers.get(
        "x-telegram-bot-api-secret-token"
      );

    if(
      !WEBHOOK_SECRET ||
      secret !== WEBHOOK_SECRET
    ){

      return json(
        {error:"Unauthorized"},
        401
      );

    }

    const update =
      await req.json();

    const callback =
      update?.callback_query;

    if(!callback){
      return json({ok:true});
    }

    const chatId =
      String(
        callback.message?.chat?.id ?? ""
      );

    if(
      chatId !== String(CHAT_ID)
    ){

      await answerCallback(
        callback.id,
        "Unauthorized admin chat."
      );

      return json({ok:true});
    }

    const data =
      String(
        callback.data ?? ""
      );

    const parts =
      data.split(":");

    if(parts.length !== 3){
      await answerCallback(
        callback.id,
        "Invalid action."
      );
      return json({ok:true});
    }

    const [type,action,id] =
      parts;

    let result;

    if(type === "seller"){

      if(action === "approve"){

        result =
          await admin
            .from("sellers")
            .update({
              status:"approved",
              reviewed_at:
                new Date().toISOString()
            })
            .eq("id",id)
            .eq("status","pending");

      }else if(action === "reject"){

        result =
          await admin
            .from("sellers")
            .update({
              status:"rejected",
              reject_reason:
                "Rejected from Telegram admin panel.",
              reviewed_at:
                new Date().toISOString()
            })
            .eq("id",id)
            .eq("status","pending");

      }

    }else if(type === "listing"){

      const {data:listing} =
        await admin
          .from("listings")
          .select(
            "id,is_locked,proof_url,imei,status"
          )
          .eq("id",id)
          .maybeSingle();

      if(!listing){
        await answerCallback(
          callback.id,
          "Listing not found."
        );
        return json({ok:true});
      }

      if(
        action === "approve" &&
        listing.is_locked &&
        (!listing.proof_url ||
         !listing.imei)
      ){

        await answerCallback(
          callback.id,
          "Locked listing is missing proof or IMEI."
        );

        return json({ok:true});
      }

      if(action === "approve"){

        result =
          await admin
            .from("listings")
            .update({
              status:"live",
              reviewed_at:
                new Date().toISOString()
            })
            .eq("id",id)
            .eq("status","pending");

      }else if(action === "reject"){

        result =
          await admin
            .from("listings")
            .update({
              status:"rejected",
              reject_reason:
                "Rejected from Telegram admin panel.",
              reviewed_at:
                new Date().toISOString()
            })
            .eq("id",id)
            .eq("status","pending");

      }

    }else{

      await answerCallback(
        callback.id,
        "Unknown action."
      );

      return json({ok:true});
    }

    if(result?.error){

      console.error(result.error);

      await answerCallback(
        callback.id,
        "Database update failed."
      );

      return json(
        {error:result.error.message},
        500
      );

    }

    await answerCallback(
      callback.id,
      action === "approve"
        ? "Approved ✅"
        : "Rejected ❌"
    );

    try{

      await tg(
        "editMessageReplyMarkup",
        {
          chat_id:CHAT_ID,
          message_id:
            callback.message.message_id,
          reply_markup:{
            inline_keyboard:[]
          }
        }
      );

    }catch(_){}

    return json({ok:true});

  }catch(error){

    console.error(error);

    return json(
      {
        error:
          error instanceof Error
            ? error.message
            : String(error)
      },
      500
    );

  }

});
EOF

ok "telegram-webhook created"

# ============================================================
# CREATE paystack-init
# ============================================================

cat > supabase/functions/paystack-init/index.ts <<'EOF'
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const PAYSTACK_SECRET =
  Deno.env.get("PAYSTACK_SECRET_KEY") ?? "";

const SUPABASE_URL =
  Deno.env.get("SUPABASE_URL") ?? "";

const SECRET_KEYS =
  JSON.parse(
    Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"
  );

const SUPABASE_SECRET =
  SECRET_KEYS.default ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "";

const admin =
  createClient(
    SUPABASE_URL,
    SUPABASE_SECRET
  );

function json(data:unknown,status=200){
  return new Response(
    JSON.stringify(data),
    {
      status,
      headers:{
        "content-type":"application/json"
      }
    }
  );
}

const providers = [
  "mtn",
  "atl",
  "vod"
];

Deno.serve(async req => {

  try{

    if(req.method !== "POST"){
      return json(
        {error:"Method not allowed"},
        405
      );
    }

    if(!PAYSTACK_SECRET){
      return json(
        {error:"PAYSTACK_SECRET_KEY is not configured"},
        500
      );
    }

    const auth =
      req.headers.get("authorization");

    if(!auth?.startsWith("Bearer ")){
      return json(
        {error:"Authentication required"},
        401
      );
    }

    const jwt =
      auth.replace(
        "Bearer ",
        ""
      );

    const {
      data:{user},
      error:userError
    } =
      await admin.auth.getUser(jwt);

    if(userError || !user){
      return json(
        {error:"Invalid authentication"},
        401
      );
    }

    const body =
      await req.json();

    const orderRef =
      String(body.order_ref || "")
        .trim();

    const phone =
      String(body.momo_phone || "")
        .replace(/\D/g,"");

    const provider =
      String(body.momo_network || "")
        .toLowerCase();

    if(!orderRef){
      return json(
        {error:"Order reference is required"},
        400
      );
    }

    if(phone.length < 9){
      return json(
        {error:"Invalid MoMo phone number"},
        400
      );
    }

    if(!providers.includes(provider)){
      return json(
        {error:"Invalid MoMo provider"},
        400
      );
    }

    const {data:order,error:orderError} =
      await admin
        .from("orders")
        .select(
          "id,ref,buyer_id,total_pesewas,status"
        )
        .eq("ref",orderRef)
        .maybeSingle();

    if(orderError){
      return json(
        {error:orderError.message},
        500
      );
    }

    if(!order){
      return json(
        {error:"Order not found"},
        404
      );
    }

    if(order.buyer_id !== user.id){
      return json(
        {error:"This order does not belong to you"},
        403
      );
    }

    if(order.status !== "awaiting_payment"){
      return json(
        {error:"This order is no longer awaiting payment"},
        409
      );
    }

    const payload = {

      email:
        user.email ||
        `buyer-${user.id}@ilinux.local`,

      amount:
        String(order.total_pesewas),

      currency:"GHS",

      reference:
        order.ref,

      metadata:{
        order_ref:order.ref,
        buyer_id:user.id
      },

      mobile_money:{
        phone,
        provider
      }

    };

    const response =
      await fetch(
        "https://api.paystack.co/charge",
        {
          method:"POST",
          headers:{
            "Authorization":
              `Bearer ${PAYSTACK_SECRET}`,
            "Content-Type":
              "application/json"
          },
          body:JSON.stringify(payload)
        }
      );

    const result =
      await response.json();

    if(
      !response.ok ||
      !result?.status
    ){

      return json(
        {
          error:
            result?.message ||
            "Paystack rejected the charge"
        },
        400
      );

    }

    return json({

      ok:true,

      reference:
        result.data?.reference ||
        order.ref,

      status:
        result.data?.status,

      display_text:
        result.data?.display_text ||
        "Approve the payment request on your phone."

    });

  }catch(error){

    console.error(error);

    return json(
      {
        error:
          error instanceof Error
            ? error.message
            : String(error)
      },
      500
    );

  }

});
EOF

ok "paystack-init created"

# ============================================================
# CREATE paystack-webhook
# ============================================================

cat > supabase/functions/paystack-webhook/index.ts <<'EOF'
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const PAYSTACK_SECRET =
  Deno.env.get("PAYSTACK_SECRET_KEY") ?? "";

const SUPABASE_URL =
  Deno.env.get("SUPABASE_URL") ?? "";

const SECRET_KEYS =
  JSON.parse(
    Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"
  );

const SUPABASE_SECRET =
  SECRET_KEYS.default ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "";

const admin =
  createClient(
    SUPABASE_URL,
    SUPABASE_SECRET
  );

function hex(buffer:ArrayBuffer){
  return Array
    .from(new Uint8Array(buffer))
    .map(b => b.toString(16).padStart(2,"0"))
    .join("");
}

async function hmacSha512(
  secret:string,
  text:string
){

  const key =
    await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(secret),
      {
        name:"HMAC",
        hash:"SHA-512"
      },
      false,
      ["sign"]
    );

  return hex(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(text)
    )
  );
}

function json(data:unknown,status=200){
  return new Response(
    JSON.stringify(data),
    {
      status,
      headers:{
        "content-type":"application/json"
      }
    }
  );
}

Deno.serve(async req => {

  try{

    if(req.method !== "POST"){
      return json(
        {error:"Method not allowed"},
        405
      );
    }

    const raw =
      await req.text();

    const signature =
      req.headers.get(
        "x-paystack-signature"
      ) || "";

    const expected =
      await hmacSha512(
        PAYSTACK_SECRET,
        raw
      );

    if(
      !signature ||
      signature.toLowerCase() !==
      expected.toLowerCase()
    ){

      return json(
        {error:"Invalid signature"},
        401
      );

    }

    const event =
      JSON.parse(raw);

    if(event.event !== "charge.success"){
      return json({ok:true});
    }

    const data =
      event.data || {};

    const reference =
      String(
        data.reference || ""
      );

    const amount =
      Number(data.amount || 0);

    if(!reference || !amount){
      return json({ok:true});
    }

    const orderRef =
      data.metadata?.order_ref ||
      reference;

    const {error} =
      await admin.rpc(
        "mark_order_paid",
        {
          p_order_ref:
            String(orderRef),

          p_paystack_ref:
            reference,

          p_amount_pesewas:
            Math.round(amount)
        }
      );

    if(error){

      console.error(error);

      return json(
        {
          error:error.message
        },
        500
      );

    }

    return json({
      ok:true
    });

  }catch(error){

    console.error(error);

    return json(
      {
        error:
          error instanceof Error
            ? error.message
            : String(error)
      },
      500
    );

  }

});
EOF

ok "paystack-webhook created"

# ============================================================
# DEPLOY
# ============================================================

echo ""
echo "Deploying Edge Functions..."
echo ""

npx --yes supabase functions deploy \
  notify-admin \
  --no-verify-jwt

npx --yes supabase functions deploy \
  telegram-webhook \
  --no-verify-jwt

npx --yes supabase functions deploy \
  paystack-init \
  --no-verify-jwt

npx --yes supabase functions deploy \
  paystack-webhook \
  --no-verify-jwt

ok "All Edge Functions deployed"

# ============================================================
# TELEGRAM WEBHOOK
# ============================================================

HOOK_URL=
"https://${PROJECT_REF}.supabase.co/functions/v1/telegram-webhook"

echo ""
echo "Connecting Telegram webhook..."

WEBHOOK_RESULT=$(
  curl -fsS \
  "https://api.telegram.org/bot${TG_TOKEN}/setWebhook" \
  -H "Content-Type: application/json" \
  -d "{
    \"url\":\"${HOOK_URL}\",
    \"secret_token\":\"${TG_SECRET}\",
    \"allowed_updates\":[\"callback_query\"]
  }"
) || fail "Could not set Telegram webhook."

echo "$WEBHOOK_RESULT" |
  grep -q '"ok":true' ||
  fail "Telegram webhook failed: $WEBHOOK_RESULT"

ok "Telegram webhook connected"

# ============================================================
# VERIFY TELEGRAM
# ============================================================

echo ""
echo "Checking Telegram webhook..."

WEBHOOK_INFO=$(
  curl -fsS \
  "https://api.telegram.org/bot${TG_TOKEN}/getWebhookInfo"
)

echo "$WEBHOOK_INFO"

# ============================================================
# FINAL MESSAGE
# ============================================================

curl -fsS \
  "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\":\"${TG_CHAT}\",
    \"text\":\"🚀 iLiNuX backend is LIVE.

Telegram:
✅ Seller alerts
✅ Listing alerts
✅ Approve / Reject buttons

Payments:
✅ Paystack Mobile Money backend
✅ Payment webhook
✅ Order verification
✅ Stock protection

Next step:
Set your Paystack webhook URL in the Paystack Dashboard.\"
  }" >/dev/null || true

echo ""
echo "================================================"
echo -e "${GREEN}${BOLD}iLiNuX BACKEND SETUP COMPLETE${RESET}"
echo "================================================"
echo ""
echo "Telegram webhook:"
echo "${HOOK_URL}"
echo ""
echo "Paystack webhook:"
echo "https://${PROJECT_REF}.supabase.co/functions/v1/paystack-webhook"
echo ""
echo -e "${YELLOW}IMPORTANT:${RESET}"
echo "Add the Paystack webhook URL above to your Paystack Dashboard."
echo ""
echo "Do NOT put your Paystack secret or Telegram token in api.js."
echo ""
echo -e "${GREEN}Done.${RESET}"
echo ""