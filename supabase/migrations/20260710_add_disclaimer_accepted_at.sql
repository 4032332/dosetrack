-- Records when a user accepted the medical disclaimer / terms of use.
-- The DoseTrack app reads and writes this column via a targeted upsert on user_settings
-- (see SupabaseSyncManager.hasAcceptedDisclaimer / recordDisclaimerAcceptance). Until this
-- migration is applied the app degrades gracefully — acceptance is still recorded locally on the
-- device, so no user is blocked; the server record simply won't persist.

alter table public.user_settings
    add column if not exists disclaimer_accepted_at timestamptz;
