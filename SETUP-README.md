# BABOUCHE — Customer UI reverted to previous design

This build keeps the previous BABOUCHE customer-facing menu design, including the touch-friendly cart and mobile drag-and-drop admin ordering. The newer customer card layout with large inline photos has been removed.

The admin/security improvements remain included.

# BABOUCHE — Supabase setup & polished ordering flow

## Current architecture

- Customers browse a multilingual menu (English, French, Spanish — **Spanish is the default language on page load**), search it, jump between categories, open dish details, and add items with quick quantity controls.
- A sticky mini-cart lets customers review and modify quantities before WhatsApp.
- The cart supports item removal, special requests/allergies, table number, subtotal and total. **There is no 5% service charge.**
- WhatsApp receives a clean, structured order **always in English** (labels and dish names), no matter which menu language the customer was browsing in. A final confirmation is shown before opening WhatsApp.
- Cart quantities and special requests survive an accidental page refresh on the same device.
- Food images are lazy-loaded on the public menu.
- Admin categories and menu items are reordered by drag-and-drop on desktop and touch devices.
- Admin photo uploads accept JPG/PNG/WebP and optimize images in the browser to WebP (max 1600px, quality ~82%) before upload.
- The admin panel uses Supabase Auth. Database and Storage writes require an authenticated user whose Supabase Auth `app_metadata.role` is `admin` or `owner`.
- The first/primary account is `owner`; only the owner can invite or revoke other administrators from the Admin Panel.
- Invited staff, and anyone using "Forgot password?", are required to choose their own password on `admin.html` before they can reach the dashboard — they're never signed straight in from an email link without setting one.
- The footer's social icons are Instagram, TripAdvisor, and Google Maps (the old Facebook icon/link was replaced — point it at your Google Maps review link, e.g. `https://g.page/r/YOUR_PLACE_ID/review`, from **Restaurant Settings → Google Maps Review URL** in the admin panel).

## One-time setup

### 1 — Create the Supabase project

Use **Europe** (or the closest available region). Keep **Data API enabled**, **Automatically expose new tables disabled**, and **automatic RLS enabled**.

### 2 — New project: run the main SQL once

Supabase → **SQL Editor** → **New query** → paste all of `supabase-menu-setup.sql` → **Run**.

Do not repeatedly run the seed portion on an already populated project.

### 3 — Existing project: harden it without reseeding

If your tables/data already exist, use `supabase-security-hardening.sql` instead of rerunning the whole seed script.

### 4 — Create the admin account

Supabase → **Authentication → Users → Add user**. Create the owner/admin email and a strong password. Disable public sign-ups after the admin exists.

Then open SQL Editor and run this once, replacing the email:

```sql
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"owner"}'::jsonb
where email = 'YOUR-ADMIN-EMAIL';
```

Sign out and sign in again. The admin panel checks this server-issued `app_metadata` role before showing the dashboard. Do **not** use `user_metadata` for authorization. The owner can then use **Restaurant Settings → Administrators → + Add Administrator** to invite staff by email. Staff accounts receive `role=admin` automatically.

#### 5 — Deploy the secure administrator function

The browser must never use a Supabase secret/service-role key. The included Edge Function keeps that privileged key on Supabase's server side.

If you use the Supabase CLI:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy manage-admin

# Set the URL where invitation links should return. For local development:
supabase secrets set ADMIN_APP_URL=http://localhost:5500
```

The function handles the bearer token itself, so the Edge Function gateway must allow the browser preflight request (`verify_jwt = false`). The function still verifies the token and requires `app_metadata.role = owner` before performing any action. It supports three owner-only actions: list administrators, send an invitation, and revoke administrator access. Revoking access changes the user's Auth `app_metadata.role` to `user`; it does not delete their account. The owner account cannot be removed and an owner cannot remove themselves.

If the function asks for a service-role secret, set it as a Supabase Function secret, never in `index.html` or `admin.html`.

If you are testing the HTML directly from `file://`, switch to a local HTTP server. Browsers give `file://` pages an origin of `null`, and invitation redirects cannot reliably return to a `file://` page. From the folder containing `index.html` and `admin.html`, run:

```bash
python -m http.server 5500
```

Then open `http://localhost:5500/admin.html`. Also add `http://localhost:5500/**` under Supabase → Authentication → URL Configuration → Redirect URLs.

For production, set `ADMIN_APP_URL` to your real HTTPS website URL and add that admin URL to Supabase Redirect URLs.

### 6 — Storage security

The `menu-images` bucket is public-read so customers can see food photos. Upload/update/delete policies require the `admin` app_metadata role.

For an extra upload limit, Supabase Dashboard → **Storage → menu-images → Settings**: set a reasonable file-size limit (for example 5 MB) and allow image MIME types only.

#### 7 — Connect the website

In both `index.html` and `admin.html`, replace:

```js
const SUPABASE_URL = 'YOUR_SUPABASE_PROJECT_URL';
const SUPABASE_PUBLISHABLE_KEY = 'YOUR_SUPABASE_PUBLISHABLE_KEY';
```

with the **Project URL** and **Publishable key** from Supabase.

Never put the database password, `service_role`, or Supabase secret key in these HTML files. Publishable keys are designed for browser code, but RLS is what protects the underlying data.

## Security model

Public:
- `SELECT` on menu/settings only.
- No public insert/update/delete.

Admin:
- Supabase Auth session + `app_metadata.role = admin` required for menu/settings changes and image writes.
- Password changes use Supabase Auth.
- The frontend never receives a secret/service-role key.

## Customer UX

**Search → category navigation → dish detail → quick Add/quantity → sticky cart → modify → special request → table → final review → WhatsApp.**

The visual identity remains BABOUCHE: oat, spruce, lingon, gold, Fraunces + Work Sans.
