-- Widen medications.current_count from integer to numeric so supply can be tracked
-- in half-unit increments (e.g. half tablets). Existing whole-number values are
-- preserved exactly by the ::numeric cast.
ALTER TABLE public.medications
  ALTER COLUMN current_count TYPE numeric USING current_count::numeric,
  ALTER COLUMN current_count SET DEFAULT 0;
