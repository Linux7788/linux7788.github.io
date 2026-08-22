// ============================================================
// iLiNuX — Supabase API / Data Layer
// ============================================================
//
// Load BEFORE your main application script:
//
// <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
// <script src="api.js"></script>
//
// NEVER put:
// - Telegram bot tokens
// - Paystack secret keys
// - Supabase secret/service-role keys
// in this file.
//
// This browser file only uses the Supabase publishable key.
// ============================================================

const SUPABASE_URL =
  'https://lkxeafrgachxnfwibxjy.supabase.co';

const SUPABASE_PUBLISHABLE_KEY =
  'sb_publishable_NKXtOfJbiCdZDFcLfrCszA_laxmVDDv';

if(!window.supabase){
  throw new Error(
    'Supabase JS did not load. Check the CDN script before api.js.'
  );
}

const db = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY
);

// ============================================================
// CONFIG
// ============================================================

const COMMISSION = 0.15;

const MAX_PHOTO_BYTES =
  5 * 1024 * 1024;

const MAX_PHOTOS = 4;

const MAX_PROOF_BYTES =
  10 * 1024 * 1024;

// ============================================================
// MONEY
// ============================================================

const toPesewas = value => {

  const amount = Number(value);

  if(!Number.isFinite(amount) || amount < 0){
    throw new Error('Invalid Ghana cedi amount.');
  }

  return Math.round(amount * 100);
};

const toGHS = pesewas =>
  Number(pesewas || 0) / 100;

const fmt = pesewas =>
  '₵' +
  toGHS(pesewas).toLocaleString(
    'en-GH',
    {
      minimumFractionDigits:2,
      maximumFractionDigits:2
    }
  );

// ============================================================
// HELPERS
// ============================================================

function requireValue(value,message){

  if(
    value === undefined ||
    value === null ||
    String(value).trim() === ''
  ){
    throw new Error(message);
  }

  return value;
}

function cleanPhone(value){

  return String(value || '')
    .replace(/\D/g,'');
}

async function currentUser(){

  const {data,error} =
    await db.auth.getUser();

  if(error) throw error;

  return data?.user || null;
}

async function requireUser(){

  const user =
    await currentUser();

  if(!user){
    throw new Error('Please sign in first.');
  }

  return user;
}

// ============================================================
// AUTH
// ============================================================

const Auth = {

  async signUp(
    email,
    password,
    fullName,
    phone
  ){

    requireValue(email,'Email is required.');
    requireValue(password,'Password is required.');
    requireValue(fullName,'Full name is required.');

    if(String(password).length < 6){
      throw new Error(
        'Password must contain at least 6 characters.'
      );
    }

    const {data,error} =
      await db.auth.signUp({

        email:String(email).trim(),

        password,

        options:{
          data:{
            full_name:String(fullName).trim(),
            phone:String(phone || '').trim()
          }
        }

      });

    if(error) throw error;

    return data.user;
  },

  async signIn(email,password){

    requireValue(email,'Email is required.');
    requireValue(password,'Password is required.');

    const {data,error} =
      await db.auth.signInWithPassword({

        email:String(email).trim(),

        password

      });

    if(error) throw error;

    return data.user;
  },

  async signOut(){

    const {error} =
      await db.auth.signOut();

    if(error) throw error;
  },

  // Supabase fires PASSWORD_RECOVERY once it consumes a reset link
  onRecovery(callback){
    db.auth.onAuthStateChange((event) => {
      if(event === 'PASSWORD_RECOVERY') callback();
    });
  },

  async requestPasswordReset(email){

    requireValue(
      email,
      'Email is required.'
    );

    const {error} =
      await db.auth.resetPasswordForEmail(
        String(email).trim(),
        {
          redirectTo:
            window.location.origin +
            window.location.pathname
        }
      );

    if(error) throw error;
  },

  async setNewPassword(newPassword){

    if(!newPassword || newPassword.length < 8){
      throw new Error(
        'Password must be at least 8 characters.'
      );
    }

    const {error} =
      await db.auth.updateUser({
        password:newPassword
      });

    if(error) throw error;
  },

  async resendConfirmation(email){

    requireValue(
      email,
      'Email is required.'
    );

    const {error} =
      await db.auth.resend({
        type:'signup',
        email:String(email).trim()
      });

    if(error) throw error;
  },

  async me(){

    const user =
      await currentUser();

    if(!user) return null;

    const {data:profile,error} =
      await db
        .from('profiles')
        .select('*')
        .eq('id',user.id)
        .maybeSingle();

    if(error) throw error;

    return {
      ...user,
      profile:profile || null
    };
  },

  onChange(callback){

    return db.auth.onAuthStateChange(
      (_event,session) =>
        callback(session?.user || null)
    );
  }

};

