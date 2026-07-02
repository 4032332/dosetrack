# Caregiver Sharing Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a patient invite a caregiver (via QR/link) who gets full read/write access to the patient's medications, schedules, and dose logs, switchable via an account-switcher UI, with proactive push alerts to the caregiver on missed doses.

**Architecture:** Extend the existing Supabase backend (used today for auth + single-user sync via `SupabaseSyncManager`) with a `caregiver_relationships` table, RLS policies granting caregivers access to a linked patient's rows, and two Edge Functions (invite create/accept, missed-dose cron). On iOS, parameterize `SupabaseSyncManager`'s push/pull functions to target an arbitrary authorized `userId`, add an `ActiveAccountContext` that all tabs read from, and add an Instagram-style account-switcher sheet. No new sync engine — this reuses the existing push/pull/merge mechanism.

**Tech Stack:** Swift 5.9/SwiftUI (iOS 17+), CoreData, Supabase (Postgres + Auth + Edge Functions in Deno/TypeScript + APNs via a push provider), XCTest.

**Spec:** `docs/superpowers/specs/2026-07-03-caregiver-sharing-design.md` — read this in full before starting; it has the authoritative rationale for every decision below.

**Supabase access:** Use the Supabase MCP tools (`list_tables`, `apply_migration`, `deploy_edge_function`, `execute_sql`, `get_advisors`) available in this session rather than a local `supabase/` CLI project — there is no local Supabase CLI scaffold in this repo today.

---

## Chunk 1: Backend schema, RLS, and invite Edge Functions

### Task 1: Create `caregiver_relationships` table

**Files:** none (Supabase migration via MCP tool)

- [ ] **Step 1: Inspect existing schema for naming conventions**

Run `list_tables` (Supabase MCP tool) and note the exact column naming style used on `medications`/`schedules`/`dose_logs` (e.g. is the owner column `user_id`?) so the new table matches.

- [ ] **Step 2: Write and apply the migration**

Use `apply_migration` with name `create_caregiver_relationships` and SQL:

```sql
create table caregiver_relationships (
  id uuid primary key default gen_random_uuid(),
  caregiver_user_id uuid not null references auth.users(id) on delete cascade,
  patient_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('pending', 'active', 'revoked')) default 'pending',
  invite_code text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  activated_at timestamptz,
  revoked_at timestamptz,
  constraint no_self_invite check (caregiver_user_id <> patient_user_id)
);

-- At most one pending/active relationship per patient
create unique index one_open_relationship_per_patient
  on caregiver_relationships (patient_user_id)
  where status in ('pending', 'active');

create index on caregiver_relationships (caregiver_user_id) where status = 'active';
create index on caregiver_relationships (invite_code);

alter table caregiver_relationships enable row level security;

-- A user can see relationships where they are either party
create policy "caregiver_relationships_select_own"
  on caregiver_relationships for select
  using (auth.uid() = caregiver_user_id or auth.uid() = patient_user_id);

-- Only the patient can create an invite for themselves
create policy "caregiver_relationships_insert_own"
  on caregiver_relationships for insert
  with check (auth.uid() = patient_user_id);

-- Either party can update (revoke); acceptance itself goes through the
-- accept-caregiver-invite Edge Function using the service role, not this policy.
create policy "caregiver_relationships_update_own"
  on caregiver_relationships for update
  using (auth.uid() = caregiver_user_id or auth.uid() = patient_user_id);
```

- [ ] **Step 3: Verify with `get_advisors`**

Run `get_advisors` (type: security) and confirm no new lint warnings on this table (e.g. missing RLS, which is already enabled above).

- [ ] **Step 4: Commit a record of the migration**

There's no local migration file since this was applied via MCP — instead, append the exact SQL above (already written in this plan) is the durable record. No git commit needed for this step; proceed to Task 2.

### Task 2: Create `device_push_tokens` table

**Files:** none (Supabase migration via MCP tool)

- [ ] **Step 1: Apply migration**

Use `apply_migration` with name `create_device_push_tokens`:

```sql
create table device_push_tokens (
  user_id uuid not null references auth.users(id) on delete cascade,
  apns_token text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, apns_token)
);

alter table device_push_tokens enable row level security;

create policy "device_push_tokens_own"
  on device_push_tokens for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
```

- [ ] **Step 2: Verify with `get_advisors`** — same as Task 1 Step 3.

### Task 3: Extend RLS on `medications`, `schedules`, `dose_logs` for caregiver access

**Files:** none (Supabase migration via MCP tool)

- [ ] **Step 1: Read current policies**

Run `execute_sql` with:
```sql
select tablename, policyname, qual from pg_policies
where tablename in ('medications', 'schedules', 'dose_logs');
```
Record the exact current `using`/`with check` clauses so Step 2 can replace them precisely rather than guessing.

- [ ] **Step 2: Apply migration adding the caregiver clause**

For each of `medications`, `schedules`, `dose_logs`, use `apply_migration` (name `extend_rls_for_caregivers`) to `drop policy` and recreate with the owner check OR'd with an active caregiver check, e.g. for `medications`:

```sql
drop policy if exists "medications_select_own" on medications;
create policy "medications_select_own" on medications for select
  using (
    auth.uid() = user_id
    or exists (
      select 1 from caregiver_relationships cr
      where cr.status = 'active'
        and cr.caregiver_user_id = auth.uid()
        and cr.patient_user_id = medications.user_id
    )
  );
-- Repeat the same OR-clause shape for the insert/update/delete policies on this table.
```

Repeat the same pattern for `schedules` and `dose_logs`, and for every existing CRUD policy on each (not just select) — a caregiver needs full read/write per the spec's "full co-management" decision.

- [ ] **Step 3: Verify with a manual query test**

Use `execute_sql` to confirm the policy exists as expected:
```sql
select policyname, qual from pg_policies where tablename = 'medications';
```
Confirm the caregiver `exists(...)` clause appears in the output.

- [ ] **Step 4: Run `get_advisors`** and confirm no new warnings.

### Task 4: `create-caregiver-invite` Edge Function

**Files:**
- Create (via `deploy_edge_function`): `create-caregiver-invite`

