-- ============================================================
-- iLiNuX MARKETPLACE
-- SUPABASE DATABASE
-- ============================================================
--
-- Run this in:
-- Supabase Dashboard
-- -> SQL Editor
-- -> New Query
-- -> Paste EVERYTHING
-- -> Run
--
-- Designed to be safe to re-run.
-- ============================================================

create extension if not exists pgcrypto;

-- ============================================================
-- ENUM TYPES
-- ============================================================

do $$
begin

  if not exists (
    select 1 from pg_type
    where typname = 'seller_status'
  ) then
    create type public.seller_status as enum (
      'pending',
      'approved',
      'rejected',
      'suspended'
    );
  end if;

  if not exists (
    select 1 from pg_type
    where typname = 'listing_status'
  ) then
    create type public.listing_status as enum (
      'pending',
      'live',
      'rejected',
      'sold_out',
      'hidden'
    );
  end if;

  if not exists (
    select 1 from pg_type
    where typname = 'order_status'
  ) then
    create type public.order_status as enum (
      'awaiting_payment',
      'held',
      'delivered',
      'refunded',
      'cancelled'
    );
  end if;

end $$;

-- ============================================================
-- PROFILES
-- ============================================================

create table if not exists public.profiles (

  id uuid primary key
    references auth.users(id)
    on delete cascade,

  full_name text,

  phone text,

  is_admin boolean
    not null default false,

  created_at timestamptz
    not null default now()

);

alter table public.profiles
  add column if not exists full_name text;

alter table public.profiles
  add column if not exists phone text;

alter table public.profiles
  add column if not exists is_admin boolean
    not null default false;

alter table public.profiles
  add column if not exists created_at timestamptz
    not null default now();

-- ============================================================
-- CREATE PROFILE AUTOMATICALLY
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

  insert into public.profiles(
    id,
    full_name,
    phone
  )

  values(
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'phone'
  )

  on conflict(id) do nothing;

  return new;

end;
$$;

drop trigger if exists on_auth_user_created
on auth.users;

create trigger on_auth_user_created

after insert on auth.users

for each row

execute function public.handle_new_user();

-- ============================================================
-- SELLERS
-- ============================================================

create table if not exists public.sellers (

  id uuid primary key
    default gen_random_uuid(),

  user_id uuid not null unique
    references public.profiles(id)
    on delete cascade,

  shop_name text not null,

  payout_phone text not null,

  payout_net text not null,

  location text not null,

  stock_desc text,

  ghana_card text,

  status public.seller_status
    not null default 'pending',

  reviewed_by uuid
    references public.profiles(id),

  reviewed_at timestamptz,

  reject_reason text,

  created_at timestamptz
    not null default now()

);

create index if not exists sellers_status_idx
on public.sellers(status);

create index if not exists sellers_user_idx
on public.sellers(user_id);

-- ============================================================
-- LISTINGS
-- ============================================================

create table if not exists public.listings (

  id uuid primary key
    default gen_random_uuid(),

  seller_id uuid not null
    references public.sellers(id)
    on delete cascade,

  sku text not null unique,

  name text not null,

  brand text not null,

  category text not null,

  grade text not null
    check(grade in ('A','B')),

  price_pesewas integer not null
    check(price_pesewas > 0),

  stock integer not null default 1
    check(stock >= 0),

  is_locked boolean not null
    default false,

  proof_url text,

  imei text,

  photos text[] not null
    default '{}',

  status public.listing_status
    not null default 'pending',

  reviewed_by uuid
    references public.profiles(id),

  reviewed_at timestamptz,

  reject_reason text,

  created_at timestamptz
    not null default now()

);

create index if not exists listings_status_idx
on public.listings(status);

create index if not exists listings_seller_idx
on public.listings(seller_id);

create index if not exists listings_brand_idx
on public.listings(brand);

-- Locked stock protection.
do $$
begin

  if not exists (
    select 1
    from pg_constraint
    where conname = 'locked_needs_proof'
  ) then

    alter table public.listings

    add constraint locked_needs_proof

    check(
      status <> 'live'
      or is_locked = false
      or (
        proof_url is not null
        and imei is not null
        and length(regexp_replace(imei,'\D','','g')) = 15
      )
    );

  end if;

end $$;

-- ============================================================
-- ORDERS
-- ============================================================

