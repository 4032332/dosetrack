-- Adds cross-device sync support for three new tracked fields:
--
--  * medications.kind                    'medication' | 'vitamin' | 'supplement'
--  * medications.allows_as_needed        item can also be taken ad-hoc (PRN)
--  * medications.quantity_per_dose       units consumed per single dose
--  * dose_logs.is_as_needed              this log was an ad-hoc dose, not a scheduled one
--
-- `kind` and `is_as_needed` are the two that carry real weight: together they decide what counts
-- toward the adherence percentage. A missed vitamin must never read as a missed prescription, and
-- an as-needed dose can never be "missed" at all — so counting it as taken would only ever inflate
-- the score. Getting these wrong on one device would make that device disagree with another about
-- the same patient's adherence, which is why they sync rather than staying local.
--
-- `quantity_per_dose` defaults to 0 as an "unset" sentinel, matching the CoreData model: the client
-- falls back to its legacy derivation (total_doses_per_day ÷ enabled schedule count) when it reads
-- 0, so existing rows keep their current supply maths untouched.
--
-- Degrades gracefully if unapplied: the app keeps all four values locally and simply won't sync
-- them across devices. Same pattern as the disclaimer / routines / scan_count migrations.

ALTER TABLE public.medications
    ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'medication',
    ADD COLUMN IF NOT EXISTS allows_as_needed boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS quantity_per_dose double precision NOT NULL DEFAULT 0;

-- Guards against a typo'd client ever writing a kind the app can't interpret. The app itself falls
-- back to 'medication' for unrecognised values (the conservative default — an unknown item stays in
-- the adherence score rather than silently dropping out), but rejecting bad writes at the database
-- keeps that fallback from being load-bearing.
ALTER TABLE public.medications
    DROP CONSTRAINT IF EXISTS medications_kind_check;
ALTER TABLE public.medications
    ADD CONSTRAINT medications_kind_check
    CHECK (kind IN ('medication', 'vitamin', 'supplement'));

ALTER TABLE public.dose_logs
    ADD COLUMN IF NOT EXISTS is_as_needed boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.medications.kind IS
    'medication | vitamin | supplement. Only ''medication'' counts toward the headline adherence score.';
COMMENT ON COLUMN public.medications.allows_as_needed IS
    'True if this item can be taken ad-hoc (PRN). Independent of schedules — an item can be scheduled, as-needed, or both.';
COMMENT ON COLUMN public.medications.quantity_per_dose IS
    'Units consumed per single dose. 0 means unset; the client then derives it from total_doses_per_day.';
COMMENT ON COLUMN public.dose_logs.is_as_needed IS
    'True for an ad-hoc dose the user logged themselves. Excluded from adherence on both sides of the ratio.';
