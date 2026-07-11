-- Records which Daily Routine Time (e.g. "Bedtime", "Wake Up") a schedule was linked to, if any.
-- Read/written via SupabaseSyncManager's ScheduleRow (routine_label). Until this migration is
-- applied the column simply won't round-trip through Supabase — schedules still sync everything
-- else fine, and the app's own CoreData copy of the label is unaffected on the device that set it.

alter table public.schedules
    add column if not exists routine_label text;
