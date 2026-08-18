# iLiNuX Marketplace — Setup Guide

This is the first working version of the marketplace: sign up, browse
listings, submit items for sale, and an admin page for you to approve
sellers and listings before anything goes public.

## What's built

- `auth.html` — sign up / sign in (email + password)
- `marketplace.html` — public browse page with search + category filters
- `listing.html` — single listing page, buyer messages seller on WhatsApp to arrange purchase
- `sell.html` — logged-in users request seller status and submit listings
- `dashboard.html` — seller sees their own listings and approval status
- `admin.html` — you review and approve/reject pending sellers and listings
- `marketplace-style.css` — dark theme with neon-green accents, matching the existing site
- `supabase-config.js` — shared connection settings and helper functions
- `supabase-schema.sql` — database setup script (run once)

## Why WhatsApp-to-buy instead of in-app checkout, for now

Building real in-app payment (MoMo via Paystack/Flutterwave) needs a small
server component to securely verify payments and split money between you
and sellers — that's a bigger piece of work. For version 1, buyers message
the seller directly on WhatsApp to arrange payment, the same way your
current site already works. This gets the marketplace live and testable
now; in-app checkout can be added as a phase 2 once listings and sellers
are flowing.

## Setup steps

### 1. Create a free Supabase project
Go to supabase.com, sign up, create a new project (pick a region close to
Ghana, e.g. Europe). Save the database password somewhere safe.

### 2. Run the database schema
In your Supabase project: **SQL Editor → New query**, paste the entire
contents of `supabase-schema.sql`, and click **Run**.

### 3. Connect the site to your project
In Supabase: **Settings → API**. Copy your **Project URL** and **anon
public** key. Open `supabase-config.js` and replace:
```
const SUPABASE_URL = 'YOUR_SUPABASE_PROJECT_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

### 4. Push these files to your GitHub repo
Add all these files to the root of `linux7788.github.io` (same place as
your existing `index.html`), commit, and push. They'll be live at
`https://linux7788.github.io/marketplace.html` within a minute or two.

### 5. Make yourself admin
Visit `auth.html` on your live site and create your own account. Then in
Supabase: **Table Editor → profiles**, find your row, and change `role`
from `buyer` to `admin`. Now `admin.html` will show you the approval
queue.

### 6. Link the marketplace from your homepage
Add a nav link in your existing `index.html` pointing to
`marketplace.html`, e.g. in the `<nav id="main-nav">` section:
```html
<a href="marketplace.html">Marketplace</a>
```

## Testing it end to end
1. Create a second test account (or use a different browser/incognito).
2. Go to `sell.html` — this marks you as a pending seller.
3. Log in as your admin account, go to `admin.html`, approve the seller.
4. Log back in as the test account, submit a listing on `sell.html`.
5. Approve the listing as admin.
6. Check `marketplace.html` — the listing should now appear publicly.

## What's next (your call)
- Real in-app checkout with MoMo (Paystack/Flutterwave) once you're ready
- Image uploads for listings (Supabase Storage, still free tier)
- Push notifications or email alerts when a listing is approved
