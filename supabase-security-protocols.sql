-- ============================================================
-- BABOUCHE — Security protocols: input bounds + rate limiting
-- Run this once in Supabase → SQL Editor, after supabase-menu-setup.sql.
-- Safe to re-run.
--
-- This file covers the two protections that only make sense to enforce
-- in the database (not just in the browser), since the Data API
-- (PostgREST) and the manage-admin Edge Function are the real "backend"
-- for this project:
--   1) CHECK constraints — a hard backstop on every write, even one that
--      didn't go through admin.html's own client-side validation
--      (a modified request, a future integration, a browser bug, etc).
--   2) A small rate-limit table + function, called from the
--      manage-admin Edge Function before it does anything sensitive.
-- ============================================================

-- 1) INPUT BOUNDS — reject absurd/empty values at the database level,
--    regardless of what the client sent.
alter table public.categories drop constraint if exists categories_name_len_chk;
alter table public.categories add constraint categories_name_len_chk
  check (
    char_length(trim(name_en)) between 1 and 120 and
    char_length(trim(name_fr)) between 1 and 120 and
    char_length(trim(name_es)) between 1 and 120
  );

alter table public.categories drop constraint if exists categories_slug_chk;
alter table public.categories add constraint categories_slug_chk
  check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 80);

alter table public.menu_items drop constraint if exists menu_items_name_len_chk;
alter table public.menu_items add constraint menu_items_name_len_chk
  check (
    char_length(trim(name_en)) between 1 and 150 and
    char_length(trim(name_fr)) between 1 and 150 and
    char_length(trim(name_es)) between 1 and 150
  );

alter table public.menu_items drop constraint if exists menu_items_desc_len_chk;
alter table public.menu_items add constraint menu_items_desc_len_chk
  check (
    coalesce(char_length(desc_en), 0) <= 800 and
    coalesce(char_length(desc_fr), 0) <= 800 and
    coalesce(char_length(desc_es), 0) <= 800
  );

alter table public.menu_items drop constraint if exists menu_items_price_chk;
alter table public.menu_items add constraint menu_items_price_chk
  check (price >= 0 and price <= 100000);

alter table public.menu_items drop constraint if exists menu_items_image_url_chk;
alter table public.menu_items add constraint menu_items_image_url_chk
  -- Item photos can be a full https URL (Supabase Storage uploads) OR a
  -- relative path like images/dish.jpg (the site's own bundled photos —
  -- this project's original seed data uses these). Only truly dangerous
  -- schemes are blocked; this is a blocklist, not an allowlist, on
  -- purpose, since relative/absolute paths are legitimate here.
  check (image_url is null or (
    char_length(image_url) <= 2048
    and image_url !~* '^\s*(javascript|data|vbscript|file)\s*:'
  ));

alter table public.settings drop constraint if exists settings_value_len_chk;
alter table public.settings add constraint settings_value_len_chk
  check (value is null or char_length(value) <= 2048);

-- 2) RATE LIMITING — used by the manage-admin Edge Function.
--    Not reachable from the browser: no grants to anon/authenticated,
--    RLS enabled with zero policies, and the function is only callable
--    with the service_role key (which only ever lives in the Edge
--    Function's server-side environment, never in the frontend).
create table if not exists public.rate_limits (
  bucket_key   text primary key,
  count        integer not null default 0,
  window_start timestamptz not null default now()
);

alter table public.rate_limits enable row level security;
-- Intentionally no policies: RLS with zero policies denies all access to
-- anon/authenticated. Only service_role (which bypasses RLS entirely) —
-- i.e. only the Edge Function — can touch this table.
revoke all on public.rate_limits from anon, authenticated;

create or replace function public.check_rate_limit(
  p_key text,
  p_max_requests integer,
  p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  insert into public.rate_limits (bucket_key, count, window_start)
  values (p_key, 1, now())
  on conflict (bucket_key) do update
    set count = case
          when public.rate_limits.window_start < now() - make_interval(secs => p_window_seconds)
            then 1
          else public.rate_limits.count + 1
        end,
        window_start = case
          when public.rate_limits.window_start < now() - make_interval(secs => p_window_seconds)
            then now()
          else public.rate_limits.window_start
        end
  returning count into v_count;

  return v_count <= p_max_requests;
end;
$$;

-- Only service_role (the Edge Function) may call this — never exposed
-- over the public Data API to anon/authenticated.
revoke all on function public.check_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.check_rate_limit(text, integer, integer) to service_role;

-- Optional housekeeping: old buckets are tiny and self-correcting (they
-- just reset on next use), but you can periodically clear stale rows,
-- e.g. via the Supabase Dashboard's SQL editor or a scheduled job:
-- delete from public.rate_limits where window_start < now() - interval '1 day';
