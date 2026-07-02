# Caregiver Sharing — Design Spec

**Date:** 2026-07-03
**Status:** Approved by user, pending spec review

## Context

DoseTrack's original plan (CLAUDE.md) listed "Family Sharing" as a Pro feature but never designed it — Settings currently shows a "Coming Soon" stub. The app also has CloudKit sync plumbing (`PersistenceController`) that is unused (the iCloud Sync toggle is a disabled `.constant(false)`) and duplicates the Supabase auth/sync layer that was added later.

Decision: **drop CloudKit entirely.** It only syncs within one person's own devices and is iOS-only; DoseTrack needs cross-person sharing and, eventually, Android support, so Supabase is the right backbone for both. This spec covers what replaces Family Sharing: a **caregiver** feature where one person can be granted full co-management access to another person's account.

This is a Pro feature (per CLAUDE.md's original Family Sharing gating) and requires a companion cleanup task to remove CloudKit code — tracked separately, not in this spec's implementation scope beyond noting it as a prerequisite. Gating is enforced on the **patient's** subscription: "Invite a Caregiver" in Settings is paywalled the same way the existing "Family Sharing" entry point was, since it's the patient's data being shared. The caregiver does not need their own Pro subscription to accept an invite and use the co-management access — access is granted through the relationship, not through their own entitlement (analogous to a Pro user's data remaining visible read/write to a linked caregiver regardless of that caregiver's own plan).

## Goals

- A caregiver can be invited by a patient, and once linked, has full read/write access to that patient's medications, schedules, and dose logs — equivalent to the patient's own access.
- One caregiver can oversee multiple patients. Each patient has at most one active caregiver.
- Patients always have their own real account; there is no caregiver-only-managed "lite" account.
- Caregivers switch between their own account and any patient they oversee via an Instagram-style account switcher; the whole app (all tabs) reflects whichever account is active.
- Caregivers get proactive push notifications when a patient misses a dose.
- Solo (non-caregiving) users keep local-first data as today; only accounts that enter a caregiver relationship become server-backed for the entities that must be shared.
- A patient's own on-device reminders and notifications continue to run locally via `UNCalendarNotificationTrigger` exactly as today regardless of whether a caregiver is linked — linking a caregiver adds server-backed data and a second (push-based) notification path to the caregiver, it does not make the patient's own reminders depend on Supabase or network connectivity.

## Non-goals

- Many-to-many relationships (multiple caregivers per patient) — explicitly deferred.
- Caregiver-managed accounts for people who never use the app themselves — explicitly deferred.
- Android implementation — out of scope for this spec, but the Supabase-based design should not preclude it later.
- View-only or partial permission tiers — access is all-or-nothing (full co-management) for this version.

## Data Model (Supabase)

New table `caregiver_relationships`:

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `caregiver_user_id` | uuid | FK to auth user |
| `patient_user_id` | uuid | FK to auth user |
| `status` | text | `pending`, `active`, `revoked` |
| `invite_code` | text | short-lived code, unique, expires after 24h |
| `created_at` | timestamptz | |
| `activated_at` | timestamptz | nullable |
| `revoked_at` | timestamptz | nullable |

Constraints:
- A partial unique index enforces at most one row with `status IN ('pending', 'active')` per `patient_user_id` — a patient cannot generate a new invite while one is already pending or active; they must revoke/let it expire first. The "Invite a Caregiver" UI checks for an existing pending/active row and shows its state (e.g. "Invite pending — resend or cancel") instead of creating a duplicate.
- A check constraint rejects `caregiver_user_id = patient_user_id` (a patient cannot accept their own invite).
- The accept Edge Function performs the validate-and-activate as a single atomic UPDATE with a `WHERE status = 'pending' AND invite_code = $1 AND expires_at > now()` guard, using the update's affected-row-count as the source of truth (0 rows = already accepted/expired/invalid, race-safe under concurrent accept attempts — no separate read-then-write).

Row Level Security: extend policies on `medications`, `schedules`, `dose_logs` so a request is authorized if `auth.uid() = owner_user_id` OR there exists an active `caregiver_relationships` row where `caregiver_user_id = auth.uid()` and `patient_user_id = owner_user_id`. Revocation (`status` leaving `active`) takes effect immediately for all subsequent requests since RLS is evaluated per-query, not cached.

Account deletion: deleting either user's auth account cascades to delete all `caregiver_relationships` rows (both directions — as caregiver and as patient) and their `device_push_tokens` rows. This is a hard delete, not a soft-revoke, since the referenced auth user no longer exists. If the deleted user is a **patient**, their `medications`/`schedules`/`dose_logs` rows are deleted along with their auth account per existing account-deletion behavior (this feature doesn't change that) — any caregiver simply loses the (now-deleted) entry from their switcher. If the deleted user is a **caregiver**, only the relationship/push-token rows are removed; the patient's own data is untouched since the caregiver never owned it.

