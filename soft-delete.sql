-- iLiNuX marketplace — recoverable delete (30-day recycle bin)
-- Run this in Supabase → SQL Editor → New query → Run.
-- Safe to run more than once.
--
-- Replaces "gone forever the instant you tap Delete" with a Deleted tab you
-- can restore from. Rows are stamped with deleted_at instead of being removed,
-- disappear from the site immediately, and are purged for good after 30 days.
-- "Delete forever" in the admin panel still removes a row on the spot, and the
-- cascades applied earlier still apply to that.


-- ------------------------------------------------------------------
-- 1. The recycle-bin column
-- ------------------------------------------------------------------
alter table public.listings add column if not exists deleted_at timestamptz;
alter table public.sellers  add column if not exists deleted_at timestamptz;

do $$
begin
  if to_regclass('public.software') is not null then
    execute 'alter table public.software add column if not exists deleted_at timestamptz';
    execute 'create index if not exists software_deleted_at_idx on public.software(deleted_at)';
  end if;
end $$;

create index if not exists listings_deleted_at_idx on public.listings(deleted_at);
create index if not exists sellers_deleted_at_idx  on public.sellers(deleted_at);


-- ------------------------------------------------------------------
-- 2. A deleted row must vanish from the site immediately
-- ------------------------------------------------------------------
-- Without this a buyer could still read a deleted listing by querying the
-- API directly, even though the app no longer shows it. The admin keeps
-- seeing everything, which is what makes Restore possible.

drop policy if exists "listing_public_read" on public.listings;
create policy "listing_public_read"
on public.listings
for select
using(
  (deleted_at is null and (status = 'live' or seller_id = public.my_seller_id()))
  or public.is_admin()
);

do $$
begin
  if to_regclass('public.software') is not null then
    execute 'drop policy if exists "software_public_read" on public.software';
    execute 'create policy "software_public_read" on public.software
             for select using (
               (deleted_at is null and status = ''live'') or public.is_admin()
             )';
    -- the older duplicate policy from the first build, if it is still there
    execute 'drop policy if exists "anyone reads live software" on public.software';
  end if;
end $$;


-- ------------------------------------------------------------------
-- 3. A deleted seller cannot list anything new
-- ------------------------------------------------------------------
drop policy if exists "listing_seller_insert" on public.listings;
create policy "listing_seller_insert"
on public.listings
for insert
with check(
  seller_id = public.my_seller_id()
  and status = 'pending'
  and exists(
    select 1 from public.sellers s
    where s.id = seller_id
      and s.status = 'approved'
      and s.deleted_at is null
  )
);


-- ------------------------------------------------------------------
-- 4. Purge anything binned more than 30 days ago
-- ------------------------------------------------------------------
-- Called by the admin panel when you open the Deleted tab, so it needs no
-- scheduler. Runs as the definer, and only ever touches rows already binned.

create or replace function public.purge_deleted(older_than_days int default 30)
returns table(table_name text, purged int)
language plpgsql
security definer
set search_path = public
as $$
declare n int; cutoff timestamptz := now() - make_interval(days => older_than_days);
begin
  if not public.is_admin() then
    raise exception 'Only an admin can purge.';
  end if;

  if to_regclass('public.software') is not null then
    delete from public.software where deleted_at is not null and deleted_at < cutoff;
    get diagnostics n = row_count;
    table_name := 'software'; purged := n; return next;
  end if;

  delete from public.listings where deleted_at is not null and deleted_at < cutoff;
  get diagnostics n = row_count;
  table_name := 'listings'; purged := n; return next;

  delete from public.sellers where deleted_at is not null and deleted_at < cutoff;
  get diagnostics n = row_count;
  table_name := 'sellers'; purged := n; return next;
end $$;

revoke all on function public.purge_deleted(int) from public, anon;
grant execute on function public.purge_deleted(int) to authenticated;


-- ------------------------------------------------------------------
-- 5. Check
-- ------------------------------------------------------------------
-- select count(*) filter (where deleted_at is not null) as binned_listings from public.listings;