- [ ] **Step 1: Write the function**

```typescript
// create-caregiver-invite/index.ts
import { createClient } from 'jsr:@supabase/supabase-js@2'

Deno.serve(async (req) => {
  const authHeader = req.headers.get('Authorization')!
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } }
  )
  const { data: { user }, error: authError } = await supabase.auth.getUser()
  if (authError || !user) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 })
  }

  const code = crypto.randomUUID().slice(0, 8).toUpperCase()
  const { data, error } = await supabase
    .from('caregiver_relationships')
    .insert({ patient_user_id: user.id, caregiver_user_id: user.id, invite_code: code, status: 'pending' })
    .select()
    .single()

  // caregiver_user_id is a placeholder (self) until accept swaps it in — see accept function.
  // The no_self_invite check constraint would reject this; instead insert caregiver_user_id
  // as NULL-able at insert time. Adjust the table: caregiver_user_id must be nullable until
  // accepted. Revisit Task 1 Step 2 to make caregiver_user_id nullable, and move the
  // no_self_invite check to apply only when caregiver_user_id is not null:
  //   constraint no_self_invite check (caregiver_user_id is null or caregiver_user_id <> patient_user_id)

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }
  return new Response(JSON.stringify({
    code: data.invite_code,
    link: `https://dosetrack.app/invite/${data.invite_code}`,
  }), { status: 200 })
})
```

**Before implementing this step**, go back and amend Task 1's migration: `caregiver_user_id` must be nullable (a pending invite has no caregiver yet), and the `no_self_invite` check must allow null. Apply a follow-up migration via `apply_migration` (name `make_caregiver_user_id_nullable`):

```sql
alter table caregiver_relationships alter column caregiver_user_id drop not null;
alter table caregiver_relationships drop constraint no_self_invite;
alter table caregiver_relationships add constraint no_self_invite
  check (caregiver_user_id is null or caregiver_user_id <> patient_user_id);
```

Then the insert in the function above should omit `caregiver_user_id` entirely (leave it null) rather than setting it to `user.id`.

- [ ] **Step 2: Deploy**

Use `deploy_edge_function` with the corrected source (insert omits `caregiver_user_id`).

- [ ] **Step 3: Manual verification**

Call the function with a valid user JWT (via `curl` or the Supabase dashboard's function test UI) and confirm it returns a `code` and `link`, and that `execute_sql` shows a new `pending` row with `caregiver_user_id is null`.

### Task 5: `accept-caregiver-invite` Edge Function

**Files:**
- Create (via `deploy_edge_function`): `accept-caregiver-invite`

- [ ] **Step 1: Write the function**

```typescript
// accept-caregiver-invite/index.ts
import { createClient } from 'jsr:@supabase/supabase-js@2'

Deno.serve(async (req) => {
  const { code } = await req.json()
  const authHeader = req.headers.get('Authorization')!
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } }
  )
  const { data: { user }, error: authError } = await supabase.auth.getUser()
  if (authError || !user) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 })
  }

  // Atomic validate-and-activate: 0 affected rows means invalid/expired/already-used.
  const { data, error } = await supabase
    .from('caregiver_relationships')
    .update({ caregiver_user_id: user.id, status: 'active', activated_at: new Date().toISOString() })
    .eq('invite_code', code)
    .eq('status', 'pending')
    .gt('expires_at', new Date().toISOString())
    .neq('patient_user_id', user.id) // belt-and-suspenders alongside the DB check constraint
    .select()

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }
  if (!data || data.length === 0) {
    return new Response(JSON.stringify({ error: 'invalid_or_expired' }), { status: 409 })
  }
  return new Response(JSON.stringify({ patientUserId: data[0].patient_user_id }), { status: 200 })
})
```

Note: this relies on RLS's update policy (`caregiver_relationships_update_own`) allowing the accepting user to update a row where they are not yet a party to it. Since the accepting user isn't `caregiver_user_id` (still null) or `patient_user_id` at the time of the update, the existing `update_own` policy from Task 1 will reject this. **Fix:** this function must run with the Supabase **service role key** (bypassing RLS), read via `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` for a second privileged client used only for this update — the `authHeader`-scoped client above is still used for `auth.getUser()` to identify the caller, but the update itself uses the service-role client.

- [ ] **Step 2: Correct the function to use a service-role client for the update**, per the note above, then deploy via `deploy_edge_function`.

- [ ] **Step 3: Manual verification**

Create an invite (Task 4), then call `accept-caregiver-invite` with a different user's JWT and the code. Confirm 200 + `patientUserId`. Call again with the same code — confirm 409 `invalid_or_expired` (proves the atomic guard works). Call with the *same* user who created the invite (patient accepting their own) — confirm rejection (either 400 from the check constraint or the explicit `.neq` filter returning 0 rows).

### Task 6: Missed-dose alert dedup table

**Files:** none (Supabase migration via MCP tool)

- [ ] **Step 1: Apply migration**

```sql
create table missed_dose_alerts (
  id uuid primary key default gen_random_uuid(),
  patient_user_id uuid not null references auth.users(id) on delete cascade,
  schedule_id uuid not null,
  scheduled_date date not null,
  sent_at timestamptz not null default now(),
  unique (schedule_id, scheduled_date)
);
```

This table has no RLS policy for direct client access — it's only touched by the Edge Function (Chunk 3, Task 12) via the service-role key, so leave RLS disabled or enabled-with-no-policies (default-deny) rather than adding a client-facing policy.

- [ ] **Step 2: Run `get_advisors`** and confirm the "RLS disabled" warning (if any) is expected/acceptable here since this table is service-role-only — note this explicitly rather than silently ignoring an advisor warning.

---

## Chunk 2: iOS sync parameterization

@docs/superpowers/specs/2026-07-03-caregiver-sharing-design.md — re-read the "Data Flow: CoreData ↔ Supabase" section before starting; it specifies exactly what must change and why.

### Task 7: Add `ActiveAccountContext`

**Files:**
- Create: `DoseTrack/App/ActiveAccountContext.swift`
- Test: `DoseTrackTests/ActiveAccountContextTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DoseTrack