create table if not exists public.orders (

  id uuid primary key
    default gen_random_uuid(),

  ref text not null unique,

  buyer_id uuid
    references public.profiles(id),

  buyer_name text not null,

  buyer_phone text not null,

  delivery_area text not null,

  momo_network text,

  subtotal_pesewas integer not null,

  delivery_pesewas integer not null
    default 0,

  total_pesewas integer not null,

  status public.order_status
    not null default 'awaiting_payment',

  paystack_ref text,

  paid_at timestamptz,

  confirmed_at timestamptz,

  payout_done boolean not null
    default false,

  created_at timestamptz
    not null default now()

);

create index if not exists orders_buyer_idx
on public.orders(buyer_id);

create index if not exists orders_status_idx
on public.orders(status);

create index if not exists orders_ref_idx
on public.orders(ref);

-- ============================================================
-- ORDER ITEMS
-- ============================================================

create table if not exists public.order_items (

  id uuid primary key
    default gen_random_uuid(),

  order_id uuid not null
    references public.orders(id)
    on delete cascade,

  listing_id uuid
    references public.listings(id),

  seller_id uuid
    references public.sellers(id),

  sku text not null,

  name text not null,

  unit_pesewas integer not null,

  qty integer not null
    check(qty > 0),

  commission_pesewas integer not null,

  payout_pesewas integer not null

);

create index if not exists order_items_order_idx
on public.order_items(order_id);

create index if not exists order_items_seller_idx
on public.order_items(seller_id);

-- ============================================================
-- SECURITY HELPERS
-- ============================================================

create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(
    (
      select is_admin
      from public.profiles
      where id = auth.uid()
    ),
    false
  );
$$;

create or replace function public.my_seller_id()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select id
  from public.sellers
  where user_id = auth.uid()
  limit 1;
$$;

-- ============================================================
-- RLS
-- ============================================================

alter table public.profiles enable row level security;
alter table public.sellers enable row level security;
alter table public.listings enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

-- ============================================================
-- PROFILES POLICIES
-- ============================================================

drop policy if exists "profiles_select_own"
on public.profiles;

create policy "profiles_select_own"

on public.profiles

for select

using(
  id = auth.uid()
  or public.is_admin()
);

drop policy if exists "profiles_update_own"
on public.profiles;

create policy "profiles_update_own"

on public.profiles

for update

using(
  id = auth.uid()
)

with check(
  id = auth.uid()
  and is_admin = public.is_admin()
);

-- ============================================================
-- SELLER POLICIES
-- ============================================================

drop policy if exists "seller_insert_own"
on public.sellers;

create policy "seller_insert_own"

on public.sellers

for insert

with check(
  user_id = auth.uid()
);

drop policy if exists "seller_select_own"
on public.sellers;

create policy "seller_select_own"

on public.sellers

for select

using(
  user_id = auth.uid()
  or public.is_admin()
);

drop policy if exists "seller_admin_update"
on public.sellers;

create policy "seller_admin_update"

on public.sellers

for update

using(
  public.is_admin()
);

-- ============================================================
-- LISTING POLICIES
-- ============================================================

drop policy if exists "listing_public_read"
on public.listings;

create policy "listing_public_read"

on public.listings

for select

using(
  status = 'live'
  or seller_id = public.my_seller_id()
  or public.is_admin()
);

drop policy if exists "listing_seller_insert"
on public.listings;

create policy "listing_seller_insert"

on public.listings

for insert

with check(

  seller_id = public.my_seller_id()

  and status = 'pending'

  and exists(
    select 1
    from public.sellers s
    where s.id = seller_id
    and s.status = 'approved'
  )

);

drop policy if exists "listing_seller_update"
on public.listings;

create policy "listing_seller_update"

on public.listings

for update

using(
  seller_id = public.my_seller_id()
)

with check(
  seller_id = public.my_seller_id()
  and status = 'pending'
);

drop policy if exists "listing_admin_update"
on public.listings;

create policy "listing_admin_update"

on public.listings

for update

using(
  public.is_admin()
);

-- ============================================================
-- ORDER POLICIES
-- ============================================================

drop policy if exists "orders_select_own"
on public.orders;

create policy "orders_select_own"

on public.orders

for select

using(
  buyer_id = auth.uid()
  or public.is_admin()
);

drop policy if exists "orders_insert"
on public.orders;

create policy "orders_insert"

on public.orders

for insert

with check(false);

drop policy if exists "orders_update_admin"
on public.orders;

create policy "orders_update_admin"

on public.orders

for update

