-- ============================================================
-- iLinux Marketplace — Supabase schema (safe to re-run)
-- Every statement checks before it acts, so running this twice
-- changes nothing the second time.
-- ============================================================

-- ---------- types ----------
do $$ begin
  if not exists (select 1 from pg_type where typname = 'seller_status') then
    create type seller_status as enum ('pending','approved','rejected','suspended');
  end if;
  if not exists (select 1 from pg_type where typname = 'listing_status') then
    create type listing_status as enum ('pending','live','rejected','sold_out','hidden');
  end if;
  if not exists (select 1 from pg_type where typname = 'order_status') then
    create type order_status as enum ('awaiting_payment','held','delivered','refunded','cancelled');
  end if;
end $$;

-- ---------- profiles ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users on delete cascade,
  full_name   text,
  phone       text,
  is_admin    boolean not null default false,
  created_at  timestamptz not null default now()
);

-- if a profiles table already existed with a different shape, top it up
alter table public.profiles add column if not exists full_name  text;
alter table public.profiles add column if not exists phone      text;
alter table public.profiles add column if not exists is_admin   boolean not null default false;
alter table public.profiles add column if not exists created_at timestamptz not null default now();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'phone')
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- sellers ----------
create table if not exists public.sellers (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  shop_name     text not null,
  payout_phone  text not null,
  payout_net    text not null,
  location      text not null,
  stock_desc    text,
  ghana_card    text,
  status        seller_status not null default 'pending',
  reviewed_by   uuid references public.profiles(id),
  reviewed_at   timestamptz,
  reject_reason text,
  created_at    timestamptz not null default now(),
  unique (user_id)
);
create index if not exists sellers_status_idx on public.sellers (status);

-- ---------- listings ----------
create table if not exists public.listings (
  id            uuid primary key default gen_random_uuid(),
  seller_id     uuid not null references public.sellers(id) on delete cascade,
  sku           text not null unique,
  name          text not null,
  brand         text not null,
  category      text not null,
  grade         text not null check (grade in ('A','B')),
  price_pesewas integer not null check (price_pesewas > 0),
  stock         integer not null default 1 check (stock >= 0),
  is_locked     boolean not null default false,
  proof_url     text,
  imei          text,
  status        listing_status not null default 'pending',
  reviewed_by   uuid references public.profiles(id),
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now()
);
create index if not exists listings_status_idx on public.listings (status);
create index if not exists listings_seller_idx on public.listings (seller_id);


-- ---------- orders ----------
create table if not exists public.orders (
  id               uuid primary key default gen_random_uuid(),
  ref              text not null unique,
  buyer_id         uuid references public.profiles(id),
  buyer_name       text not null,
  buyer_phone      text not null,
  delivery_area    text not null,
  momo_network     text,
  subtotal_pesewas integer not null,
  delivery_pesewas integer not null default 0,
  total_pesewas    integer not null,
  status           order_status not null default 'awaiting_payment',
  paystack_ref     text,
  paid_at          timestamptz,
  confirmed_at     timestamptz,
  payout_done      boolean not null default false,
  created_at       timestamptz not null default now()
);
create index if not exists orders_buyer_idx  on public.orders (buyer_id);
create index if not exists orders_status_idx on public.orders (status);

create table if not exists public.order_items (
  id                 uuid primary key default gen_random_uuid(),
  order_id           uuid not null references public.orders(id) on delete cascade,
  listing_id         uuid references public.listings(id),
  seller_id          uuid references public.sellers(id),
  sku                text not null,
  name               text not null,
  unit_pesewas       integer not null,
  qty                integer not null check (qty > 0),
  commission_pesewas integer not null,
  payout_pesewas     integer not null
);
create index if not exists order_items_order_idx  on public.order_items (order_id);
create index if not exists order_items_seller_idx on public.order_items (seller_id);

