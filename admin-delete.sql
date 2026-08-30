-- iLiNuX marketplace — admin delete permissions
-- Run this ONCE in Supabase → SQL Editor → New query → Run.
--
-- Why this is needed: the original schema created no DELETE policy on any
-- table. With row level security on and no policy, Postgres does not raise an
-- error — it silently deletes zero rows and reports success. A Delete button
-- without this file would look like it worked and change nothing.
--
-- Safe to run more than once.

-- ------------------------------------------------------------------
-- 1. Confirm you are actually flagged as admin.
--    If this returns nothing, nothing below will work for you.
-- ------------------------------------------------------------------
-- select id, full_name, is_admin from public.profiles where is_admin = true;

-- ------------------------------------------------------------------
-- 2. Delete policies, all gated on public.is_admin()
-- ------------------------------------------------------------------

drop policy if exists "listing_admin_delete" on public.listings;
create policy "listing_admin_delete"
on public.listings
for delete
to authenticated
using ( public.is_admin() );

-- Note: "photos" is a storage bucket, not a table. Image objects are removed
-- through the storage API by the admin panel, not by a row policy here.

drop policy if exists "seller_admin_delete" on public.sellers;
create policy "seller_admin_delete"
on public.sellers
for delete
to authenticated
using ( public.is_admin() );

-- The software store tables were never added to schema.sql, so guard them.
do $$
begin
  if to_regclass('public.software') is not null then
    execute 'alter table public.software enable row level security';
    execute 'drop policy if exists "software_admin_delete" on public.software';
    execute 'create policy "software_admin_delete" on public.software
             for delete to authenticated using ( public.is_admin() )';
    execute 'drop policy if exists "software_admin_write" on public.software';
    execute 'create policy "software_admin_write" on public.software
             for update to authenticated
             using ( public.is_admin() ) with check ( public.is_admin() )';
    execute 'drop policy if exists "software_admin_insert" on public.software';
    execute 'create policy "software_admin_insert" on public.software
             for insert to authenticated with check ( public.is_admin() )';
    -- buyers see only what is on sale; the admin sees everything
    execute 'drop policy if exists "software_public_read" on public.software';
    execute 'create policy "software_public_read" on public.software
             for select using ( status = ''live'' or public.is_admin() )';
  end if;

  if to_regclass('public.licenses') is not null then
    execute 'drop policy if exists "licenses_admin_read" on public.licenses';
    execute 'create policy "licenses_admin_read" on public.licenses
             for select to authenticated
             using ( public.is_admin() or user_id = auth.uid() )';
  end if;
end $$;

-- ------------------------------------------------------------------
-- 3. A published price must never be null again.
--    The old admin code wrote NaN here whenever you tapped "Put live",
--    which Postgres stored as null and the site displayed as GHS 0.00.
-- ------------------------------------------------------------------
do $$
begin
  if to_regclass('public.software') is not null then
    -- fix anything already broken before adding the constraint
    execute 'update public.software set status = ''draft''
             where price_pesewas is null and status = ''live''';
    begin
      execute 'alter table public.software
               add constraint software_live_needs_price
               check ( status <> ''live'' or (price_pesewas is not null and price_pesewas > 0) )';
    exception when duplicate_object then null;
    end;
  end if;
end $$;

-- ------------------------------------------------------------------
-- 4. Show anything the old bug already damaged, so you can re-price it.
-- ------------------------------------------------------------------
-- select id, name, price_pesewas, status from public.software
-- where price_pesewas is null or price_pesewas = 0;
