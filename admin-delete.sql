-- iLiNuX marketplace — full admin delete
-- Run this in Supabase → SQL Editor → New query → Run.
-- Safe to run more than once.
--
-- ============================================================
-- READ SECTION 2 BEFORE YOU RUN IT. It permanently changes what
-- a delete takes with it.
-- ============================================================


-- ------------------------------------------------------------------
-- 1. Permission to delete  (already applied on 30 Aug 2026)
-- ------------------------------------------------------------------
-- With row level security on and no DELETE policy, Postgres does not
-- raise an error — it deletes zero rows and reports success.

drop policy if exists "listing_admin_delete" on public.listings;
create policy "listing_admin_delete" on public.listings
for delete to authenticated using ( public.is_admin() );

drop policy if exists "seller_admin_delete" on public.sellers;
create policy "seller_admin_delete" on public.sellers
for delete to authenticated using ( public.is_admin() );

drop policy if exists "orders_admin_delete" on public.orders;
create policy "orders_admin_delete" on public.orders
for delete to authenticated using ( public.is_admin() );

do $$
begin
  if to_regclass('public.software') is not null then
    execute 'alter table public.software enable row level security';
    execute 'drop policy if exists "software_admin_delete" on public.software';
    execute 'create policy "software_admin_delete" on public.software
             for delete to authenticated using ( public.is_admin() )';
  end if;
end $$;


-- ------------------------------------------------------------------
-- 2. THE ONE THAT ACTUALLY UNBLOCKS DELETE  <-- not yet applied
-- ------------------------------------------------------------------
-- Permission was never the problem. Postgres refuses the delete because
-- other rows still point at it:
--
--   ERROR 23503: update or delete on table "software" violates foreign key
--   constraint "software_orders_software_id_fkey" on table "software_orders"
--
-- This rebuilds every foreign key that points at a content table as
-- ON DELETE CASCADE, so the dependent rows are removed with the parent.
--
-- WHAT THIS MEANS IN PRACTICE:
--   delete a piece of software -> its licences and software_orders rows go too
--   delete a listing           -> its order_items rows go too
--   delete a seller            -> their listings go, and those listings'
--                                 order_items go
--   delete an order            -> its order_items go
--
-- Those rows are your sales records. Once deleted they are not recoverable
-- and the order they belonged to is left incomplete. Foreign keys pointing
-- at profiles / auth.users are deliberately left alone.
--
-- If you would rather keep sales history, do NOT run this section — use
-- "Take down" / "Take offline" instead, which hides an item from the site
-- and is reversible.

do $$
declare r record; stripped text;
begin
  for r in
    select con.conname,
           con.conrelid::regclass::text  as child,
           con.confrelid::regclass::text as parent,
           pg_get_constraintdef(con.oid) as def
    from pg_constraint con
    join pg_namespace n on n.oid = con.connamespace and n.nspname = 'public'
    where con.contype = 'f'
      and con.confdeltype <> 'c'                          -- not already cascade
      and con.confrelid::regclass::text
          in ('listings','sellers','software','orders')   -- never profiles
  loop
    stripped := regexp_replace(r.def, '\s+ON DELETE .*$', '', 'i');
    execute format('alter table %s drop constraint %I', r.child, r.conname);
    execute format('alter table %s add constraint %I %s on delete cascade',
                   r.child, r.conname, stripped);
    raise notice 'cascaded: % on % -> %', r.conname, r.child, r.parent;
  end loop;
end $$;


-- ------------------------------------------------------------------
-- 3. A published price can never be null again
-- ------------------------------------------------------------------
do $$
begin
  if to_regclass('public.software') is not null then
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
-- 4. Check it worked
-- ------------------------------------------------------------------
-- Should list the cascaded keys:
--
-- select con.conrelid::regclass::text as child, con.confrelid::regclass::text as parent
-- from pg_constraint con
-- join pg_namespace n on n.oid = con.connamespace and n.nspname='public'
-- where con.contype='f' and con.confdeltype='c'
--   and con.confrelid::regclass::text in ('listings','sellers','software','orders');
