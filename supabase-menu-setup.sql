-- ============================================================
-- BABOUCHE — Menu database setup
-- Run this once in Supabase → SQL Editor → New query → Run
-- Safe to re-run (uses IF NOT EXISTS / ON CONFLICT).
--
-- IMPORTANT — this script sets up TABLES and PERMISSIONS, but it does
-- NOT create your admin login. That's a separate one-time step:
--   Supabase Dashboard → Authentication → Users → Add user
--   → enter the admin's email + a password → Create user.
-- That account is what you'll use to sign in on admin.html.
-- See SETUP-README.md for the full walkthrough.
-- ============================================================

-- 1) SETTINGS (WhatsApp number, socials, header photo, etc.)
create table if not exists public.settings (
  key   text primary key,
  value text
);

insert into public.settings (key, value) values
  ('whatsapp_number', '212600000000'),
  ('header_image_url', 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1000&q=80'),
  ('default_language', 'es'),
  ('google_maps_url', 'https://g.page/r/YOUR_PLACE_ID/review'),
  ('instagram_url', 'https://instagram.com/YOUR_PAGE'),
  ('tripadvisor_url', 'https://www.tripadvisor.com/YOUR_PAGE')
on conflict (key) do nothing;

-- The old shared "admin_password" setting is no longer used now that the
-- admin panel uses real Supabase Auth accounts instead. Safe to remove.
delete from public.settings where key = 'admin_password';

-- If this project was seeded before the footer icon changed from Facebook to
-- Google Maps, carry the old value over to the new key instead of losing it.
update public.settings set key = 'google_maps_url' where key = 'facebook_url';

-- 1b) STORAGE — bucket for photos uploaded from the admin panel
--     (dish photos + header photo). Public READ so the menu page can
--     display them to every visitor; write access (upload/replace/delete)
--     requires a signed-in Supabase Auth session, i.e. a logged-in admin.
insert into storage.buckets (id, name, public)
values ('menu-images', 'menu-images', true)
on conflict (id) do nothing;

drop policy if exists "menu_images_select" on storage.objects;
drop policy if exists "menu_images_insert" on storage.objects;
drop policy if exists "menu_images_update" on storage.objects;
drop policy if exists "menu_images_delete" on storage.objects;

create policy "menu_images_select" on storage.objects
  for select using (bucket_id = 'menu-images');

