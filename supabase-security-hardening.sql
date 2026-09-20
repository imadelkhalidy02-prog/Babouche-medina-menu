-- BABOUCHE — SECURITY HARDENING FOR AN EXISTING SUPABASE PROJECT
-- Run this AFTER the main setup, especially if your existing project was
-- created with the earlier policy that allowed every authenticated user to edit.
--
-- IMPORTANT: First create the admin user in Supabase Auth, then replace the
-- email below and run the ADMIN ROLE statement at the bottom.

-- Public visitors can read the menu. Auth users with app_metadata.role=admin or owner
-- can write menu/settings data. Only the owner can manage other administrators.
-- app_metadata is used because normal browser users
-- cannot safely self-assign it.

revoke insert, update, delete on public.settings, public.categories, public.menu_items from anon;
grant select on public.settings, public.categories, public.menu_items to anon;
grant select, insert, update, delete on public.settings, public.categories, public.menu_items to authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;

alter table public.settings enable row level security;
alter table public.categories enable row level security;
alter table public.menu_items enable row level security;

drop policy if exists "settings_all" on public.settings;
drop policy if exists "categories_all" on public.categories;
drop policy if exists "menu_items_all" on public.menu_items;
drop policy if exists "settings_select_public" on public.settings;
drop policy if exists "settings_write_admin" on public.settings;
drop policy if exists "categories_select_public" on public.categories;
drop policy if exists "categories_write_admin" on public.categories;
drop policy if exists "menu_items_select_public" on public.menu_items;
drop policy if exists "menu_items_write_admin" on public.menu_items;

create policy "settings_select_public" on public.settings
  for select to anon, authenticated using (true);
create policy "settings_write_admin" on public.settings
  for all to authenticated
  using ((select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'))
  with check ((select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'));

create policy "categories_select_public" on public.categories
  for select to anon, authenticated using (true);
create policy "categories_write_admin" on public.categories
  for all to authenticated
  using ((select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'))
  with check ((select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'));

create policy "menu_items_select_public" on public.menu_items
  for select to anon, authenticated using (true);
create policy "menu_items_write_admin" on public.menu_items
  for all to authenticated
  using ((select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'))
  with check ((select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'));

-- Storage: public read for menu images, admin-only writes.
drop policy if exists "menu_images_select" on storage.objects;
drop policy if exists "menu_images_insert" on storage.objects;
drop policy if exists "menu_images_update" on storage.objects;
drop policy if exists "menu_images_delete" on storage.objects;

create policy "menu_images_select" on storage.objects
  for select using (bucket_id = 'menu-images');
create policy "menu_images_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'menu-images' and (select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'));
create policy "menu_images_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'menu-images' and (select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'))
  with check (bucket_id = 'menu-images' and (select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'));
create policy "menu_images_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'menu-images' and (select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'));

-- OWNER ROLE: replace the email, then run this statement once for the original owner account.
-- The user must sign out and sign in again afterwards so the JWT receives the role.
-- update auth.users
-- set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"owner"}'::jsonb
-- where email = 'YOUR-ADMIN-EMAIL';