-- ---------- top up any pre-existing tables with missing columns ----------
-- sellers
alter table public.sellers add column if not exists user_id uuid references public.profiles(id) on delete cascade;
alter table public.sellers add column if not exists shop_name text;
alter table public.sellers add column if not exists payout_phone text;
alter table public.sellers add column if not exists payout_net text;
alter table public.sellers add column if not exists location text;
alter table public.sellers add column if not exists stock_desc text;
alter table public.sellers add column if not exists ghana_card text;
alter table public.sellers add column if not exists status seller_status not null default 'pending';
alter table public.sellers add column if not exists reviewed_by uuid references public.profiles(id);
alter table public.sellers add column if not exists reviewed_at timestamptz;
alter table public.sellers add column if not exists reject_reason text;
alter table public.sellers add column if not exists created_at timestamptz not null default now();

-- listings
alter table public.listings add column if not exists seller_id uuid references public.sellers(id) on delete cascade;
alter table public.listings add column if not exists sku text;
alter table public.listings add column if not exists name text;
alter table public.listings add column if not exists brand text;
alter table public.listings add column if not exists category text;
alter table public.listings add column if not exists grade text;
alter table public.listings add column if not exists price_pesewas integer;
alter table public.listings add column if not exists stock integer not null default 1;
alter table public.listings add column if not exists is_locked boolean not null default false;
alter table public.listings add column if not exists proof_url text;
alter table public.listings add column if not exists imei text;
alter table public.listings add column if not exists status listing_status not null default 'pending';
alter table public.listings add column if not exists reviewed_by uuid references public.profiles(id);
alter table public.listings add column if not exists reviewed_at timestamptz;
alter table public.listings add column if not exists created_at timestamptz not null default now();

-- orders
alter table public.orders add column if not exists ref text;
alter table public.orders add column if not exists buyer_id uuid references public.profiles(id);
alter table public.orders add column if not exists buyer_name text;
alter table public.orders add column if not exists buyer_phone text;
alter table public.orders add column if not exists delivery_area text;
alter table public.orders add column if not exists momo_network text;
alter table public.orders add column if not exists subtotal_pesewas integer;
alter table public.orders add column if not exists delivery_pesewas integer not null default 0;
alter table public.orders add column if not exists total_pesewas integer;
alter table public.orders add column if not exists status order_status not null default 'awaiting_payment';
alter table public.orders add column if not exists paystack_ref text;
alter table public.orders add column if not exists paid_at timestamptz;
alter table public.orders add column if not exists confirmed_at timestamptz;
alter table public.orders add column if not exists payout_done boolean not null default false;
alter table public.orders add column if not exists created_at timestamptz not null default now();

-- order_items
alter table public.order_items add column if not exists order_id uuid references public.orders(id) on delete cascade;
alter table public.order_items add column if not exists listing_id uuid references public.listings(id);
alter table public.order_items add column if not exists seller_id uuid references public.sellers(id);
alter table public.order_items add column if not exists sku text;
alter table public.order_items add column if not exists name text;
alter table public.order_items add column if not exists unit_pesewas integer;
alter table public.order_items add column if not exists qty integer;
alter table public.order_items add column if not exists commission_pesewas integer;
alter table public.order_items add column if not exists payout_pesewas integer;

-- a locked part cannot go live without proof and IMEI on file
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'locked_needs_proof') then
    alter table public.listings add constraint locked_needs_proof check (
      status <> 'live' or is_locked = false or (proof_url is not null and imei is not null)
    );
  end if;
end $$;

-- ============================================================
-- Row Level Security
-- ============================================================
alter table public.profiles    enable row level security;
alter table public.sellers     enable row level security;
alter table public.listings    enable row level security;
alter table public.orders      enable row level security;
alter table public.order_items enable row level security;

create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = '' as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.my_seller_id()
returns uuid language sql security definer stable set search_path = '' as $$
  select id from public.sellers where user_id = auth.uid();
$$;

-- ----- profiles -----
drop policy if exists "read own profile" on public.profiles;
create policy "read own profile" on public.profiles for select
  using (id = auth.uid() or public.is_admin());

drop policy if exists "edit own profile" on public.profiles;
create policy "edit own profile" on public.profiles for update
  using (id = auth.uid())
  with check (id = auth.uid() and is_admin = (select is_admin from public.profiles where id = auth.uid()));

-- ----- sellers -----
drop policy if exists "apply as seller" on public.sellers;
create policy "apply as seller" on public.sellers for insert with check (user_id = auth.uid());

drop policy if exists "read own seller" on public.sellers;
create policy "read own seller" on public.sellers for select
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists "admin edits seller" on public.sellers;
create policy "admin edits seller" on public.sellers for update using (public.is_admin());

