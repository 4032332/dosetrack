-- Tracks redemptions of shared (non-unique) promo codes that grant a temporary DoseTrack Plus
-- entitlement — e.g. a code bundled with a physical product that unlocks 1 free month of Plus.
--
-- The app enforces "once per account, ever" by inserting a row per (user_id, code) redemption;
-- the unique constraint below makes a second redemption attempt fail atomically at the database,
-- so the check can't be bypassed by racing requests or a client that lies about having already
-- redeemed. Unlike the disclaimer/scan-count columns on user_settings, this is its own table
-- since it's a log of discrete events (potentially multiple different promo codes over time) with
-- an interesting shape (redeemed_at, expires_at) per code, not a single mutable column.
--
-- Degrades gracefully if unapplied: SupabaseSyncManager.redeemPromoCode returns a network-error
-- result, and the app shows a generic "couldn't redeem right now" message rather than granting
-- access it can't actually enforce server-side.

create table if not exists public.promo_redemptions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    code text not null,
    redeemed_at timestamptz not null default now(),
    expires_at timestamptz not null,
    unique (user_id, code)
);

comment on table public.promo_redemptions is
    'One row per (account, promo code) redemption. The unique constraint enforces one-time use of a given code per account.';

alter table public.promo_redemptions enable row level security;

-- A signed-in user may only see and create their own redemption rows. There is no update/delete
-- policy — redemptions are immutable once created, matching the "permanently one-time" design.
create policy "Users can view their own promo redemptions"
    on public.promo_redemptions for select
    using (auth.uid() = user_id);

create policy "Users can insert their own promo redemptions"
    on public.promo_redemptions for insert
    with check (auth.uid() = user_id);
