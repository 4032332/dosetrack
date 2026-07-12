-- Tracks the free tier's lifetime medication-scanner usage.
--
-- The scanner is a DoseTrack Plus feature; free users get 3 successful scans (a scan counts only
-- when it results in a saved medication) before it's paywalled. Storing the count on the account
-- (not just the device) stops a reinstall or a second device from resetting the allowance.
--
-- Degrades gracefully if unapplied: the count still gates locally via UserDefaults, it just won't
-- follow the user across devices/reinstalls. Same pattern as the disclaimer/routines migrations.

ALTER TABLE public.user_settings
    ADD COLUMN IF NOT EXISTS scan_count integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.user_settings.scan_count IS
    'Lifetime count of successful medication scans by this account (free-tier scanner allowance).';
