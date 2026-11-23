# Shared Trip Budget & Expenses

## Product and design
Build a working, mobile-first travel finance app, provisionally named **TripTogether**, rather than disconnected sample screens. Use a soft gray canvas, white surfaces, restrained navy typography, emerald financial accents, and destination photography. Home, My Trips, Activity, and Profile share consistent navigation, with bottom navigation on phones.

User profiles are confirmed: include full name, email, photo, and financial summaries derived from recorded transactions.

## Delivery phases
1. **Foundation:** Connect Lovable Cloud; enable email/password and Google sign-in; implement confirmation-aware signup, password recovery, profiles, and private trip access.
2. **Trips:** Create trips with dates, destination, budget, INR-default currency, description, and optional cover. Add member management and secure join-by-link/code flows.
3. **Expenses:** Implement personal, equal, custom, on-behalf-of, and multiple-contributor expenses with receipts, category, date, descriptions, and explicit beneficiaries.
4. **Ledger and settlements:** Add searchable/filterable history, member financial details, partial settlement recording, settlement history, and suggested group transfers.
5. **Offline reliability:** Persist authorized trip snapshots and pending expenses locally, synchronize safely on reconnect and app open, and expose pending/failed/synced states.
6. **Finishing:** Personal cross-trip summaries, budget/category/member charts, realtime updates, installability, phone layouts, and end-to-end checks.

## Financial rules
- Store and calculate integer minor units (paise for INR), never floating-point money.
- Contributions and beneficiary shares must each equal the expense total; validate membership and totals atomically in the database.
- Equal splits distribute leftover paise deterministically using stable member ordering.
- Balance before settlements = contributions − allocated personal spending. Positive means receivable; negative means payable.
- A settlement increases the sender’s balance toward zero and decreases the recipient’s balance toward zero. Preserve original expenses.
- Synchronized group balances sum to zero. Reject invalid or duplicate financial operations.
- Financial records are immutable; corrections use linked reversals/adjustments.
- Suggest deterministic reduced transfers; do not claim a globally minimum transfer count unless verified by an exact algorithm.

## Invitations and email
Invite existing or new users by email, shareable link, or code. Email-specific invitations require a matching verified signed-in email; login alone never creates membership. Preserve invitations across Google login. Support pending, accepted, expired, revoked, resend, and duplicate-active-invitation prevention.

Use Lovable Emails with a professional invitation template and a secure Join Trip button. Sending requires a domain you own; domain setup is a user prerequisite, not a reason to block other app features. Each invitation sends to one explicit recipient, without mailing-list or campaign behavior. No bank/UPI processing is included.

## Technical design
### Application architecture
Keep the existing React/TypeScript, TanStack Start, Tailwind, and shadcn stack. Use Lovable Cloud for PostgreSQL, authentication, realtime, and storage. App-internal server functions perform authenticated operations; PostgreSQL functions handle atomic financial validation. Do not introduce Supabase Edge Functions or replace the application’s hosting framework. Vercel deployment is not part of this workspace’s native publish flow.

### Schema and relationships
- `profiles`: one-to-one with auth users, created on signup; no roles stored here.
- `trips`: owner, destination, dates, budget, currency, description, cover reference.
- `trip_members`: unique user/trip membership and status.
- `trip_member_roles`: separate trip-scoped creator/administrator/participant permissions.
- `trip_invitations`: trip, inviter, normalized recipient, hashed token/code, expiry, status; unique active email/trip invitation.
- `expense_categories`: canonical categories.
- `expenses`: immutable trip transaction header, integer amount, category, timestamp, creator, idempotency UUID, optional correction reference and receipt.
- `expense_contributions` and `expense_splits`: expense-to-member paid amounts and beneficiary allocations.
- `settlements` and `settlement_allocations`: immutable payer-to-recipient transfers and optional allocation detail.
- `sync_operations`: per-user operation identifiers/results for deduplication and audit, not an email queue.

Every public table gets explicit grants followed by RLS. Membership-based policies protect trips and all financial rows. Database helpers avoid recursive membership policies. Ordinary reads run as the signed-in user; privileged invitation verification exposes no private data before authorization. Store invitation hashes only; suppress tokens from logs. Receipts remain private and member-scoped.

### Offline architecture
Use IndexedDB through a maintained wrapper for per-user trip snapshots and persistent operation queues. Generate expense UUIDs before saving; show optimistic rows labeled pending, never final confirmed balances. Synchronize via the same authenticated atomic operation used online. Replays return the existing result. Retry transient failures; keep validation failures visible for correction, never discard queued entries. Separate local data by identity and clear private snapshots on sign-out; warn before deleting unsent operations.

Generate the app-shell service worker with `vite-plugin-pwa`, network-first navigation and hashed-asset caching. Register only on the published app, never preview/development, with the platform’s preview guards and kill switch. Foreground synchronization is required; background sync is optional. Offline access requires a prior successful online sign-in and cached trip.

## Verification and completion
Add concrete tests for the specified expense scenarios, custom totals, multiple contributions, paise remainders, settlement signs, zero-sum balances, and idempotency. Check unauthorized trip access, invitation email matching, expiry/revocation, and immutable records. Exercise real create-trip → expense → ledger → settlement flows and offline expense replay, plus desktop/phone layouts. Verify email delivery only after sender-domain verification; published offline behavior needs a published-app check.