// ============================================================
// LISTINGS
// ============================================================

const Listings = {

  async browse({
    q='',
    brand='',
    category='',
    grade=''
  } = {}){

    let query =
      db
        .from('listings')
        .select(`
          *,
          sellers(
            shop_name,
            status
          )
        `)
        .eq('status','live')
        .gt('stock',0)
        .order('created_at',{
          ascending:false
        });

    if(brand)
      query = query.eq('brand',brand);

    if(category)
      query = query.eq('category',category);

    if(grade)
      query = query.eq('grade',grade);

    const term =
      String(q || '').trim();

    if(term){

      const safe =
        term
          .replace(/\\/g,'\\\\')
          .replace(/%/g,'\\%')
          .replace(/_/g,'\\_')
          .replace(/,/g,'\\,');

      query =
        query.or(
          `name.ilike.%${safe}%,sku.ilike.%${safe}%`
        );

    }

    const {data,error} =
      await query;

    if(error) throw error;

    return data || [];
  },

  async create(fields={}){

    const sellerId =
      await Sellers.myId();

    if(!sellerId){

      throw new Error(
        'You are not an approved seller.'
      );

    }

    requireValue(
      fields.sku,
      'SKU is required.'
    );

    requireValue(
      fields.name,
      'Part name is required.'
    );

    requireValue(
      fields.brand,
      'Brand is required.'
    );

    requireValue(
      fields.category,
      'Category is required.'
    );

    const price =
      toPesewas(fields.priceGHS);

    if(price <= 0){
      throw new Error(
        'Price must be greater than zero.'
      );
    }

    const stock =
      Number.parseInt(
        fields.stock,
        10
      );

    if(!Number.isInteger(stock) || stock < 1){
      throw new Error(
        'Stock must be at least 1.'
      );
    }

    const locked =
      Boolean(fields.is_locked);

    let imei = null;

    if(locked){

      imei =
        String(fields.imei || '')
          .replace(/\D/g,'');

      if(imei.length !== 15){
        throw new Error(
          'Locked stock requires a valid 15-digit IMEI.'
        );
      }

      if(!fields.proof_url){
        throw new Error(
          'Locked stock requires ownership proof.'
        );
      }

    }

    const photos =
      Array.isArray(fields.photos)
        ? fields.photos.slice(0,MAX_PHOTOS)
        : [];

    const {data,error} =
      await db
        .from('listings')
        .insert({

          seller_id:sellerId,

          sku:String(fields.sku).trim(),

          name:String(fields.name).trim(),

          brand:String(fields.brand).trim(),

          category:String(fields.category).trim(),

          grade:
            fields.grade === 'B'
              ? 'B'
              : 'A',

          price_pesewas:price,

          stock,

          is_locked:locked,

          proof_url:
            fields.proof_url || null,

          imei,

          photos

        })
        .select()
        .single();

    if(error) throw error;

    await Notify.adminNewListing(data);

    return data;
  },

  async mine(){

    const sellerId =
      await Sellers.myId();

    if(!sellerId) return [];

    const {data,error} =
      await db
        .from('listings')
        .select('*')
        .eq('seller_id',sellerId)
        .order('created_at',{
          ascending:false
        });

    if(error) throw error;

    return data || [];
  },

  async uploadPhotos(files){

    const user =
      await requireUser();

    const picked =
      Array.from(files || [])
        .slice(0,MAX_PHOTOS);

    const urls = [];

    for(const file of picked){

      if(file.size > MAX_PHOTO_BYTES){

        throw new Error(
          `${file.name} is larger than 5MB.`
        );

      }

      if(!file.type.startsWith('image/')){

        throw new Error(
          `${file.name} is not an image.`
        );

      }

      const ext =
        (file.name.split('.').pop() || 'jpg')
          .toLowerCase()
          .replace(/[^a-z0-9]/g,'');

      const unique =
        typeof crypto.randomUUID === 'function'
          ? crypto.randomUUID()
          : Math.random()
              .toString(36)
              .slice(2);

      const path =
        `${user.id}/${Date.now()}-${unique}.${ext || 'jpg'}`;

      const {error} =
        await db
          .storage
          .from('photos')
          .upload(
            path,
            file,
            {
              contentType:file.type,
              upsert:false
            }
          );

      if(error) throw error;

      const {data} =
        db
          .storage
          .from('photos')
          .getPublicUrl(path);

      urls.push(data.publicUrl);
    }

    return urls;
  },

  async uploadProof(file){

    const user =
      await requireUser();

    if(!file){
      throw new Error(
        'Ownership proof is required.'
      );
    }

    const allowed = [
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/webp'
    ];

    if(!allowed.includes(file.type)){

      throw new Error(
        'Proof must be PDF, JPG, PNG or WEBP.'
      );

    }

    if(file.size > MAX_PROOF_BYTES){

      throw new Error(
        'Ownership proof must be 10MB or smaller.'
      );

    }

    const safeName =
      file.name.replace(
        /[^a-zA-Z0-9._-]/g,
        '_'
      );

    const unique =
      typeof crypto.randomUUID === 'function'
        ? crypto.randomUUID()
        : Math.random()
            .toString(36)
            .slice(2);

    const path =
      `${user.id}/${Date.now()}-${unique}-${safeName}`;

    const {error} =
      await db
        .storage
        .from('proofs')
        .upload(
          path,
          file,
          {
            contentType:file.type,
            upsert:false
          }
        );

    if(error) throw error;

    return path;
  }

};