using(
  public.is_admin()
);

-- ============================================================
-- ORDER ITEM POLICIES
-- ============================================================

drop policy if exists "order_items_select"
on public.order_items;

create policy "order_items_select"

on public.order_items

for select

using(

  public.is_admin()

  or seller_id = public.my_seller_id()

  or exists(
    select 1
    from public.orders o
    where o.id = order_id
    and o.buyer_id = auth.uid()
  )

);

-- Client cannot insert order items directly.
drop policy if exists "order_items_insert"
on public.order_items;

create policy "order_items_insert"

on public.order_items

for insert

with check(false);

-- ============================================================
-- SECURE ORDER CREATION
-- ============================================================
--
-- Browser supplies only:
-- listing UUID + quantity.
--
-- Database reads:
-- price
-- seller
-- stock
-- product name
-- SKU
--
-- This prevents browser-side price manipulation.
-- ============================================================

create or replace function public.create_order(
  p_items jsonb,
  p_buyer_name text,
  p_buyer_phone text,
  p_delivery_area text,
  p_momo_network text
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$

declare

  v_order public.orders;

  v_item jsonb;

  v_listing public.listings;

  v_qty integer;

  v_subtotal integer := 0;

  v_delivery integer := 0;

  v_total integer := 0;

  v_ref text;

  v_commission integer;

  v_payout integer;

begin

  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'Cart is empty';
  end if;

  if p_momo_network not in(
    'MTN',
    'ATMoney',
    'Telecel'
  ) then
    raise exception 'Invalid mobile money network';
  end if;

  if trim(p_buyer_name) = '' then
    raise exception 'Delivery name is required';
  end if;

  if trim(p_buyer_phone) = '' then
    raise exception 'Buyer phone is required';
  end if;

  if trim(p_delivery_area) = '' then
    raise exception 'Delivery area is required';
  end if;

  -- Lock all requested listing rows during order creation.
  for v_item in
    select value
    from jsonb_array_elements(p_items)
  loop

    v_qty :=
      (v_item->>'qty')::integer;

    if v_qty < 1 then
      raise exception 'Invalid quantity';
    end if;

    select *
    into v_listing
    from public.listings
    where id =
      (v_item->>'id')::uuid
    and status = 'live'
    and stock > 0
    for update;

    if not found then
      raise exception
        'A selected listing is no longer available';
    end if;

    if v_qty > v_listing.stock then
      raise exception
        'Not enough stock for %',
        v_listing.name;
    end if;

    v_subtotal :=
      v_subtotal +
      (
        v_listing.price_pesewas *
        v_qty
      );

  end loop;

  if v_subtotal > 50000 then
    v_delivery := 0;
  else
    v_delivery := 2500;
  end if;

  v_total :=
    v_subtotal +
    v_delivery;

  v_ref :=
    'ILX-' ||
    upper(
      substr(
        replace(
          gen_random_uuid()::text,
          '-',
          ''
        ),
        1,
        10
      )
    );

  insert into public.orders(
    ref,
    buyer_id,
    buyer_name,
    buyer_phone,
    delivery_area,
    momo_network,
    subtotal_pesewas,
    delivery_pesewas,
    total_pesewas
  )

  values(
    v_ref,
    auth.uid(),
    trim(p_buyer_name),
    regexp_replace(
      p_buyer_phone,
      '\D',
      '',
      'g'
    ),
    trim(p_delivery_area),
    p_momo_network,
    v_subtotal,
    v_delivery,
    v_total
  )

  returning *
  into v_order;

  for v_item in
    select value
    from jsonb_array_elements(p_items)
  loop

    v_qty :=
      (v_item->>'qty')::integer;

    select *
    into v_listing
    from public.listings
    where id =
      (v_item->>'id')::uuid
    for update;

    v_commission :=
      round(
        v_listing.price_pesewas *
        v_qty *
        0.15
      );

    v_payout :=
      (
        v_listing.price_pesewas *
        v_qty
      ) -
      v_commission;

    insert into public.order_items(

      order_id,

      listing_id,

      seller_id,

      sku,

      name,

      unit_pesewas,

      qty,

      commission_pesewas,

      payout_pesewas

    )

    values(

      v_order.id,

      v_listing.id,

      v_listing.seller_id,

      v_listing.sku,

      v_listing.name,

      v_listing.price_pesewas,

      v_qty,

      v_commission,

      v_payout

    );

  end loop;

  return v_order;

end;
$$;

-- ============================================================
-- PAYMENT SUCCESS
-- ============================================================
--
-- Called only by the Paystack webhook function.
-- It verifies the order amount before changing it to HELD.
-- ============================================================

create or replace function public.mark_order_paid(
  p_order_ref text,
  p_paystack_ref text,
  p_amount_pesewas integer
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$

declare

  v_order public.orders;

  v_item record;

  v_new_stock integer;

begin

  select *
  into v_order
  from public.orders
  where ref = p_order_ref
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.status = 'held' then
    return v_order;
  end if;

  if v_order.status <> 'awaiting_payment' then
    raise exception 'Order cannot be paid in current state';
  end if;

  if v_order.total_pesewas <> p_amount_pesewas then
    raise exception 'Payment amount does not match order';
  end if;

  for v_item in
    select *
    from public.order_items
    where order_id = v_order.id
    for update
  loop

    update public.listings
    set
      stock =
        greatest(
          stock - v_item.qty,
          0
        ),
      status =
        case
          when stock - v_item.qty <= 0
          then 'sold_out'::public.listing_status
          else status
        end
    where id = v_item.listing_id
    and stock >= v_item.qty;

    if not found then
      raise exception
        'Insufficient stock for %',
        v_item.name;
    end if;

  end loop;

  update public.orders

  set
    status = 'held',
    paystack_ref = p_paystack_ref,
    paid_at = now()

  where id = v_order.id

  returning *
  into v_order;

  return v_order;

end;
$$;

-- ============================================================
-- BUYER CONFIRMS DELIVERY
-- ============================================================

create or replace function public.confirm_delivery(
  order_ref text
)
returns void
language plpgsql
security definer
set search_path = public
as $$

declare
  v_order public.orders;

begin

  select *
  into v_order
  from public.orders
  where ref = order_ref
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.buyer_id <> auth.uid() then
    raise exception 'This is not your order';
  end if;

  if v_order.status <> 'held' then
    raise exception
      'Order is not awaiting delivery confirmation';
  end if;

  update public.orders

  set
    status = 'delivered',
    confirmed_at = now()

  where id = v_order.id;

end;
$$;

-- ============================================================
-- STORAGE
-- ============================================================

insert into storage.buckets(
  id,
  name,
  public
)

values(
  'photos',
  'photos',
  true
)

on conflict(id) do nothing;

insert into storage.buckets(
  id,
  name,
  public
)

values(
  'proofs',
  'proofs',
  false
)

on conflict(id) do nothing;

-- ============================================================
-- PHOTO STORAGE POLICIES
-- ============================================================

drop policy if exists "photos_public_read"
on storage.objects;

create policy "photos_public_read"

on storage.objects

for select

using(
  bucket_id = 'photos'
);

drop policy if exists "photos_authenticated_upload"
on storage.objects;

create policy "photos_authenticated_upload"

on storage.objects

for insert

to authenticated

with check(
  bucket_id = 'photos'
  and auth.uid() is not null
);

drop policy if exists "photos_owner_delete"
on storage.objects;

create policy "photos_owner_delete"

on storage.objects

for delete

to authenticated

using(
  bucket_id = 'photos'
  and owner_id = auth.uid()::text
);

-- ============================================================
-- PROOF STORAGE
-- ============================================================

drop policy if exists "proofs_authenticated_upload"
on storage.objects;

create policy "proofs_authenticated_upload"

on storage.objects

for insert

to authenticated

with check(
  bucket_id = 'proofs'
  and auth.uid() is not null
);

drop policy if exists "proofs_admin_read"
on storage.objects;

create policy "proofs_admin_read"

on storage.objects

for select

to authenticated

using(
  bucket_id = 'proofs'
  and public.is_admin()
);

-- ============================================================
-- REALTIME
-- ============================================================
--
-- Required by the browser payment-status listener.
-- ============================================================

do $$
begin

  begin
    alter publication supabase_realtime
      add table public.orders;
  exception
    when duplicate_object then
      null;
    when undefined_object then
      null;
  end;

end $$;

-- ============================================================
-- GRANTS
-- ============================================================

grant execute on function public.create_order(
  jsonb,
  text,
  text,
  text,
  text
)
to authenticated;

grant execute on function public.confirm_delivery(text)
to authenticated;

grant execute on function public.mark_order_paid(
  text,
  text,
  integer
)
to service_role;

-- ============================================================
-- END
-- ============================================================