New table `device_push_tokens`: `user_id, apns_token, updated_at` — needed for the missed-dose notification job to reach the caregiver's device.

## Data Flow: CoreData ↔ Supabase

CoreData on the patient's own device remains the on-device source of truth, exactly as today — this feature does not migrate patients to a server-source-of-truth model. `SupabaseSyncManager` (existing) already pushes local `Medication`/`Schedule`/`DoseLog` writes to Supabase and pulls/merges remote rows back via `pullAll`/`mergeMedications`/`mergeSchedules`/`mergeDoseLogs`. This feature extends that existing mechanism rather than replacing it:

- When a caregiver relationship is `active`, the patient's own device continues syncing exactly as it does now (push on write, pull/merge on refresh) — the RLS change described above only affects who else is *authorized* to read/write those Supabase rows, not how the patient's own device behaves.
- The caregiver's device, when its `ActiveAccountContext` is set to a patient, runs the same `pullAll`/merge functions but against the patient's `user_id` instead of its own, writing into a **separate local CoreData store scoped to that patient** (not merged into the caregiver's own medications). Any edit the caregiver makes calls the same `pushMedication`/`pushSchedule`/`pushDoseLog` functions, tagged with the patient's `user_id`, which Supabase accepts because of the RLS policy above.
- Conflict resolution follows the existing merge logic's last-write-wins behavior (whatever `mergeMedications` etc. already do for the patient's own multi-device case) — this feature does not introduce new conflict semantics, since a caregiver editing a patient's data is not materially different from the patient editing it from a second device.
- Net effect: no new sync engine is being built. This is the existing single-user sync path, invoked once for the caregiver's own account and again for each patient they've switched into, authorized by the new RLS rule.

## Invite Flow

1. Patient: Settings → "Invite a Caregiver" → calls a Supabase Edge Function that creates a `pending` `caregiver_relationships` row with a fresh `invite_code`, returns a code + a universal link `https://dosetrack.app/invite/<code>`.
2. App renders the link as a QR code and as a shareable text/link (Messages/email/AirDrop share sheet).
3. Caregiver scans QR or opens link:
   - App not installed → universal link falls back to App Store listing.
   - App installed → deep link opens an "Accept Caregiver Invite" screen showing the patient's display name and a plain-language description of what access is being granted (full read/write to their medications, schedules, and dose logs), with Accept/Decline.
4. Accept calls an Edge Function that validates the code (not expired, still pending), sets `caregiver_user_id` to the accepting user, flips `status` to `active`, sets `activated_at`.
5. Both sides reflect the change: patient's Settings shows "Co-managed by <name>" with a Remove option; caregiver's account switcher gains the new entry.

Edge cases: expired code (>24h) shown as "This invite has expired, ask them to send a new one"; code already used/revoked shown as "This invite is no longer valid"; offline acceptance queues the accept call and retries when connectivity returns.

## Account Switcher UI

