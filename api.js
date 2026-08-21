// ============================================================
// iLinux — Supabase data layer
// Replaces the in-memory state in the prototype.
// Load in your page BEFORE your app script:
//   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
//   <script src="api.js"></script>
// ============================================================

const SUPABASE_URL  = 'https://lkxeafrgachxnfwibxjy.supabase.co';
const SUPABASE_ANON = 'sb_publishable_NKXtOfJbiCdZDFcLfrCszA_laxmVDDv';  // safe to publish — RLS is what protects the data

const db = supabase.createClient(SUPABASE_URL, SUPABASE_ANON);

// money is stored as whole pesewas so nothing rounds badly
const toPesewas = ghs => Math.round(ghs * 100);
const toGHS     = p   => (p / 100);
const fmt       = p   => '₵' + toGHS(p).toLocaleString('en-GH', {minimumFractionDigits:2});

const COMMISSION = 0.15;   // change in one place

// ---------------- auth ----------------
const Auth = {
  async signUp(email, password, fullName, phone){
    const {data, error} = await db.auth.signUp({
      email, password, options:{data:{full_name:fullName, phone}}
    });
    if(error) throw error;
    return data.user;
  },
  async signIn(email, password){
    const {data, error} = await db.auth.signInWithPassword({email, password});
    if(error) throw error;
    return data.user;
  },
  async signOut(){ await db.auth.signOut(); },
  async me(){
    const {data:{user}} = await db.auth.getUser();
    if(!user) return null;
    const {data:profile} = await db.from('profiles').select('*').eq('id', user.id).single();
    return {...user, profile};
  },
  onChange(cb){ db.auth.onAuthStateChange((_e, session) => cb(session?.user ?? null)); }
};

// ---------------- listings ----------------
const Listings = {
  // public parts ledger
  async browse({q = '', brand = '', category = '', grade = ''} = {}){
    let query = db.from('listings')
      .select('*, sellers(shop_name, status)')
      .eq('status','live').gt('stock', 0)
      .order('created_at', {ascending:false});

    if(brand)    query = query.eq('brand', brand);
    if(category) query = query.eq('category', category);
    if(grade)    query = query.eq('grade', grade);
    if(q)        query = query.or(`name.ilike.%${q}%,sku.ilike.%${q}%`);

    const {data, error} = await query;
    if(error) throw error;
    return data;
  },

  // seller creates a listing — lands as 'pending'
  async create(fields){
    const sellerId = await Sellers.myId();
    if(!sellerId) throw new Error('You are not an approved seller yet.');
    if(fields.is_locked && (!fields.proof_url || !fields.imei))
      throw new Error('Locked stock needs an ownership proof and IMEI.');

    const {data, error} = await db.from('listings').insert({
      seller_id: sellerId,
      sku: fields.sku, name: fields.name, brand: fields.brand,
      category: fields.category, grade: fields.grade,
      price_pesewas: toPesewas(fields.priceGHS),
      stock: fields.stock ?? 1,
      is_locked: !!fields.is_locked,
      proof_url: fields.proof_url ?? null,
      imei: fields.imei ?? null,
      photos: fields.photos ?? []
    }).select().single();
    if(error) throw error;
    await Notify.adminNewListing(data);
    return data;
  },

  async mine(){
    const sellerId = await Sellers.myId();
    if(!sellerId) return [];
    const {data, error} = await db.from('listings')
      .select('*').eq('seller_id', sellerId).order('created_at',{ascending:false});
    if(error) throw error;
    return data;
  },

  // product photos live in a public bucket — buyers must be able to see them.
  // Returns public URLs ready to drop straight into an <img src>.
  async uploadPhotos(files){
    const {data:{user}} = await db.auth.getUser();
    const urls = [];
    for(const f of files){
      if(f.size > 5 * 1024 * 1024) throw new Error(`${f.name} is over 5MB. Please use a smaller photo.`);
      const ext  = (f.name.split('.').pop() || 'jpg').toLowerCase();
      const path = `${user.id}/${Date.now()}-${Math.random().toString(36).slice(2,7)}.${ext}`;
      const {error} = await db.storage.from('photos').upload(path, f, {contentType:f.type});
      if(error) throw error;
      urls.push(db.storage.from('photos').getPublicUrl(path).data.publicUrl);
    }
    return urls;
  },

  // upload an ownership proof, returns the storage path
  async uploadProof(file){
    const {data:{user}} = await db.auth.getUser();
    const path = `${user.id}/${Date.now()}-${file.name}`;
    const {error} = await db.storage.from('proofs').upload(path, file);
    if(error) throw error;
    return path;
  }
};

