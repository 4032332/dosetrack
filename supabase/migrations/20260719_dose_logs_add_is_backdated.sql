-- Marks a dose_logs row as a correction made after the fact (e.g. changing a
-- MissedDoseSweeper-generated "missed" entry to "taken" from History), rather than logged on
-- the day it happened. Reports must never let a backdated "taken" read identically to a
-- same-day one.
ALTER TABLE public.dose_logs
  ADD COLUMN IF NOT EXISTS is_backdated boolean NOT NULL DEFAULT false;