- Visible only when the signed-in user has ≥1 linked account (as caregiver of someone, in this version — patients don't get a switcher since they only ever have one caregiver, not the reverse).
- A chevron next to the account name near the top of the main tab view opens a bottom sheet (mirrors the reference Instagram screenshots): "My Account" (checkmark when active), then each overseen patient by name, then "Add Caregiver Account" to start a new invite-accept flow.
- Selecting an entry sets an `ActiveAccountContext` (an `ObservableObject`/environment value) holding the currently active `user_id` and display name. Today, Medications, History, and the relevant parts of Settings all scope their queries/fetches to `ActiveAccountContext.activeUserId` instead of always using the signed-in user's own id.
- A small persistent label (e.g. under the nav bar or in the tab bar area) always shows whose account is currently active, so it's never ambiguous.

## Missed-Dose Alerts

- A scheduled Supabase Edge Function (cron, e.g. every 15 min) scans active relationships. For each patient, it finds schedules whose due time is 30-60+ minutes past and has no corresponding `dose_logs` entry, and where a notification for that occurrence hasn't already been sent.
- Due times are evaluated in the patient's stored timezone preference (the same timezone their own on-device reminders use), not server UTC or the caregiver's timezone — this must be a field already available from the existing schedule/notification data, not a new concept introduced here.
- To avoid false-positive alerts from sync lag (patient logged the dose on their device but it hasn't reached Supabase yet), the job only alerts on doses still unlogged **60+ minutes** after due (not 30) and skips the check entirely if the patient's device has synced within the last 10 minutes with no corresponding log — i.e. prefer a late alert over a wrong one.
- For each qualifying miss, sends an APNs push to the caregiver's token(s) from `device_push_tokens`, e.g. "Mom missed her 8:00 AM Metformin dose."
- Track sent-notification state via a dedup table `missed_dose_alerts (patient_user_id, schedule_id, scheduled_date, sent_at)` with a unique constraint on `(schedule_id, scheduled_date)` — chosen over a column on dose occurrences because "occurrences" aren't materialized rows in the current schema (schedules generate them implicitly by time), so a standalone table is the simpler fit. The cron job inserts a row (or no-ops on unique-constraint conflict) before sending the push, so a crash/retry mid-run can't double-send. If a late dose log arrives after an alert was already sent, no retraction/follow-up message is sent in this version (acceptable false-positive-after-the-fact, noted as a known limitation).

## Revocation

- Patient can remove their caregiver from Settings at any time → sets `status = revoked`, `revoked_at`. RLS immediately blocks further access.
- Caregiver can remove themselves from a patient's list similarly.
- If a caregiver is actively viewing a patient's account when access is revoked, the next data fetch fails auth and the app falls back to "My Account" with a message ("Your access to <name>'s account has ended").
- To bound how long a caregiver could act on stale cached data while genuinely offline (no fetch attempted, so the auth failure above never triggers), the app re-validates the active relationship's status whenever it becomes active/foregrounded, not only on data fetch — an offline caregiver viewing cached data is a known, accepted limitation (no local data is fully trustworthy without connectivity), but returning from background is treated as a checkpoint to catch revocations promptly.

## Testing

- Unit tests for relationship state transitions (pending → active → revoked, invalid transitions rejected) in whatever service wraps `caregiver_relationships` calls.
- Unit tests for the missed-dose detection logic as a pure function: `(schedules, doseLogs, now) -> [overdueOccurrence]`, independent of the Edge Function/cron wiring.
- UI test for the switcher: selecting a different account changes the content shown on Today/Medications/History.
- Manual verification of the invite deep link on a real device (universal links can't be fully tested in simulator).

## Open Items / Follow-up (not blocking this spec)

- Removing the now-dead CloudKit code path in `PersistenceController` and the disabled iCloud Sync toggle in Settings — separate cleanup task.
- Eventual Android client will need to consume the same Supabase tables/Edge Functions; nothing in this design is iOS-specific except the switcher UI and push token format.
- **Accepted limitation, not resolved:** a caregiver who stays foregrounded-but-offline (or never backgrounds the app) after their access is revoked can continue viewing stale cached patient data indefinitely, since neither the fetch-failure path nor the foreground-revalidation checkpoint fires without connectivity. Bounding this fully would require a local cache TTL/force-refresh timer, which is deferred as a follow-up if it proves to matter in practice.