// ---------------- sellers ----------------
const Sellers = {
  async apply({shopName, payoutPhone, payoutNet, location, stockDesc, ghanaCard}){
    const {data:{user}} = await db.auth.getUser();
    if(!user) throw new Error('Sign in first.');
    const {data, error} = await db.from('sellers').insert({
      user_id:user.id, shop_name:shopName, payout_phone:payoutPhone,
      payout_net:payoutNet, location, stock_desc:stockDesc, ghana_card:ghanaCard
    }).select().single();
    if(error) throw error;
    await Notify.adminNewSeller(data);   // Telegram ping
    return data;
  },
  async mine(){
    const {data} = await db.from('sellers').select('*').maybeSingle();
    return data;
  },
  async myId(){
    const s = await this.mine();
    return s && s.status === 'approved' ? s.id : null;
  }
};

// ---------------- orders ----------------
const Orders = {
  async create({items, buyerName, buyerPhone, deliveryArea, momoNetwork}){
    const {data:{user}} = await db.auth.getUser();
    if(!user) throw new Error('Sign in to place an order.');

    const subtotal = items.reduce((a,i) => a + i.price_pesewas * i.qty, 0);
    const delivery = subtotal > 50000 ? 0 : 2500;   // free over ₵500
    const ref = 'ILX-' + Math.random().toString(36).slice(2,7).toUpperCase();

    const {data:order, error} = await db.from('orders').insert({
      ref, buyer_id:user.id, buyer_name:buyerName, buyer_phone:buyerPhone,
      delivery_area:deliveryArea, momo_network:momoNetwork,
      subtotal_pesewas:subtotal, delivery_pesewas:delivery,
      total_pesewas: subtotal + delivery
    }).select().single();
    if(error) throw error;

    const rows = items.map(i => {
      const gross = i.price_pesewas * i.qty;
      const commission = Math.round(gross * COMMISSION);
      return {
        order_id:order.id, listing_id:i.id, seller_id:i.seller_id,
        sku:i.sku, name:i.name, unit_pesewas:i.price_pesewas, qty:i.qty,
        commission_pesewas:commission, payout_pesewas:gross - commission
      };
    });
    const {error:e2} = await db.from('order_items').insert(rows);
    if(e2) throw e2;

    return order;   // hand order.ref + total to Paystack next
  },

  async mine(){
    const {data, error} = await db.from('orders')
      .select('*, order_items(*)').order('created_at',{ascending:false});
    if(error) throw error;
    return data;
  },

  // buyer releases the money
  async confirmDelivery(ref){
    const {error} = await db.rpc('confirm_delivery', {order_ref: ref});
    if(error) throw error;
  }
};

// ---------------- admin ----------------
const Admin = {
  async pendingSellers(){
    const {data} = await db.from('sellers').select('*').eq('status','pending')
      .order('created_at',{ascending:true});
    return data ?? [];
  },
  async pendingListings(){
    const {data} = await db.from('listings')
      .select('*, sellers(shop_name)').eq('status','pending')
      .order('created_at',{ascending:true});
    return data ?? [];
  },
  async decideSeller(id, approve, reason = null){
    const {data:{user}} = await db.auth.getUser();
    const {error} = await db.from('sellers').update({
      status: approve ? 'approved' : 'rejected',
      reviewed_by:user.id, reviewed_at:new Date().toISOString(), reject_reason:reason
    }).eq('id', id);
    if(error) throw error;
  },
  async decideListing(id, approve, reason = null){
    const {data:{user}} = await db.auth.getUser();
    const {error} = await db.from('listings').update({
      status: approve ? 'live' : 'rejected',
      reviewed_by:user.id, reviewed_at:new Date().toISOString()
    }).eq('id', id);
    // the DB blocks approving locked stock with no proof — surface that plainly
    if(error) throw new Error(
      error.message.includes('locked_needs_proof')
        ? 'This listing is from a locked device and has no ownership proof or IMEI. It cannot go live.'
        : error.message);
  },
  // orders you still owe a seller for
  async payoutsDue(){
    const {data} = await db.from('orders')
      .select('*, order_items(*, sellers(shop_name, payout_phone, payout_net))')
      .eq('status','delivered').eq('payout_done', false);
    return data ?? [];
  },
  async markPaidOut(orderId){
    await db.from('orders').update({payout_done:true}).eq('id', orderId);
  },
  // signed link so you can view an ownership proof
  async proofUrl(path){
    const {data} = await db.storage.from('proofs').createSignedUrl(path, 300);
    return data?.signedUrl;
  }
};

// ---------------- Telegram alerts ----------------
// Calls a Supabase Edge Function — the bot token must NEVER sit in this file.
const Notify = {
  async adminNewSeller(s){
    try{
      await db.functions.invoke('notify-admin', {
        body:{ type:'seller', id:s.id, name:s.shop_name, location:s.location,
               payout_net:s.payout_net, payout_phone:s.payout_phone, stock_desc:s.stock_desc }
      });
    }catch(e){ console.warn('Telegram alert failed', e); }
  },
  async adminNewListing(l){
    try{
      await db.functions.invoke('notify-admin', {
        body:{ type:'listing', id:l.id, name:l.name, sku:l.sku,
               price_pesewas:l.price_pesewas, locked:l.is_locked,
               proof:!!l.proof_url, imei:l.imei }
      });
    }catch(e){ console.warn('Telegram alert failed', e); }
  }
};
