# TripTogether

Shared trip budgets and group expenses with clear balances, settlements, invites and offline support.

## Features

- **Trips** – create trips with destination, dates, budget and currency (INR, USD, EUR, GBP).
- **Friends & invitations** – invite people with a secure share link or an email-specific invitation; links expire after 7 days and can be revoked.
- **Expenses** – equal or custom splits, multiple payers, categories, notes and private receipt uploads.
- **Balances & settlements** – live per-person balances, suggested transfers, and recorded payments.
- **Immutable ledger** – expenses are never edited or deleted; mistakes are corrected with linked reversals.
- **Offline support** – installable PWA; expenses added offline are queued and synced safely when you reconnect.
- **Realtime** – trip changes appear instantly for every member.
- **Sign-in** – email/password and Google.

## Tech stack

- React 19, TypeScript, TanStack Start & Router
- Tailwind CSS, shadcn/ui
- Supabase (PostgreSQL, Auth, Storage, Realtime)
- IndexedDB (`idb`) and `vite-plugin-pwa` for offline use
- Vitest for tests

## Getting started

### 1. Install

```sh
npm install
```

### 2. Configure Supabase

Create a Supabase project, then add a `.env` file in the project root:

```sh
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_PUBLISHABLE_KEY=<publishable-key>
SUPABASE_PROJECT_ID=<project-ref>
VITE_SUPABASE_URL=https://<project-ref>.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=<publishable-key>
VITE_SUPABASE_PROJECT_ID=<project-ref>
```

Never commit `.env`.

### 3. Create the database

Run `supabase/schema.sql` in the Supabase SQL Editor, or with the CLI:

```sh
supabase link --project-ref <project-ref>
supabase db query --remote -f supabase/schema.sql
```

### 4. Auth settings

In Supabase → Authentication:

- **URL Configuration** – add `http://localhost:8080/**` (and your production domain) to Redirect URLs.
- **Providers → Google** – enable it and add your Google OAuth client ID and secret.

### 5. Run

```sh
npm run dev      # http://localhost:8080
npm test         # run tests
npm run build    # production build
```

## How money is handled

- All amounts are stored as integers in minor units (e.g. paise, cents) — never floating point.
- Payments and shares must each add up to the expense total; this is validated in the database.
- Equal splits distribute leftover units deterministically.
- Group balances always sum to zero.

## Developer

Developed by **Praduman Kathade**.
