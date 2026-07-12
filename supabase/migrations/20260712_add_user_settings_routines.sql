-- Adds the Daily Routine Times "routines" column to user_settings.
--
-- Routines replace the fixed set of per-meal columns (meal_breakfast_hour, meal_lunch_hour, …)
-- with a user-defined, ordered list of named times ({ id, name, hour, minute, anchor }). The app
-- writes the authoritative list here as a JSON string; the legacy per-meal columns are kept in
-- place (populated best-effort from this list) so any client that predates this column keeps
-- working. They can be dropped in a later housekeeping migration once every client reads `routines`.
--
-- The app degrades gracefully if this migration hasn't been applied: routine changes then persist
-- locally only (same as the disclaimer/routine_label migrations before it).

ALTER TABLE public.user_settings
    ADD COLUMN IF NOT EXISTS routines text;

COMMENT ON COLUMN public.user_settings.routines IS
    'JSON-encoded RoutineStore (Daily Routine Times). Supersedes the meal_* columns.';