// ============================================================
// SELLERS
// ============================================================

const Sellers = {

  async apply({
    shopName,
    payoutPhone,
    payoutNet,
    location,
    stockDesc,
    ghanaCard
  } = {}){

    const user =
      await requireUser();

    requireValue(
      shopName,
      'Shop name is required.'
    );

    requireValue(
      payoutPhone,
      'MoMo payout number is required.'
    );

    requireValue(
      location,
      'Trading location is required.'
    );

    requireValue(
      stockDesc,
      'Stock description is required.'
    );

    requireValue(
      ghanaCard,
      'Ghana Card number is required.'
    );

    const phone =
      cleanPhone(payoutPhone);

    if(phone.length < 9){
      throw new Error(
        'Enter a valid MoMo number.'
      );
    }

    const networks = [
      'MTN',
      'ATMoney',
      'Telecel'
    ];

    if(!networks.includes(payoutNet)){
      throw new Error(
        'Invalid mobile money network.'
      );
    }

    const existing =
      await this.mine();

    if(existing){

      throw new Error(
        `You already have a seller application (${existing.status}).`
      );

    }

    const {data,error} =
      await db
        .from('sellers')
        .insert({

          user_id:user.id,

          shop_name:
            String(shopName).trim(),

          payout_phone:phone,

          payout_net:payoutNet,

          location:
            String(location).trim(),

          stock_desc:
            String(stockDesc).trim(),

          ghana_card:
            String(ghanaCard).trim()

        })
        .select()
        .single();

    if(error) throw error;

    await Notify.adminNewSeller(data);

    return data;
  },

  async mine(){

    const user =
      await currentUser();

    if(!user) return null;

    const {data,error} =
      await db
        .from('sellers')
        .select('*')
        .eq('user_id',user.id)
        .maybeSingle();

    if(error) throw error;

    return data || null;
  },

  async myId(){

    const seller =
      await this.mine();

    return seller?.status === 'approved'
      ? seller.id
      : null;
  }

};

