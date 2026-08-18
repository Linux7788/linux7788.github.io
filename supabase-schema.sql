-- ============================================================
-- iLiNuX Marketplace — Supabase schema
-- Run this ONCE in Supabase: Dashboard → SQL Editor → New query → Run
-- ============================================================

-- Profiles table: extends Supabase's built-in auth.users
create table profiles (
  id uuid references auth.users on delete cascade primary key,
  full_name text,
  phone text,
  role text default 'buyer',            -- 'buyer' or 'admin'
  seller_status text default 'none',    -- 'none' | 'pending' | 'approved' | 'rejected'
  created_at timestamp with time zone default now()
);

-- Listings table
create table listings (
  id uuid default gen_random_uuid() primary key,
  seller_id uuid references profiles(id) on delete cascade,
  title text not null,
  category text not null,
  price numeric not null,
  description text,
  status text default 'pending',        -- 'pending' | 'approved' | 'rejected'
  created_at timestamp with time zone default now()
);

-- ============================================================
-- Row Level Security — keeps buyers/sellers from editing each other's data
-- ============================================================
alter table profiles enable row level security;
alter table listings enable row level security;

-- Anyone can read any profile (needed to show seller name on listings)
create policy "Profiles are viewable by everyone"
  on profiles for select using (true);

-- Users can only edit their own profile
create policy "Users can update own profile"
  on profiles for update using (auth.uid() = id);

-- Users can insert their own profile row on signup
create policy "Users can insert own profile"
  on profiles for insert with check (auth.uid() = id);

-- Everyone can see approved listings; sellers can see their own regardless of status
create policy "Approved listings are public"
  on listings for select using (status = 'approved' or seller_id = auth.uid());

-- Only approved sellers can create listings
create policy "Approved sellers can insert listings"
  on listings for insert with check (
    seller_id = auth.uid()
    and exists (
      select 1 from profiles
      where profiles.id = auth.uid()
      and profiles.seller_status = 'approved'
    )
  );

-- ============================================================
-- IMPORTANT: admin approval policies
-- The policies above don't let anyone change 'status' or 'seller_status' —
-- that's intentional. Approvals happen through the Supabase dashboard
-- initially (Table Editor), OR by making yourself an admin below and
-- adding an admin-only update policy (see step 3 in the setup notes).
-- ============================================================

-- ============================================================
-- SETUP NOTES
-- ============================================================
-- 1. After running this, go to Authentication → Providers and make sure
--    "Email" is enabled (it is by default).
--
-- 2. Sign up for an account through auth.html once the site is live, then
--    in Table Editor → profiles, find your row and set role = 'admin'.
--    This unlocks admin.html for you.
--
-- 3. To let admins update seller_status and listing status from admin.html,
--    run this additional policy (replace nothing — just run as-is):

create policy "Admins can update any profile"
  on profiles for update using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
  );

create policy "Admins can update any listing"
  on listings for update using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
  );
