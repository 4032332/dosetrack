# Caregiver Sharing — Design Spec

**Date:** 2026-07-03
**Status:** Approved by user, pending spec review

## Context

DoseTrack's original plan (CLAUDE.md) listed "Family Sharing" as a Pro feature but never designed it — Settings currently shows a "Coming Soon" stub. The app also has CloudKit sync plumbing (`PersistenceController`) that is unused (the iCloud Sync toggle is a disabled `.constant(false)`) and duplicates the Supabase auth/sync layer that was added later.

Decision: **drop CloudKit entirely.** It only syncs within one person's own devices and is iOS-only; DoseTrack needs cross-person sharing and, eventually, Android support, so Supabase is the right backbone for both. This spec covers what replaces Family Sharing: a **caregiver** feature where one person can be granted full co-management access to another person's account.

This is a Pro feature (per CLAUDE.md's original Family Sharing gating) and requires a companion cleanup task to remove CloudKit code — tracked separately, not in this spec's implementation scope beyond noting it as a prerequisite.

## Goals

- A caregiver can be invited by a patient, and once linked, has full read/write access to that patient's medications, schedules, and dose logs — equivalent to the patient's own access.
- One caregiver can oversee multiple patients. Each patient has at most one active caregiver.
- Patients always have their own real account; there is no caregiver-only-managed "lite" account.
- Caregivers switch between their own account and any patient they oversee via an Instagram-style account switcher; the whole app (all tabs) reflects whichever account is active.
- Caregivers get proactive push notifications when a patient misses a dose.
- Solo (non-caregiving) users keep local-first data as today; only accounts that enter a caregiver relationship become server-backed for the entities that must be shared.

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

Constraint: at most one row with `status = active` per `patient_user_id`.

Row Level Security: extend policies on `medications`, `schedules`, `dose_logs` so a request is authorized if `auth.uid() = owner_user_id` OR there exists an active `caregiver_relationships` row where `caregiver_user_id = auth.uid()` and `patient_user_id = owner_user_id`.

New table `device_push_tokens`: `user_id, apns_token, updated_at` — needed for the missed-dose notification job to reach the caregiver's device.

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
- For each qualifying miss, sends an APNs push to the caregiver's token(s) from `device_push_tokens`, e.g. "Mom missed her 8:00 AM Metformin dose."
- Track sent-notification state (e.g. a `notified_at` column on dose occurrences, or a small dedup table) to avoid duplicate alerts on subsequent cron runs.

## Revocation

- Patient can remove their caregiver from Settings at any time → sets `status = revoked`, `revoked_at`. RLS immediately blocks further access.
- Caregiver can remove themselves from a patient's list similarly.
- If a caregiver is actively viewing a patient's account when access is revoked, the next data fetch fails auth and the app falls back to "My Account" with a message ("Your access to <name>'s account has ended").

## Testing

- Unit tests for relationship state transitions (pending → active → revoked, invalid transitions rejected) in whatever service wraps `caregiver_relationships` calls.
- Unit tests for the missed-dose detection logic as a pure function: `(schedules, doseLogs, now) -> [overdueOccurrence]`, independent of the Edge Function/cron wiring.
- UI test for the switcher: selecting a different account changes the content shown on Today/Medications/History.
- Manual verification of the invite deep link on a real device (universal links can't be fully tested in simulator).

## Open Items / Follow-up (not blocking this spec)

- Removing the now-dead CloudKit code path in `PersistenceController` and the disabled iCloud Sync toggle in Settings — separate cleanup task.
- Eventual Android client will need to consume the same Supabase tables/Edge Functions; nothing in this design is iOS-specific except the switcher UI and push token format.