// ============================================================
// ORDERS
// ============================================================
//
// IMPORTANT:
// The browser no longer calculates the authoritative order
// price. The database create_order() function reads prices and
// stock directly from listings.
//
// ============================================================

const Orders = {

  async create({
    items,
    buyerName,
    buyerPhone,
    deliveryArea,
    momoNetwork
  } = {}){

    const user =
      await requireUser();

    if(!Array.isArray(items) || !items.length){

      throw new Error(
        'Your cart is empty.'
      );

    }

    requireValue(
      buyerName,
      'Delivery name is required.'
    );

    requireValue(
      buyerPhone,
      'MoMo number is required.'
    );

    requireValue(
      deliveryArea,
      'Delivery area is required.'
    );

    const phone =
      cleanPhone(buyerPhone);

    if(phone.length < 9){
      throw new Error(
        'Enter a valid MoMo number.'
      );
    }

    const networks = [
      'MTN',
      'ATMoney',
      'Telecel'
    ];

    if(!networks.includes(momoNetwork)){
      throw new Error(
        'Invalid mobile money network.'
      );
    }

    const cleanItems =
      items.map(item => {

        const qty =
          Number.parseInt(
            item.qty,
            10
          );

        if(!item.id){
          throw new Error(
            'Invalid cart item.'
          );
        }

        if(!Number.isInteger(qty) || qty < 1){
          throw new Error(
            'Invalid item quantity.'
          );
        }

        return {
          id:item.id,
          qty
        };

      });

    const {data,error} =
      await db.rpc(
        'create_order',
        {
          p_items:cleanItems,
          p_buyer_name:
            String(buyerName).trim(),
          p_buyer_phone:phone,
          p_delivery_area:
            String(deliveryArea).trim(),
          p_momo_network:momoNetwork
        }
      );

    if(error) throw error;

    if(!data){
      throw new Error(
        'Order creation failed.'
      );
    }

    return data;
  },

  async mine(){

    const user =
      await requireUser();

    const {data,error} =
      await db
        .from('orders')
        .select(`
          *,
          order_items(*)
        `)
        .eq('buyer_id',user.id)
        .order('created_at',{
          ascending:false
        });

    if(error) throw error;

    return data || [];
  },

  async confirmDelivery(ref){

    requireValue(
      ref,
      'Order reference is required.'
    );

    const {error} =
      await db.rpc(
        'confirm_delivery',
        {
          order_ref:
            String(ref).trim()
        }
      );

    if(error) throw error;
  }

};

// ============================================================
// PAYMENTS
// ============================================================

const Payments = {

  async start({
    orderRef,
    phone,
    network
  }){

    requireValue(
      orderRef,
      'Order reference is required.'
    );

    requireValue(
      phone,
      'MoMo number is required.'
    );

    const provider = {

      MTN:'mtn',

      ATMoney:'atl',

      Telecel:'vod'

    }[network];

    if(!provider){

      throw new Error(
        'Unsupported MoMo network.'
      );

    }

    const {data,error} =
      await db.functions.invoke(
        'paystack-init',
        {
          body:{
            order_ref:String(orderRef),
            momo_phone:cleanPhone(phone),
            momo_network:provider
          }
        }
      );

    if(error){

      throw new Error(
        error.message ||
        'Could not start payment.'
      );

    }

    if(data?.error){

      throw new Error(
        data.error
      );

    }

    return data;
  }

};

// ============================================================
// ADMIN
// ============================================================