create policy "menu_images_insert" on storage.objects
  for insert with check (bucket_id = 'menu-images' and (select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'));

create policy "menu_images_update" on storage.objects
  for update using (bucket_id = 'menu-images' and (select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'));

create policy "menu_images_delete" on storage.objects
  for delete using (bucket_id = 'menu-images' and (select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'));

-- 2) CATEGORIES
create table if not exists public.categories (
  id         uuid primary key default gen_random_uuid(),
  slug       text unique not null,
  sort_order int  not null default 0,
  name_en    text not null,
  name_fr    text not null,
  name_es    text not null,
  created_at timestamptz default now()
);

-- 3) MENU ITEMS
create table if not exists public.menu_items (
  id           uuid primary key default gen_random_uuid(),
  category_id  uuid references public.categories(id) on delete cascade,
  sort_order   int  not null default 0,
  name_en      text not null,
  name_fr      text not null,
  name_es      text not null,
  desc_en      text,
  desc_fr      text,
  desc_es      text,
  price        numeric not null default 0,
  image_url    text,
  available    boolean not null default true,
  created_at   timestamptz default now()
);

-- 3b) DATA API GRANTS
-- New Supabase projects can have "Automatically expose new tables" disabled.
-- supabase-js uses the Data API, so explicitly grant the required privileges.
grant select on public.settings, public.categories, public.menu_items to anon;
grant select, insert, update, delete on public.settings, public.categories, public.menu_items to authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;

-- 4) Row Level Security
--    Everyone (including anonymous visitors) can READ the menu and
--    settings — that's how the public menu page works with no login.
--    Only a signed-in Supabase Auth admin can WRITE (insert/update/delete).
alter table public.settings   enable row level security;
alter table public.categories enable row level security;
alter table public.menu_items enable row level security;

drop policy if exists "settings_all"   on public.settings;
drop policy if exists "categories_all" on public.categories;
drop policy if exists "menu_items_all" on public.menu_items;
drop policy if exists "settings_select_public"     on public.settings;
drop policy if exists "settings_write_admin"       on public.settings;
drop policy if exists "categories_select_public"   on public.categories;
drop policy if exists "categories_write_admin"     on public.categories;
drop policy if exists "menu_items_select_public"   on public.menu_items;
drop policy if exists "menu_items_write_admin"     on public.menu_items;

create policy "settings_select_public" on public.settings for select using (true);
create policy "settings_write_admin" on public.settings for all
  to authenticated
  using ((select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'))
  with check ((select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'));

create policy "categories_select_public" on public.categories for select using (true);
create policy "categories_write_admin" on public.categories for all
  to authenticated
  using ((select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'))
  with check ((select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'));

create policy "menu_items_select_public" on public.menu_items for select using (true);
create policy "menu_items_write_admin" on public.menu_items for all
  to authenticated
  using ((select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'))
  with check ((select auth.jwt()->'app_metadata'->>'role') in ('admin','owner'));

-- 5) SEED DATA — everything that was previously hard-coded in
--    index.html, so the live menu doesn't lose anything.
-- ============================================================

do $$
declare
  c_starters   uuid;
  c_mains      uuid;
  c_couscous   uuid;
  c_tajines    uuid;
  c_fastfood   uuid;
  c_pizza      uuid;
  c_desserts   uuid;
  c_hotdrinks  uuid;
  c_colddrinks uuid;
  c_juices     uuid;
begin

  insert into public.categories (slug, sort_order, name_en, name_fr, name_es) values
    ('starters',   1, 'Starters', 'Entrées', 'Entrantes')
    returning id into c_starters;
  insert into public.categories (slug, sort_order, name_en, name_fr, name_es) values
    ('mains',      2, 'Main Dishes', 'Plats principaux', 'Platos Principales')
    returning id into c_mains;
  insert into public.categories (slug, sort_order, name_en, name_fr, name_es) values
    ('couscous',   3, 'Couscous', 'Couscous', 'Cuscús')
    returning id into c_couscous;
  insert into public.categories (slug, sort_order, name_en, name_fr, name_es) values
    ('tajines',    4, 'Tajines', 'Tajines', 'Tajines')
    returning id into c_tajines;
  insert into public.categories (slug, sort_order, name_en, name_fr, name_es) values
    ('fastfood',   5, 'Fast Food', 'Fast food', 'Comida Rápida')
    returning id into c_fastfood;
  insert into public.categories (slug, sort_order, name_en, name_fr, name_es) values
    ('pizza',      6, 'Pizza', 'Pizza', 'Pizza')
    returning id into c_pizza;
  insert into public.categories (slug, sort_order, name_en, name_fr, name_es) values
    ('desserts',   7, 'Desserts', 'Desserts', 'Postres')
    returning id into c_desserts;
  insert into public.categories (slug, sort_order, name_en, name_fr, name_es) values
    ('hotdrinks',  8, 'Hot Drinks', 'Boissons chaudes', 'Bebidas Calientes')
    returning id into c_hotdrinks;
  insert into public.categories (slug, sort_order, name_en, name_fr, name_es) values
    ('colddrinks', 9, 'Cold Drinks', 'Boissons froides', 'Bebidas Frías')
    returning id into c_colddrinks;
  insert into public.categories (slug, sort_order, name_en, name_fr, name_es) values
    ('juices',    10, 'Juices', 'Jus', 'Zumos')
    returning id into c_juices;

  -- STARTERS
  insert into public.menu_items (category_id, sort_order, name_en, name_fr, name_es, desc_en, desc_fr, desc_es, price, image_url) values
  (c_starters, 1, 'Moroccan salad', 'Salade marocaine', 'Ensalada marroquí', 'Tomato, onions, cucumber, pepper', 'Tomate, oignons, concombre, poivron', 'Tomate, cebolla, pepino, pimiento', 40, 'images/salade-marocaine.jpg'),
  (c_starters, 2, 'Assortment Briouat', 'Assortiment Briouates', 'Surtido de Briouats', 'Cheese, minced meat', 'Fromage, viande hachée', 'Queso, carne picada', 55, 'images/assortiment-briouates.jpg'),
  (c_starters, 3, 'Tabouleh salad', 'Salade taboulé', 'Ensalada tabulé', 'Borghol, tomato, pepper, cucumber, onions, mint, olive oil', 'Borghol, tomate, poivron, concombre, oignons, menthe, huile d''olive', 'Burgol, tomate, pimiento, pepino, cebolla, menta, aceite de oliva', 40, 'images/salade-taboule.jpg'),
  (c_starters, 4, 'Aubergines gratin', 'Aubergines gratin', 'Berenjenas al gratén', null, null, null, 50, 'images/aubergines-gratin.png'),
  (c_starters, 5, 'Babouche salad with seafood', 'Babouche aux fruits de mer', 'Ensalada Babouche con mariscos', 'Red salad, citrus segments, apple, pineapple, seafood', 'Salade rouge, segments d''agrumes, pomme, ananas, fruits de mer', 'Ensalada roja, gajos de cítricos, manzana, piña, marisco', 60, 'images/babouche-aux-fruits-de-mer.jpg'),
  (c_starters, 6, 'Avocado tartar with quinoa', 'Tartar d''avocat au quinoa', 'Tartar de aguacate con quinoa', 'Avocado, tomato, onions, cucumber, pepper', 'Avocat, tomate, oignons, concombre, poivron', 'Aguacate, tomate, cebolla, pepino, pimiento', 55, 'images/tartar-d-avocat-au-quinoa.jpg'),
  (c_starters, 7, 'Harira soup', 'Soupe Harira', 'Sopa Harira', null, null, null, 30, 'images/soupe-harira.jpg'),
  (c_starters, 8, 'Pastilla with chicken and almonds', 'Pastilla au poulet et aux amandes', 'Pastilla de pollo y almendras', null, null, null, 60, 'images/pastilla-au-poulet-et-aux-amandes.jpg');

  -- MAIN DISHES
  insert into public.menu_items (category_id, sort_order, name_en, name_fr, name_es, desc_en, desc_fr, desc_es, price, image_url) values
  (c_mains, 1, 'Kebab Kefta', 'Kebab Kefta', 'Kebab Kefta', 'Rice, sauteed vegetables, fries', 'Riz, légumes sautés, frites', 'Arroz, verduras salteadas, patatas fritas', 85, 'images/kebab-kefta.jpg'),
  (c_mains, 2, 'Chicken Kabab', 'Poulet Kabab', 'Kebab de Pollo', 'Rice, sauteed vegetables, fries', 'Riz, légumes sautés, frites', 'Arroz, verduras salteadas, patatas fritas', 85, 'images/poulet-kabab.jpg'),
  (c_mains, 3, 'Falafel', 'Falafel', 'Falafel', 'Green salad, hummus, babaghanouch, tarator sauce', 'Salade verte, hommus, babaghanouch, sauce tarator', 'Ensalada verde, hummus, babaganush, salsa tarator', 75, 'images/falafel.jpg'),
  (c_mains, 4, 'Fattat badinjan', 'Fatte badinjan', 'Fatteh de berenjena', 'Aubergine, minced meat, bolognese sauce, laban, Lebanese crouton', 'Aubergine, viande hachée, sauce bolognaise, laban, crouton libanais', 'Berenjena, carne picada, salsa boloñesa, laban, picatostes libaneses', 75, 'images/fatte-badinjan.jpg'),
  (c_mains, 5, 'Chicken with cream & mushrooms', 'Poulet à la crème et aux champignons', 'Pollo a la crema y champiñones', 'Minced chicken with cream and mushrooms served with fries', 'Poulet émincé avec crème et champignons servi avec frites', 'Pollo desmenuzado con crema y champiñones servido con patatas fritas', 75, 'images/poulet-a-la-creme-et-aux-champignons.jpg');

  -- COUSCOUS
  insert into public.menu_items (category_id, sort_order, name_en, name_fr, name_es, desc_en, desc_fr, desc_es, price, image_url) values
  (c_couscous, 1, 'Chicken Couscous (7 Vegetables)', 'Couscous Poulet & 7 Légumes', 'Cuscús de Pollo (7 Verduras)', 'Couscous with chicken, seven vegetables and tfaya caramelized onions', 'Poulet, sept légumes et oignons caramélisés tfaya', 'Cuscús con pollo, 7 verduras y cebollas caramelizadas tfaya', 85, 'images/couscous-poulet-and-7-legumes.jpg'),
  (c_couscous, 2, 'Beef Couscous (7 Vegetables)', 'Couscous Bœuf & 7 Légumes', 'Cuscús de Ternera (7 Verduras)', 'Couscous with beef, vegetables and tfaya caramelized onions', 'Bœuf, légumes et oignons caramélisés tfaya', 'Cuscús con ternera, verduras y cebollas caramelizadas tfaya', 85, 'images/couscous-boeuf-and-7-legumes.jpg'),
  (c_couscous, 3, 'Royal Couscous', 'Couscous Royal', 'Cuscús Real', 'Royal couscous of vegetables, chicken and beef, and tfaya caramelized onions', 'Couscous royal aux légumes, poulet, bœuf et oignons caramélisés tfaya', 'Cuscús real de verduras, pollo, ternera y cebollas caramelizadas tfaya', 90, 'images/couscous-royal.jpg'),
  (c_couscous, 4, 'Vegetable Couscous', 'Couscous 7 Légumes', 'Cuscús de 7 Verduras', 'Couscous with 7 vegetables and tfaya caramelized onions', 'Sept légumes et oignons caramélisés tfaya', 'Cuscús con 7 verduras y cebollas caramelizadas tfaya', 75, 'images/couscous-7-legumes.jpg');

  -- TAJINES
  insert into public.menu_items (category_id, sort_order, name_en, name_fr, name_es, desc_en, desc_fr, desc_es, price, image_url) values
  (c_tajines, 1, 'Berber Vegetable Tagine', 'Tajine berbère de légumes', 'Tajine bereber de verduras', 'Berber Tagine of vegetables', 'Tajine berbère aux légumes de saison', 'Tajine tradicional bereber de verduras', 60, 'images/tajine-berbere-de-legumes.jpg'),
  (c_tajines, 2, 'Kefta Tagine with Eggs', 'Tajine de kefta aux œufs', 'Tajine de kefta con huevos', 'Tagine of kefta with eggs, fresh tomato, and fries', 'Kefta avec œufs, tomates fraîches et frites', 'Tajine de kefta con huevos, tomate fresco y patatas fritas', 75, 'images/tajine-de-kefta-aux-oeufs.jpg'),
  (c_tajines, 3, 'Beef Tagine with Prunes', 'Tajine de bœuf aux pruneaux', 'Tajine de ternera con ciruelas', 'Beef tagine with prunes and almonds', 'Bœuf mijoté aux pruneaux et amandes', 'Tajine de ternera con ciruelas pasas y almendras', 85, 'images/tajine-de-boeuf-aux-pruneaux.jpg'),
  (c_tajines, 4, 'Seafood & Fish Tagine', 'Tajine poisson et fruits de mer', 'Tajine de pescado y mariscos', 'Fish tagine with seafood and pepper farandoles', 'Poisson avec fruits de mer et farandole de poivrons', 'Tajine de pescado con mariscos y pimientos variados', 80, 'images/tajine-poisson-et-fruits-de-mer.jpg'),
  (c_tajines, 5, 'Chicken Tagine with Lemon', 'Tajine de poulet au citron et olives', 'Tajine de pollo con limón y aceitunas', 'Chicken tagine with lemon and olives and fries', 'Poulet au citron confit, olives et frites', 'Tajine de pollo con limón encurtido, aceitunas y patatas fritas', 80, 'images/tajine-de-poulet-au-citron-et-olives.jpg'),
  (c_tajines, 6, 'Camel Meat Tanjia', 'Tanjia de viande de chameau', 'Tanjia de carne de camello', 'Traditional Tanjia of camel meat', 'Tanjia marocaine traditionnelle à la viande de chameau', 'Tanjia marroquí tradicional de carne de camello', 120, 'images/tanjia-de-viande-de-chameau.jpg');

  -- FAST FOOD
  insert into public.menu_items (category_id, sort_order, name_en, name_fr, name_es, desc_en, desc_fr, desc_es, price, image_url) values
  (c_fastfood, 1, 'Chicken & Cheese Quesadilla', 'Quesadilla au poulet et fromage', 'Quesadilla de pollo y queso', 'Quesadilla of chicken and cheese served with fries', 'Quesadilla poulet et fromage servie avec frites', 'Quesadilla de pollo y queso servida con patatas fritas', 70, 'images/quesadilla-au-poulet-et-fromage.jpg'),
  (c_fastfood, 2, 'Falafel Sandwich', 'Sandwich Falafel', 'Sándwich de Falafel', 'Falafel sandwich with hummus and fries', 'Sandwich falafel avec houmous et frites', 'Sándwich de falafel con hummus y patatas fritas', 65, 'images/sandwich-falafel.jpg'),
  (c_fastfood, 3, 'Cheeseburger', 'Cheeseburger', 'Hamburguesa con queso', 'Cheeseburger with tomato, salad, pickle, cheddar, served with fries', 'Cheeseburger avec tomate, salade, cornichon, cheddar et frites', 'Cheeseburger con tomate, ensalada, pepinillo, cheddar y patatas fritas', 60, 'images/cheeseburger.jpg'),
  (c_fastfood, 4, 'Crunchy Chicken Burger', 'Crunchy burger de poulet', 'Hamburguesa de pollo crujiente', 'Chicken Crunchy burger served with fries', 'Burger de poulet croustillant servi avec frites', 'Hamburguesa de pollo crujiente servida con patatas fritas', 60, 'images/crunchy-burger-de-poulet.jpg'),
  (c_fastfood, 5, 'Grilled Chicken Sandwich', 'Sandwich poulet grillé', 'Sándwich de pollo a la plancha', 'Grilled chicken sandwich served with fries', 'Sandwich au poulet grillé servi avec frites', 'Sándwich de pollo a la plancha servido con patatas fritas', 60, 'images/sandwich-poulet-grille.jpg'),
  (c_fastfood, 6, 'Grilled Kofta Sandwich', 'Sandwich Kofta grillé', 'Sándwich de Kofta a la plancha', 'Grilled kofta sandwich served with fries', 'Sandwich à la kefta grillée servi avec frites', 'Sándwich de kofta a la plancha servido con patatas fritas', 60, 'images/sandwich-kofta-grille.jpg');

  -- PIZZA
  insert into public.menu_items (category_id, sort_order, name_en, name_fr, name_es, desc_en, desc_fr, desc_es, price, image_url) values
  (c_pizza, 1, 'Margarita Pizza', 'Pizza Margarita', 'Pizza Margarita', 'Tomato sauce, mozzarella, black olives', 'Sauce tomate, mozzarella, olives noires', 'Salsa de tomate, mozzarella, aceitunas negras', 50, 'images/pizza-margarita.jpg'),
  (c_pizza, 2, 'Veggie Pizza', 'Pizza Veggie', 'Pizza Vegetariana', 'Tomato sauce, zucchini, eggplant, onions, olives, mozzarella', 'Sauce tomate, courgettes, aubergines, oignons, olives, mozzarella', 'Salsa de tomate, calabacín, berenjena, cebolla, aceitunas, mozzarella', 60, 'images/pizza-veggie.jpg'),
  (c_pizza, 3, 'Sicilian Pizza', 'Pizza Sicilienne', 'Pizza Siciliana', 'Tomato sauce, tuna, pepper, olive, mozzarella', 'Sauce tomate, thon, poivron, olive, mozzarella', 'Salsa de tomate, atún, pimiento, aceituna, mozzarella', 60, 'images/pizza-sicilienne.jpg'),
  (c_pizza, 4, 'Royal Chicken Pizza', 'Pizza Royal Chicken', 'Pizza Royal Chicken', 'Tomato sauce, mozzarella, chicken breast, olives, cherry tomato, onions', 'Sauce tomate, mozzarella, blanc de poulet, olives, tomate cerise, oignons', 'Salsa de tomate, mozzarella, pechuga de pollo, aceitunas, tomate cherry, cebolla', 60, 'images/pizza-royal-chicken.jpg'),
  (c_pizza, 5, '4 Cheese Pizza', 'Pizza 4 Fromages', 'Pizza 4 Quesos', 'Mozzarella, red, blue, goat cheese', 'Mozzarella, rouge, bleu, chèvre', 'Mozzarella, queso rojo, azul, de cabra', 60, 'images/pizza-4-fromages.jpg');

  -- DESSERTS
  insert into public.menu_items (category_id, sort_order, name_en, name_fr, name_es, desc_en, desc_fr, desc_es, price, image_url) values
  (c_desserts, 1, 'Cinnamon Orange', 'Orange à la cannelle', 'Naranja a la canela', 'Fresh orange slices with cinnamon', 'Tranches d''orange fraîche à la cannelle', 'Rodajas de naranja fresca espolvoreadas con canela', 30, 'images/orange-a-la-cannelle.jpg'),
  (c_desserts, 2, 'Fresh Fruit Salad', 'Salade de fruits frais', 'Ensalada de frutas frescas', 'Assorted fresh seasonal fruits', 'Fruits frais de saison', 'Surtido de frutas frescas de temporada', 35, 'images/salade-de-fruits-frais.jpg'),
  (c_desserts, 3, 'Nutella Crepe', 'Crêpe Nutella', 'Crepe de Nutella', 'Sweet crepe with Nutella', 'Crêpe gourmande au Nutella', 'Crepe dulce rellena de Nutella', 30, 'images/crepe-nutella.jpg'),
  (c_desserts, 4, 'Nutella Banana & Ice Cream Crepe', 'Crêpe Nutella banane et boule de glace vanille', 'Crepe de Nutella, plátano y helado', 'Nutella banana crepe with vanilla ice cream', 'Crêpe Nutella et banane servie avec une boule de glace vanille', 'Crepe de Nutella y plátano servida con una bola de helado de vainilla', 50, 'images/crepe-nutella-banane-et-boule-de-glace-vanille.jpg'),
  (c_desserts, 5, 'Gazelle Horns (3 pcs)', 'Corne de gazelle (3 pièces)', 'Cuernos de gazela (3 ud)', 'Traditional almond paste pastries', 'Pâtisserie marocaine traditionnelle aux amandes', 'Dulce tradicional marroquí relleno de almendra', 35, 'images/corne-de-gazelle-3-pieces.jpg'),
  (c_desserts, 6, 'Pastilla Style Tiramisu', 'Tiramisu façon pastilla', 'Tiramisú estilo pastilla', 'Crispy pastilla layers with tiramisu cream', 'Feuilles de pastilla croustillantes à la crème tiramisu', 'Capas crujientes de pastilla con crema de tiramisú', 45, 'images/tiramisu-facon-pastilla.jpg');

  -- HOT DRINKS
  insert into public.menu_items (category_id, sort_order, name_en, name_fr, name_es, desc_en, desc_fr, desc_es, price, image_url) values
  (c_hotdrinks, 1, 'Black Coffee', 'Café noir', 'Café solo', 'Espresso or black coffee', 'Espresso ou café noir', 'Café espresso o negro', 17, 'images/cafe-noir.jpg'),
  (c_hotdrinks, 2, 'American Coffee', 'Café américain', 'Café americano', 'Americano', 'Café allongé', 'Café largo estilo americano', 20, 'images/cafe-americain.jpg'),
  (c_hotdrinks, 3, 'Coffee with Milk', 'Café au lait', 'Café con leche', 'Café au lait', 'Café au lait chaud', 'Café con leche caliente', 20, 'images/cafe-au-lait.jpg'),
  (c_hotdrinks, 4, 'Moroccan Mint Tea', 'Thé marocain', 'Té marroquí', 'Traditional green tea with mint', 'Thé vert traditionnel à la menthe', 'Té verde tradicional con menta fresca', 19, 'images/the-marocain.jpg'),
  (c_hotdrinks, 5, 'Hot Chocolate', 'Chocolat chaud', 'Chocolate caliente', 'Creamy hot cocoa', 'Chocolat chaud crémeux', 'Chocolate caliente cremoso', 20, 'images/chocolat-chaud.jpg'),
  (c_hotdrinks, 6, 'Lipton Tea', 'Lipton', 'Té Lipton', 'Black tea bag', 'Thé noir Lipton', 'Té negro en bolsita', 20, 'images/lipton.jpg'),
  (c_hotdrinks, 7, 'Verbena Tea', 'Verveine', 'María Luisa (Luisa)', 'Herbal verbena infusion', 'Infusion de verveine', 'Infusión natural de yerbaluisa', 20, 'images/verveine.jpg');

  -- COLD DRINKS
  insert into public.menu_items (category_id, sort_order, name_en, name_fr, name_es, desc_en, desc_fr, desc_es, price, image_url) values
  (c_colddrinks, 1, 'San Miguel 0.0', 'San Miguel 0.0', 'San Miguel 0.0', 'Non-alcoholic beer', 'Bière sans alcool', 'Cerveza sin alcohol', 35, 'images/san-miguel-0-0.jpg'),
  (c_colddrinks, 2, 'Soda', 'Soda', 'Refresco', 'Coca-Cola, Coca Zero, Sprite, Schweppes Lemon', 'Coca, Coca Zero, Sprite, Schweppes citron', 'Coca-Cola, Coca Zero, Sprite, Schweppes Limón', 20, 'images/soda.jpg'),
  (c_colddrinks, 3, 'Small Water', 'Petite bouteille d''eau', 'Agua pequeña', 'Still water (0.5L)', 'Eau minérale plate (0.5L)', 'Agua mineral natural (0.5L)', 10, 'images/petite-bouteille-d-eau.jpg'),
  (c_colddrinks, 4, 'Large Water', 'Grande bouteille d''eau', 'Agua grande', 'Still water (1.5L)', 'Eau minérale plate (1.5L)', 'Agua mineral natural (1.5L)', 15, 'images/grande-bouteille-d-eau.jpg'),
  (c_colddrinks, 5, 'Small Sparkling Water', 'Eau pétillante', 'Agua con gas pequeña', 'Sparkling water (0.5L)', 'Eau gazeuse (0.5L)', 'Agua con gas (0.5L)', 15, 'images/eau-petillante.jpg'),
  (c_colddrinks, 6, 'Large Sparkling Water', 'Eau pétillante grand', 'Agua con gas grande', 'Sparkling water (1L)', 'Eau gazeuse (1L)', 'Agua con gas (1L)', 25, 'images/eau-petillante-grand.jpg');

  -- JUICES
  insert into public.menu_items (category_id, sort_order, name_en, name_fr, name_es, desc_en, desc_fr, desc_es, price, image_url) values
  (c_juices, 1, 'Fresh Juice', 'Jus frais', 'Zumo natural', 'Orange, Carrot, Banana, Apple, or Pineapple', 'Orange, Carotte, Banane, Pomme, Ananas', 'Naranja, Zanahoria, Plátano, Manzana o Piña', 25, 'images/jus-frais.jpg'),
  (c_juices, 2, 'Avocado Juice', 'Jus d''avocat', 'Zumo de aguacate', 'Fresh avocado smoothie', 'Onctueux jus d''avocat frais', 'Batido cremoso de aguacate fresco', 30, 'images/jus-d-avocat.jpg'),
  (c_juices, 3, 'Mixed Juice', 'Jus mixte', 'Zumo mixto', 'Blended fruit mix', 'Melange de fruits de saison', 'Mezcla de frutas variadas', 30, 'images/jus-mixte.jpg'),
  (c_juices, 4, 'Mojito', 'Mojito', 'Mojito', 'Refreshing mint & lime drink', 'Boisson rafraîchissante à la menthe et citron vert', 'Bebida refrescante de menta y lima', 25, 'images/mojito.jpg');

end $$;


-- ============================================================
-- ONE-TIME REPAIR FOR EXISTING PROJECTS
-- If you already ran an older version of this script and the
-- admin/menu shows 403 errors, run this block in SQL Editor.
-- ============================================================
grant select on public.settings, public.categories, public.menu_items to anon;
grant select, insert, update, delete on public.settings, public.categories, public.menu_items to authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;


-- ============================================================
-- ADMIN AUTHORIZATION
-- After creating the admin user in Authentication → Users, run: 
-- update auth.users
-- set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"owner"}'::jsonb
-- where email = 'YOUR-ADMIN-EMAIL';
-- Then sign out/in so the new JWT contains app_metadata.role=owner.
-- New staff accounts created from the Admin Panel receive role=admin automatically.
-- Never use user_metadata for this role check.
-- ============================================================