-- ----- listings -----
drop policy if exists "anyone reads live" on public.listings;
create policy "anyone reads live" on public.listings for select
  using (status = 'live' or seller_id = public.my_seller_id() or public.is_admin());

drop policy if exists "approved seller lists" on public.listings;
create policy "approved seller lists" on public.listings for insert
  with check (
    seller_id = public.my_seller_id()
    and status = 'pending'
    and exists (select 1 from public.sellers s where s.id = seller_id and s.status = 'approved')
  );

drop policy if exists "seller edits own" on public.listings;
create policy "seller edits own" on public.listings for update
  using (seller_id = public.my_seller_id()) with check (status = 'pending');

drop policy if exists "admin edits listing" on public.listings;
create policy "admin edits listing" on public.listings for update using (public.is_admin());

-- ----- orders -----
drop policy if exists "buyer reads own order" on public.orders;
create policy "buyer reads own order" on public.orders for select
  using (buyer_id = auth.uid() or public.is_admin());

drop policy if exists "buyer creates order" on public.orders;
create policy "buyer creates order" on public.orders for insert
  with check (buyer_id = auth.uid() and status = 'awaiting_payment');

drop policy if exists "admin edits order" on public.orders;
create policy "admin edits order" on public.orders for update using (public.is_admin());

-- ----- order items -----
drop policy if exists "read own items" on public.order_items;
create policy "read own items" on public.order_items for select using (
  public.is_admin()
  or seller_id = public.my_seller_id()
  or exists (select 1 from public.orders o where o.id = order_id and o.buyer_id = auth.uid())
);

drop policy if exists "insert own items" on public.order_items;
create policy "insert own items" on public.order_items for insert with check (
  exists (select 1 from public.orders o where o.id = order_id and o.buyer_id = auth.uid())
);

-- ============================================================
-- Buyer confirms delivery — the only way an order leaves 'held'
-- ============================================================
create or replace function public.confirm_delivery(order_ref text)
returns void language plpgsql security definer set search_path = '' as $$
declare o public.orders;
begin
  select * into o from public.orders where ref = order_ref;
  if o is null then raise exception 'Order not found'; end if;
  if o.buyer_id <> auth.uid() then raise exception 'Not your order'; end if;
  if o.status <> 'held' then raise exception 'Order is not awaiting confirmation'; end if;
  update public.orders set status = 'delivered', confirmed_at = now() where id = o.id;
end; $$;

-- ============================================================
-- Reduce stock when a payment lands (called by the webhook)
-- ============================================================
create or replace function public.decrement_stock(p_listing uuid, p_qty int)
returns void language sql security definer set search_path = '' as $$
  update public.listings
     set stock  = greatest(stock - p_qty, 0),
         status = case when stock - p_qty <= 0 then 'sold_out'::public.listing_status else status end
   where id = p_listing;
$$;

-- ============================================================
-- Storage bucket for ownership proofs (private — admins only)
-- ============================================================
insert into storage.buckets (id, name, public) values ('proofs','proofs',false)
  on conflict (id) do nothing;

drop policy if exists "seller uploads proof" on storage.objects;
create policy "seller uploads proof" on storage.objects for insert
  with check (bucket_id = 'proofs' and auth.uid() is not null);

drop policy if exists "admin reads proofs" on storage.objects;
create policy "admin reads proofs" on storage.objects for select
  using (bucket_id = 'proofs' and public.is_admin());

-- ============================================================
-- Product photos (added after initial build)
-- ============================================================
alter table public.listings add column if not exists photos text[] not null default '{}';

insert into storage.buckets (id, name, public) values ('photos','photos',true)
  on conflict (id) do nothing;

drop policy if exists "anyone views photos" on storage.objects;
create policy "anyone views photos" on storage.objects for select
  using (bucket_id = 'photos');

drop policy if exists "signed in uploads photos" on storage.objects;
create policy "signed in uploads photos" on storage.objects for insert
  with check (bucket_id = 'photos' and auth.uid() is not null);

drop policy if exists "owner removes photos" on storage.objects;
create policy "owner removes photos" on storage.objects for delete
  using (bucket_id = 'photos' and owner = auth.uid());