const Admin = {

  async pendingSellers(){

    const {data,error} =
      await db
        .from('sellers')
        .select('*')
        .eq('status','pending')
        .order('created_at',{
          ascending:true
        });

    if(error) throw error;

    return data || [];
  },

  async pendingListings(){

    const {data,error} =
      await db
        .from('listings')
        .select(`
          *,
          sellers(shop_name)
        `)
        .eq('status','pending')
        .order('created_at',{
          ascending:true
        });

    if(error) throw error;

    return data || [];
  },

  async decideSeller(
    id,
    approve,
    reason=null
  ){

    const user =
      await requireUser();

    if(!id){
      throw new Error(
        'Seller id is required.'
      );
    }

    const {error} =
      await db
        .from('sellers')
        .update({

          status:
            approve
              ? 'approved'
              : 'rejected',

          reviewed_by:user.id,

          reviewed_at:
            new Date().toISOString(),

          reject_reason:
            approve
              ? null
              : (
                  reason ||
                  'Application not approved.'
                )

        })
        .eq('id',id)
        .eq('status','pending');

    if(error) throw error;
  },

  async decideListing(
    id,
    approve,
    reason=null
  ){

    const user =
      await requireUser();

    if(!id){
      throw new Error(
        'Listing id is required.'
      );
    }

    const {error} =
      await db
        .from('listings')
        .update({

          status:
            approve
              ? 'live'
              : 'rejected',

          reviewed_by:user.id,

          reviewed_at:
            new Date().toISOString(),

          reject_reason:
            approve
              ? null
              : (
                  reason ||
                  'Listing rejected.'
                )

        })
        .eq('id',id)
        .eq('status','pending');

    if(error){

      const message =
        String(error.message || '');

      if(
        message.includes(
          'locked_needs_proof'
        )
      ){

        throw new Error(
          'Locked listing requires ownership proof and IMEI.'
        );

      }

      throw error;
    }
  },

  async payoutsDue(){

    const {data,error} =
      await db
        .from('orders')
        .select(`
          *,
          order_items(
            *,
            sellers(
              shop_name,
              payout_phone,
              payout_net
            )
          )
        `)
        .eq('status','delivered')
        .eq('payout_done',false)
        .order('confirmed_at',{
          ascending:true
        });

    if(error) throw error;

    return data || [];
  },

  async markPaidOut(orderId){

    if(!orderId){
      throw new Error(
        'Order id is required.'
      );
    }

    const {error} =
      await db
        .from('orders')
        .update({
          payout_done:true
        })
        .eq('id',orderId)
        .eq('status','delivered')
        .eq('payout_done',false);

    if(error) throw error;
  },

  async proofUrl(path){

    if(!path) return null;

    const {data,error} =
      await db
        .storage
        .from('proofs')
        .createSignedUrl(
          path,
          300
        );

    if(error) throw error;

    return data?.signedUrl || null;
  }

};

// ============================================================
// TELEGRAM NOTIFICATIONS
// ============================================================

const Notify = {

  async adminNewSeller(seller){

    try{

      await db.functions.invoke(
        'notify-admin',
        {
          body:{
            type:'seller',
            id:seller.id,
            name:seller.shop_name,
            location:seller.location,
            payout_net:seller.payout_net,
            payout_phone:seller.payout_phone,
            stock_desc:seller.stock_desc
          }
        }
      );

    }catch(error){

      console.warn(
        'Telegram seller notification failed:',
        error
      );

    }

  },

  async adminNewListing(listing){

    try{

      await db.functions.invoke(
        'notify-admin',
        {
          body:{
            type:'listing',
            id:listing.id,
            name:listing.name,
            sku:listing.sku,
            price_pesewas:
              listing.price_pesewas,
            locked:
              listing.is_locked,
            proof:
              Boolean(listing.proof_url),
            imei:
              listing.imei
          }
        }
      );

    }catch(error){

      console.warn(
        'Telegram listing notification failed:',
        error
      );

    }

  }

};

// ============================================================
// GLOBAL EXPORT
// ============================================================

window.iLiNuX = {

  db,

  Auth,

  Listings,

  Sellers,

  Orders,

  Payments,

  Admin,

  Notify,

  fmt,

  toPesewas,

  toGHS,

  COMMISSION

};