final class ActiveAccountContextTests: XCTestCase {
    func test_defaultsToSignedInUser() {
        let ownId = UUID()
        let ctx = ActiveAccountContext(ownUserId: ownId, ownDisplayName: "Me")
        XCTAssertEqual(ctx.activeUserId, ownId)
        XCTAssertFalse(ctx.isViewingOtherAccount)
    }

    func test_switchingToPatientUpdatesActiveUserId() {
        let ownId = UUID()
        let patientId = UUID()
        let ctx = ActiveAccountContext(ownUserId: ownId, ownDisplayName: "Me")
        ctx.switchTo(userId: patientId, displayName: "Mom")
        XCTAssertEqual(ctx.activeUserId, patientId)
        XCTAssertTrue(ctx.isViewingOtherAccount)
    }

    func test_switchingBackToOwnAccount() {
        let ownId = UUID()
        let ctx = ActiveAccountContext(ownUserId: ownId, ownDisplayName: "Me")
        ctx.switchTo(userId: UUID(), displayName: "Mom")
        ctx.switchToOwnAccount()
        XCTAssertEqual(ctx.activeUserId, ownId)
        XCTAssertFalse(ctx.isViewingOtherAccount)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator -only-testing:DoseTrackTests/ActiveAccountContextTests 2>&1 | tail -30`
Expected: FAIL / build error — `ActiveAccountContext` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// DoseTrack/App/ActiveAccountContext.swift
import Foundation

/// Tracks which account's data the app should currently display/act on.
/// Defaults to the signed-in user's own account; a caregiver can switch it
/// to a linked patient via the account switcher.
@MainActor
final class ActiveAccountContext: ObservableObject {
    @Published private(set) var activeUserId: UUID
    @Published private(set) var activeDisplayName: String

    let ownUserId: UUID
    let ownDisplayName: String

    var isViewingOtherAccount: Bool { activeUserId != ownUserId }

    init(ownUserId: UUID, ownDisplayName: String) {
        self.ownUserId = ownUserId
        self.ownDisplayName = ownDisplayName
        self.activeUserId = ownUserId
        self.activeDisplayName = ownDisplayName
    }

    func switchTo(userId: UUID, displayName: String) {
        activeUserId = userId
        activeDisplayName = displayName
    }

    func switchToOwnAccount() {
        activeUserId = ownUserId
        activeDisplayName = ownDisplayName
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator -only-testing:DoseTrackTests/ActiveAccountContextTests 2>&1 | tail -30`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/App/ActiveAccountContext.swift DoseTrackTests/ActiveAccountContextTests.swift
git commit -m "feat: add ActiveAccountContext for caregiver account switching"
```

### Task 8: Parameterize `SupabaseSyncManager` pull/push functions by target user

**Files:**
- Modify: `DoseTrack/Services/SupabaseSyncManager.swift:22,43,56,63,111-123,127-204`
- Test: `DoseTrackTests/SupabaseSyncManagerTests.swift` (create if it doesn't already cover this)

This is the change flagged as understated risk during spec review — read `DoseTrack/Services/SupabaseSyncManager.swift` in full first (395 lines) before touching it, since every fetch/push function currently reads `AuthManager.shared.session?.user.id` internally.

- [ ] **Step 1: Write failing tests for the new signatures**

Since these functions do real network I/O against Supabase, write tests against the *query construction*, not live network calls — check current test file conventions first:

```bash
grep -n "class\|func test" DoseTrackTests/*.swift | grep -i supabase
```

If no existing pattern for testing this file exists (likely, since it's a thin wrapper over network calls), write a narrower unit test for the pure logic extracted in Step 3 below (a `targetUserId(for:)` resolver), rather than trying to mock the Supabase client — that keeps this task's test honest about what's actually being verified.

```swift
import XCTest
@testable import DoseTrack

final class SupabaseSyncManagerTargetUserTests: XCTestCase {
    func test_targetUserId_defaultsToNilMeaningCurrentSession() {
        // No explicit target passed → resolver returns nil, signaling "use current session's own id"
        XCTAssertNil(SupabaseSyncManager.resolveTargetUserId(explicit: nil))
    }

    func test_targetUserId_usesExplicitValueWhenProvided() {
        let id = UUID()
        XCTAssertEqual(SupabaseSyncManager.resolveTargetUserId(explicit: id), id)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator -only-testing:DoseTrackTests/SupabaseSyncManagerTargetUserTests 2>&1 | tail -30`
Expected: FAIL — `resolveTargetUserId` not defined.

- [ ] **Step 3: Add the resolver and parameterize the public functions**

Add near the top of `SupabaseSyncManager`:

```swift
static func resolveTargetUserId(explicit: UUID?) -> UUID? {
    explicit
}
```

Change each function signature to accept an optional `forUserId: UUID? = nil` defaulting to today's behavior (own session) when nil:

```swift
func pullAll(context: NSManagedObjectContext, forUserId: UUID? = nil) async {
    guard AuthManager.shared.isSignedIn, !AuthManager.shared.isGuest else { return }
    let targetUserId = Self.resolveTargetUserId(explicit: forUserId) ?? AuthManager.shared.session?.user.id
    guard let targetUserId else { return }
    do {
        async let meds    = fetchRemoteMedications(userId: targetUserId)
        async let scheds  = fetchRemoteSchedules(userId: targetUserId)
        async let logs    = fetchRemoteDoseLogs(userId: targetUserId)
        async let settings = fetchRemoteSettings(userId: targetUserId)
        let (m, s, l, st) = try await (meds, scheds, logs, settings)
        mergeMedications(m, context: context)
        mergeSchedules(s, context: context)
        mergeDoseLogs(l, context: context)
        if let st { applySettings(st) }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    } catch {
        print("SupabaseSync pullAll error: \(error)")
    }
}

func pushMedication(_ med: Medication, forUserId: UUID? = nil) async {
    guard AuthManager.shared.isSignedIn, !AuthManager.shared.isGuest,
          let id = med.id else { return }
    let targetUserId = Self.resolveTargetUserId(explicit: forUserId) ?? AuthManager.shared.session?.user.id
    guard let targetUserId else { return }
    let row = MedicationRow(medication: med, userId: targetUserId)
    do {
        try await client.from("medications").upsert(row).execute()
        for schedule in med.schedulesArray {
            await pushSchedule(schedule, medicationId: id, userId: targetUserId)
        }
    } catch { print("pushMedication error: \(error)") }
}
```

Apply the same `forUserId: UUID? = nil` pattern to `pushSchedule`, `pushDoseLog`, and the four private `fetchRemote*` functions (add a `userId: UUID` parameter to each and filter the Supabase query by it — check the exact `.eq(...)` call needed by reading how `fetchRemoteMedications()` currently queries, since it likely relies on RLS alone with no explicit filter; add an explicit `.eq("user_id", userId.uuidString)` filter so behavior is correct even before RLS changes propagate, not just correct-by-accident via RLS).

Call sites that invoke these functions without a target (existing solo-user flows) don't need to change — the default `nil` preserves current behavior exactly.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator -only-testing:DoseTrackTests/SupabaseSyncManagerTargetUserTests 2>&1 | tail -30`
Expected: PASS

- [ ] **Step 5: Build the whole app to confirm no call-site breakage**

Run: `xcodebuild -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator build 2>&1 | tail -40`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add DoseTrack/Services/SupabaseSyncManager.swift DoseTrackTests/SupabaseSyncManagerTargetUserTests.swift
git commit -m "feat: parameterize SupabaseSyncManager to sync on behalf of a target user"
```

### Task 9: `CaregiverManager` service (relationship CRUD, invite generate/accept)

**Files:**
- Create: `DoseTrack/Services/CaregiverManager.swift`
- Create: `DoseTrack/Models/CaregiverRelationshipRow.swift`
- Test: `DoseTrackTests/CaregiverManagerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import DoseTrack

final class CaregiverManagerTests: XCTestCase {
    func test_relationshipDisplaysAsPendingBeforeActivation() {
        let row = CaregiverRelationshipRow(
            id: UUID(), caregiverUserId: nil, patientUserId: UUID(),
            status: "pending", inviteCode: "ABC123", createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86_400), activatedAt: nil, revokedAt: nil
        )
        XCTAssertTrue(row.isPending)
        XCTAssertFalse(row.isActive)
        XCTAssertFalse(row.isExpired)
    }

    func test_relationshipIsExpiredPastExpiresAt() {
        let row = CaregiverRelationshipRow(
            id: UUID(), caregiverUserId: nil, patientUserId: UUID(),
            status: "pending", inviteCode: "ABC123", createdAt: Date().addingTimeInterval(-90_000),
            expiresAt: Date().addingTimeInterval(-3_600), activatedAt: nil, revokedAt: nil
        )
        XCTAssertTrue(row.isExpired)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator -only-testing:DoseTrackTests/CaregiverManagerTests 2>&1 | tail -30`
Expected: FAIL — `CaregiverRelationshipRow` not defined.

- [ ] **Step 3: Implement the model**

```swift
// DoseTrack/Models/CaregiverRelationshipRow.swift
import Foundation

struct CaregiverRelationshipRow: Codable, Identifiable {
    let id: UUID
    let caregiverUserId: UUID?
    let patientUserId: UUID
    let status: String
    let inviteCode: String
    let createdAt: Date
    let expiresAt: Date
    let activatedAt: Date?
    let revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case caregiverUserId = "caregiver_user_id"
        case patientUserId = "patient_user_id"
        case status, status2 = "status"
        case inviteCode = "invite_code"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case activatedAt = "activated_at"
        case revokedAt = "revoked_at"
    }

    var isPending: Bool { status == "pending" }
    var isActive: Bool { status == "active" }
    var isRevoked: Bool { status == "revoked" }
    var isExpired: Bool { expiresAt < Date() }
}
```

(Remove the accidental duplicate `status2` case above when writing the real file — it's a typo in this plan, not intended for the shipped code. The real enum should have exactly one `status` case.)

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator -only-testing:DoseTrackTests/CaregiverManagerTests 2>&1 | tail -30`
Expected: PASS

- [ ] **Step 5: Implement `CaregiverManager` (network calls, no new unit tests for the network layer itself — same rationale as Task 8)**

```swift
// DoseTrack/Services/CaregiverManager.swift
import Foundation
import Supabase

@MainActor
final class CaregiverManager: ObservableObject {
    static let shared = CaregiverManager()
    private init() {}

    private var client: SupabaseClient { AuthManager.shared.client }

    @Published var myRelationships: [CaregiverRelationshipRow] = []

    /// Relationships where the signed-in user is the caregiver (active only) — drives the account switcher.
    var overseenPatients: [CaregiverRelationshipRow] {
        myRelationships.filter { $0.isActive && $0.caregiverUserId == AuthManager.shared.session?.user.id }
    }

    /// The signed-in user's own relationship as a patient, if any (pending or active) — drives Settings display.
    var ownPatientRelationship: CaregiverRelationshipRow? {
        myRelationships.first { $0.patientUserId == AuthManager.shared.session?.user.id && !$0.isRevoked }
    }

    func refresh() async {
        guard let userId = AuthManager.shared.session?.user.id else { return }
        do {
            let response: [CaregiverRelationshipRow] = try await client
                .from("caregiver_relationships")
                .select()
                .or("caregiver_user_id.eq.\(userId),patient_user_id.eq.\(userId)")
                .execute()
                .value
            myRelationships = response
        } catch {
            print("CaregiverManager refresh error: \(error)")
        }
    }

    struct InviteResponse: Decodable { let code: String; let link: String }

    func createInvite() async throws -> InviteResponse {
        let response: InviteResponse = try await client.functions
            .invoke("create-caregiver-invite", options: .init(body: [String: String]()))
        await refresh()
        return response
    }

    struct AcceptResponse: Decodable { let patientUserId: UUID }

    func acceptInvite(code: String) async throws -> AcceptResponse {
        let response: AcceptResponse = try await client.functions
            .invoke("accept-caregiver-invite", options: .init(body: ["code": code]))
        await refresh()
        return response
    }

    func revoke(relationshipId: UUID) async throws {
        try await client.from("caregiver_relationships")
            .update(["status": "revoked", "revoked_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", relationshipId.uuidString)
            .execute()
        await refresh()
    }
}
```

- [ ] **Step 6: Build to confirm it compiles**

Run: `xcodebuild -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator build 2>&1 | tail -40`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add DoseTrack/Services/CaregiverManager.swift DoseTrack/Models/CaregiverRelationshipRow.swift DoseTrackTests/CaregiverManagerTests.swift
git commit -m "feat: add CaregiverManager service for relationship CRUD and invites"
```

---

## Chunk 3: Invite UI, account switcher, deep links, missed-dose alerts, cleanup

### Task 10: Invite-a-caregiver UI (patient side)

**Files:**
- Create: `DoseTrack/Views/Settings/CaregiverInviteView.swift`
- Modify: `DoseTrack/Views/Settings/SettingsView.swift:219-230,330-345` (replace the `FamilySharingView` stub and disabled iCloud toggle)

- [ ] **Step 1: Build the invite view**

```swift
// DoseTrack/Views/Settings/CaregiverInviteView.swift
import SwiftUI
import CoreImage.CIFilterBuiltins

struct CaregiverInviteView: View {
    @EnvironmentObject var caregiverManager: CaregiverManager
    @State private var invite: CaregiverManager.InviteResponse?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if let relationship = caregiverManager.ownPatientRelationship {
                Section {
                    if relationship.isActive {
                        Text("Co-managed by your caregiver")
                        Button("Remove Caregiver", role: .destructive) {
                            Task { try? await caregiverManager.revoke(relationshipId: relationship.id) }
                        }
                    } else if relationship.isPending && !relationship.isExpired {
                        Text("Invite pending — share the code below, or cancel it to start over.")
                        Button("Cancel Invite", role: .destructive) {
                            Task { try? await caregiverManager.revoke(relationshipId: relationship.id) }
                        }
                    }
                }
            } else {
                Section {
                    Text("Invite someone to co-manage your medications — they'll be able to view and log doses on your behalf.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let invite {
                        qrCode(for: invite.link)
                        ShareLink(item: URL(string: invite.link)!) {
                            Label("Share Invite Link", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            Task { await generateInvite() }
                        } label: {
                            if isLoading { ProgressView() } else { Text("Generate Invite") }
                        }
                        .disabled(isLoading)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Caregiver")
        .task { await caregiverManager.refresh() }
    }

    private func generateInvite() async {
        isLoading = true; defer { isLoading = false }
        do { invite = try await caregiverManager.createInvite() }
        catch { errorMessage = "Couldn't create an invite. Please try again." }
    }

    private func qrCode(for string: String) -> some View {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        let context = CIContext()
        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return AnyView(EmptyView())
        }
        return AnyView(
            Image(decorative: cgImage, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: 200, height: 200)
        )
    }
}
```

- [ ] **Step 2: Wire it into Settings, gated on Pro, replacing the stub**

In `SettingsView.swift`, replace:
```swift
if subscriptionManager.isProSubscriber {
    NavigationLink {
        FamilySharingView()
    } label: {
        Label("Family Sharing", systemImage: "person.2.fill")
    }

    Toggle(isOn: .constant(false)) {
        Label("iCloud Sync", systemImage: "icloud.fill")
    }
    .disabled(true)
}
```
with:
```swift
if subscriptionManager.isProSubscriber {
    NavigationLink {
        CaregiverInviteView()
    } label: {
        Label("Caregiver", systemImage: "person.2.fill")
    }
}
```
And delete the `FamilySharingView` stub struct entirely (lines ~330-345) since it's superseded.

- [ ] **Step 3: Manual verification in simulator**

Run the app, sign in, navigate to Settings → Caregiver (as a Pro user — toggle Pro status via whatever debug mechanism the app already has for testing subscriptions), tap "Generate Invite", confirm a QR code renders and a share sheet works.

- [ ] **Step 4: Commit**

```bash
git add DoseTrack/Views/Settings/CaregiverInviteView.swift DoseTrack/Views/Settings/SettingsView.swift
git commit -m "feat: add caregiver invite UI, remove Family Sharing/iCloud stubs"
```

### Task 11: Accept-invite deep link screen + universal link routing

**Files:**
- Create: `DoseTrack/Views/Settings/AcceptCaregiverInviteView.swift`
- Modify: `DoseTrack/App/DoseTrackApp.swift` (or wherever `.onOpenURL`/universal link handling belongs — check `SceneDelegate.swift` first)
- Create: `DoseTrack/Utilities/Constants.swift` addition for the placeholder App Store fallback URL (see spec's "Pre-launch placeholder" note)

- [ ] **Step 1: Check existing URL/deep-link handling**

Run: `grep -rn "onOpenURL\|universal link\|continueUserActivity" DoseTrack/App/*.swift`
If nothing exists yet, this is a new addition; if something exists (e.g. for Sign in with Apple redirects), follow its existing pattern.

- [ ] **Step 2: Add the placeholder fallback URL constant**

In `DoseTrack/Utilities/Constants.swift`, add:
```swift
enum ExternalLinks {
    /// Pre-launch placeholder — swap for the real App Store listing URL once live.
    static let appStoreFallback = URL(string: "https://dosetrack.app/get-the-app")!
}
```

- [ ] **Step 3: Build the accept screen**

```swift
// DoseTrack/Views/Settings/AcceptCaregiverInviteView.swift
import SwiftUI

struct AcceptCaregiverInviteView: View {
    let code: String
    @EnvironmentObject var caregiverManager: CaregiverManager
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var accepted = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Caregiver Invitation")
                .font(.title2.bold())
            Text("Accepting this invite gives you full access to view and manage this person's medications, schedules, and dose history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if accepted {
                Label("Invite accepted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                Button {
                    Task { await accept() }
                } label: {
                    if isLoading { ProgressView() } else { Text("Accept") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                Button("Decline") { dismiss() }
            }
        }
        .padding()
    }

    private func accept() async {
        isLoading = true; defer { isLoading = false }
        do {
            _ = try await caregiverManager.acceptInvite(code: code)
            accepted = true
        } catch {
            errorMessage = "This invite is no longer valid."
        }
    }
}
```

- [ ] **Step 4: Route the universal link to this screen**

In `DoseTrackApp.swift`, add (adjust to match the app's actual root view structure found in Step 1):
```swift
.onOpenURL { url in
    guard url.host == "dosetrack.app", url.pathComponents.count >= 3,
          url.pathComponents[1] == "invite" else { return }
    let code = url.pathComponents[2]
    pendingInviteCode = code // @State/@Published surfaced to present AcceptCaregiverInviteView as a sheet
}
```
Wire `pendingInviteCode` to present `AcceptCaregiverInviteView(code:)` as a `.sheet(item:)` from the app's root view — follow whatever pattern `RootView.swift` already uses for other sheets.

- [ ] **Step 5: Manual verification**

Since universal links require a real associated domain and can't be fully tested in the simulator (per the spec's testing section), verify the `onOpenURL` parsing logic with a manual `xcrun simctl openurl booted "https://dosetrack.app/invite/TESTCODE"` and confirm the accept sheet appears with `code == "TESTCODE"`.

- [ ] **Step 6: Commit**

```bash
git add DoseTrack/Views/Settings/AcceptCaregiverInviteView.swift DoseTrack/App/DoseTrackApp.swift DoseTrack/Utilities/Constants.swift
git commit -m "feat: add caregiver invite acceptance screen and deep link routing"
```

### Task 12: Account switcher UI

**Files:**
- Create: `DoseTrack/Views/Components/AccountSwitcherView.swift`
- Modify: `DoseTrack/App/MainTabView.swift`
- Modify: `DoseTrack/App/DoseTrackApp.swift` (inject `ActiveAccountContext` into the environment)

- [ ] **Step 1: Inject `ActiveAccountContext` at the app root**

In `DoseTrackApp.swift`, construct it once the user's own id/display name is known (after sign-in) and pass via `.environmentObject`. Check how `AuthManager.shared.session` becomes available and construct `ActiveAccountContext(ownUserId: session.user.id, ownDisplayName: <profile name>)`.

- [ ] **Step 2: Build the switcher sheet**

```swift
// DoseTrack/Views/Components/AccountSwitcherView.swift
import SwiftUI

struct AccountSwitcherView: View {
    @EnvironmentObject var activeAccount: ActiveAccountContext
    @EnvironmentObject var caregiverManager: CaregiverManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingInvite = false

    var body: some View {
        List {
            Button {
                activeAccount.switchToOwnAccount()
                dismiss()
            } label: {
                HStack {
                    Text(activeAccount.ownDisplayName)
                    Spacer()
                    if !activeAccount.isViewingOtherAccount {
                        Image(systemName: "checkmark").foregroundStyle(.blue)
                    }
                }
            }
            ForEach(caregiverManager.overseenPatients) { relationship in
                Button {
                    activeAccount.switchTo(userId: relationship.patientUserId, displayName: relationship.patientDisplayName ?? "Account")
                    dismiss()
                } label: {
                    HStack {
                        Text(relationship.patientDisplayName ?? "Account")
                        Spacer()
                        if activeAccount.activeUserId == relationship.patientUserId {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
            }
            Button {
                showingInvite = true
            } label: {
                Label("Add Caregiver Account", systemImage: "plus.circle")
            }
        }
        .sheet(isPresented: $showingInvite) {
            NavigationStack { AcceptCaregiverInviteEntryView() } // simple text-entry fallback if not arriving via deep link
        }
    }
}
```

Note: `relationship.patientDisplayName` doesn't exist yet on `CaregiverRelationshipRow` — the row as designed in Task 9 only has user ids, not display names. **Fix before implementing:** either (a) join against a `profiles`/`user_settings` table when fetching in `CaregiverManager.refresh()` and add a `patientDisplayName: String?` field populated client-side after a follow-up profile fetch, or (b) have the Supabase select in `refresh()` use a foreign-table select if `profiles` is `public` and joinable. Check whether the codebase already has a `profiles` table (`grep -rn "profiles" DoseTrack/Services/*.swift`) before deciding — reuse whatever pattern already fetches a user's display name elsewhere (e.g. `ProfileView.swift`).

- [ ] **Step 3: Add the switcher trigger to `MainTabView`**

Add a top-level toolbar item or overlay near the top of the tab view (only shown if `!caregiverManager.overseenPatients.isEmpty`), e.g. as a `.safeAreaInset(edge: .top)` showing the active account name with a chevron that presents `AccountSwitcherView` as a `.sheet`.

- [ ] **Step 4: Manual verification**

With two test accounts linked via the invite flow (Tasks 10-11), confirm switching accounts in the sheet changes what `TodayView`/`MedicationsView`/`HistoryView` display (this requires Task 13 below to actually scope their fetches — do a smoke test after Task 13 is also done, not in isolation).

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/Views/Components/AccountSwitcherView.swift DoseTrack/App/MainTabView.swift DoseTrack/App/DoseTrackApp.swift
git commit -m "feat: add account switcher UI for caregivers"
```

### Task 13: Scope tab data fetches to `ActiveAccountContext`

**Files:**
- Modify: `DoseTrack/ViewModels/TodayViewModel.swift`
- Modify: `DoseTrack/ViewModels/MedicationsViewModel.swift`
- Modify: `DoseTrack/Views/History/HistoryView.swift` (and its view model if separate)

- [ ] **Step 1: Read each view model's current CoreData fetch to find the injection point**

Run: `grep -n "NSFetchRequest\|fetchRequest\|@FetchRequest" DoseTrack/ViewModels/TodayViewModel.swift DoseTrack/ViewModels/MedicationsViewModel.swift`

Since caregiver data is synced into a **separate local CoreData store per patient** (per the spec's data-flow section), the actual scoping mechanism is which `NSManagedObjectContext`/persistent store the fetch runs against, not a predicate on a shared store. This means `ActiveAccountContext` switching must also swap which `NSManagedObjectContext` is injected into the environment (`\.managedObjectContext`), pointing at either the user's own `PersistenceController` or a per-patient one.

- [ ] **Step 2: Add a per-patient CoreData store manager**

Add a method to `PersistenceController` (or a small new helper) that returns a distinct `NSManagedObjectContext` keyed by patient `userId`, backed by a separate SQLite file (e.g. `DoseTrack-caregiver-<userId>.sqlite` in the app group container). Reuse `PersistenceController.makeContainer`'s pattern (seen in `PersistenceController.swift:57-94`) but parameterize the store filename instead of hardcoding `"DoseTrack.sqlite"`.

- [ ] **Step 3: Wire `MainTabView` to inject the right context**

When `ActiveAccountContext.activeUserId` changes, `MainTabView` (or a wrapper view) re-injects `.environment(\.managedObjectContext, <context for activeUserId>)` and triggers a `SupabaseSyncManager.shared.pullAll(context:forUserId:)` call for that patient's context if it hasn't been synced recently.

- [ ] **Step 4: Manual verification**

Repeat the Task 12 Step 4 smoke test now that fetches are actually scoped — confirm switching accounts shows genuinely different medication lists sourced from each store.

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/App/PersistenceController.swift DoseTrack/App/MainTabView.swift
git commit -m "feat: scope CoreData context per active account for caregiver switching"
```

### Task 14: Missed-dose detection pure function + tests

**Files:**
- Create: `DoseTrack/Services/MissedDoseDetector.swift` (Swift port, used for any client-side preview/testing of the logic — the authoritative check runs server-side in Task 15, but the spec requires this logic be independently testable as a pure function)
- Test: `DoseTrackTests/MissedDoseDetectorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import DoseTrack

final class MissedDoseDetectorTests: XCTestCase {
    func test_dosePastSixtyMinutesWithNoLogIsOverdue() {
        let scheduledAt = Date().addingTimeInterval(-61 * 60)
        let result = MissedDoseDetector.overdueOccurrences(
            scheduledTimes: [scheduledAt], loggedTimes: [], now: Date()
        )
        XCTAssertEqual(result, [scheduledAt])
    }

    func test_doseWithMatchingLogIsNotOverdue() {
        let scheduledAt = Date().addingTimeInterval(-61 * 60)
        let result = MissedDoseDetector.overdueOccurrences(
            scheduledTimes: [scheduledAt], loggedTimes: [scheduledAt], now: Date()
        )
        XCTAssertTrue(result.isEmpty)
    }

    func test_doseUnderSixtyMinutesIsNotYetOverdue() {
        let scheduledAt = Date().addingTimeInterval(-30 * 60)
        let result = MissedDoseDetector.overdueOccurrences(
            scheduledTimes: [scheduledAt], loggedTimes: [], now: Date()
        )
        XCTAssertTrue(result.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator -only-testing:DoseTrackTests/MissedDoseDetectorTests 2>&1 | tail -30`
Expected: FAIL — `MissedDoseDetector` not defined.

- [ ] **Step 3: Implement**

```swift
// DoseTrack/Services/MissedDoseDetector.swift
import Foundation

/// Pure logic for deciding which scheduled doses count as "missed" for caregiver
/// alerting purposes. Mirrors the server-side Edge Function logic (Task 15) so it
/// can be unit tested without a live Supabase connection; the Edge Function is the
/// actual source of truth for production alerts.
enum MissedDoseDetector {
    static let overdueThreshold: TimeInterval = 60 * 60 // 60 minutes, per spec (sync-lag safety margin)

    static func overdueOccurrences(scheduledTimes: [Date], loggedTimes: [Date], now: Date) -> [Date] {
        let loggedSet = Set(loggedTimes)
        return scheduledTimes.filter { scheduled in
            !loggedSet.contains(scheduled) && now.timeIntervalSince(scheduled) >= overdueThreshold
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator -only-testing:DoseTrackTests/MissedDoseDetectorTests 2>&1 | tail -30`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/Services/MissedDoseDetector.swift DoseTrackTests/MissedDoseDetectorTests.swift
git commit -m "feat: add pure missed-dose detection logic with unit tests"
```

### Task 15: `missed-dose-alerts` cron Edge Function

**Files:** none (Supabase Edge Function + cron schedule, via MCP tools)

- [ ] **Step 1: Write the function**, mirroring `MissedDoseDetector`'s logic and the spec's sync-lag safety rule (60+ min threshold, skip if patient device synced within last 10 min with no log):

```typescript
// missed-dose-alerts/index.ts
import { createClient } from 'jsr:@supabase/supabase-js@2'

Deno.serve(async () => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const { data: relationships } = await supabase
    .from('caregiver_relationships')
    .select('caregiver_user_id, patient_user_id')
    .eq('status', 'active')

  for (const rel of relationships ?? []) {
    // Fetch this patient's schedules + recent dose_logs, compute overdue occurrences
    // using the same >=60min-since-due rule as MissedDoseDetector.overdueOccurrences.
    // For each overdue occurrence not already present in missed_dose_alerts
    // (unique on schedule_id+scheduled_date), insert a row and send an APNs push
    // to every device_push_tokens row for rel.caregiver_user_id.
    // (Full query/push implementation deferred to actual coding time — this
    // plan step's job is the schema/wiring; write the query against the real
    // schedules/dose_logs column names, which should be confirmed via
    // `execute_sql` describe queries before writing this function for real.)
  }

  return new Response('ok')
})
```

Before writing the real query logic, run `execute_sql` with `select column_name, data_type from information_schema.columns where table_name = 'schedules'` (and same for `dose_logs`) to get exact column names — do not guess them.

- [ ] **Step 2: Deploy** via `deploy_edge_function`.

- [ ] **Step 3: Schedule the cron trigger**

Supabase Edge Functions are triggered via `pg_cron` calling `net.http_post` against the function URL, or via the dashboard's Cron Jobs UI — use `apply_migration` to set up a `pg_cron` schedule (every 15 minutes) if the project has the `pg_cron` extension enabled (check via `list_extensions` MCP tool first).

- [ ] **Step 4: Manual verification**

Create a test caregiver relationship + an overdue schedule with no dose log, manually invoke the function (via its URL or the dashboard), and confirm a row appears in `missed_dose_alerts` and (if a real device token is registered) a push arrives.

### Task 16: Device push token registration

**Files:**
- Modify: `DoseTrack/App/AppDelegate.swift` (existing APNs registration, if any — check first)
- Modify: `DoseTrack/Services/CaregiverManager.swift` or a new small `PushTokenManager.swift`

- [ ] **Step 1: Check existing APNs setup**

Run: `grep -n "didRegisterForRemoteNotifications\|registerForRemoteNotifications" DoseTrack/App/AppDelegate.swift`
The app already requests notification permission (per `NotificationManager`) — confirm whether remote (APNs) registration is already wired for local notifications-only apps (it likely isn't, since local notifications don't need a device token). This is new for this feature.

- [ ] **Step 2: Add remote notification registration + token upload**

In `AppDelegate.swift`, add `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` that uploads the token via `client.from("device_push_tokens").upsert(...)`, and call `UIApplication.shared.registerForRemoteNotifications()` after existing local notification authorization succeeds (in `NotificationManager`).

- [ ] **Step 3: Manual verification**

On a real device (APNs tokens aren't available in simulator), confirm a row appears in `device_push_tokens` after granting notification permission.

- [ ] **Step 4: Commit**

```bash
git add DoseTrack/App/AppDelegate.swift
git commit -m "feat: register device for remote push, upload token for caregiver alerts"
```

### Task 17: Revocation handling — foreground re-validation and switcher cleanup

**Files:**
- Modify: `DoseTrack/App/MainTabView.swift` or `RootView.swift` (wherever scene-phase/foreground events are already observed — check first)
- Modify: `DoseTrack/Services/CaregiverManager.swift`

- [ ] **Step 1: Check existing scene phase handling**

Run: `grep -rn "scenePhase\|ScenePhase" DoseTrack/App/*.swift`

- [ ] **Step 2: Add a foreground hook that calls `CaregiverManager.refresh()` and validates the active account**

```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .active {
        Task {
            await caregiverManager.refresh()
            if activeAccount.isViewingOtherAccount,
               !caregiverManager.overseenPatients.contains(where: { $0.patientUserId == activeAccount.activeUserId }) {
                activeAccount.switchToOwnAccount()
                revocationMessage = "Your access to that account has ended."
            }
        }
    }
}
```

Surface `revocationMessage` as a simple alert/banner, following whatever alert pattern the app already uses elsewhere (check `SettingsView.swift` or `TodayView.swift` for an existing alert modifier pattern to match).

- [ ] **Step 3: Manual verification**

With two linked test accounts, revoke access from the patient side while the caregiver app is active in the foreground; background and re-foreground the caregiver's app; confirm it falls back to "My Account" with the message.

- [ ] **Step 4: Commit**

```bash
git add DoseTrack/App/MainTabView.swift DoseTrack/Services/CaregiverManager.swift
git commit -m "feat: re-validate caregiver access on foreground, handle revocation gracefully"
```

### Task 18: Remove dead CloudKit code path

**Files:**
- Modify: `DoseTrack/App/PersistenceController.swift` (remove `NSPersistentCloudKitContainer` branch, `cloudKitContainerOptions`, and the `isPro` container-switching logic — collapse to a single `NSPersistentContainer` path, since Task 13 already introduced a *different* multi-store mechanism for caregiver support that supersedes this)
- Modify: `DoseTrack/Views/Settings/SettingsView.swift` (confirm the disabled iCloud Sync toggle was already removed in Task 10 — if any residual CloudKit-related text remains, e.g. in the free-tier description string, update it)
- Modify: `DoseTrack/DoseTrack.entitlements` (remove the CloudKit/iCloud container entitlement if present)

- [ ] **Step 1: Read the current file fully before cutting anything**

Read `DoseTrack/App/PersistenceController.swift` in full (95 lines) to confirm exactly what's CloudKit-specific vs. shared logic that Task 13's per-patient store mechanism also depends on (e.g. `makeContainer`'s app-group `storeURL` logic must stay).

- [ ] **Step 2: Simplify to a single container path**

Remove the `isPro` branch and `NSPersistentCloudKitContainer`/`cloudKitContainerOptions` usage; keep `NSPersistentContainer` unconditionally, preserving the app-group store URL logic and the parameterized store filename added in Task 13.

- [ ] **Step 3: Check and clean entitlements**

Run: `grep -n "iCloud\|CloudKit" DoseTrack/Resources/DoseTrack.entitlements`
Remove the CloudKit container entry if present and not needed elsewhere.

- [ ] **Step 4: Build to confirm nothing else depends on the removed code**

Run: `xcodebuild -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator build 2>&1 | tail -40`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/App/PersistenceController.swift DoseTrack/Resources/DoseTrack.entitlements
git commit -m "refactor: remove unused CloudKit sync path, superseded by Supabase caregiver sync"
```

### Task 19: Full test suite + manual smoke test

**Files:** none (verification only)

- [ ] **Step 1: Run the full unit test suite**

Run: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator 2>&1 | tail -60`
Expected: all tests pass, including every new test added in Tasks 7, 8, 9, 14.

- [ ] **Step 2: End-to-end manual smoke test using two simulators or two accounts**

1. Create two test accounts (patient + caregiver) via the app's existing sign-up flow.
2. As the patient (with Pro enabled), generate a caregiver invite from Settings → Caregiver.
3. As the caregiver, accept via `xcrun simctl openurl` with the invite link (per Task 11 Step 5), or a manual code-entry fallback if built.
4. Confirm the caregiver's account switcher now shows the patient's account.
5. Switch to the patient's account; add a medication as the caregiver; confirm it appears when signed in as the patient directly (or via a second simulator).
6. Revoke access from the patient side; confirm the caregiver is kicked back to "My Account" on next foreground per Task 17.

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "test: verify caregiver sharing end-to-end"
```
