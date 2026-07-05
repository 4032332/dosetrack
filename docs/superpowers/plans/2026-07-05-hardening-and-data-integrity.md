# DoseTrack Hardening & Data-Integrity Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the data-integrity, notification-reliability, sync-robustness, and polish defects found in the 2026-07-05 code review so DoseTrack keeps its three core promises — correct data, reliable reminders, honest deletion — before any TestFlight build.

**Architecture:** Four sequential phases. Phase 1 introduces a single shared `DoseLoggingService` and threads the active-account user ID through every write path, eliminating the divergent logging/sync code and the caregiver-writes-under-wrong-user bug — and removes the HealthKit integration entirely (category misuse, low value, no Android counterpart) rather than fixing its disclosure. Phase 2 makes the notification engine reliable (preserve snoozes, sort the 64-cap, honor the critical-alerts toggle, actually arm background refresh). Phase 3 adds `updated_at`-based conflict resolution, incremental pulls, and an unsynced-record sweep. Phase 4 is polish (PDF pagination, widget identity, save-error reporting, secrets template). Each phase produces a shippable, testable increment on its own.

**Tech Stack:** Swift 5.9 / SwiftUI, Core Data (App Group shared store + per-patient stores), Supabase (Postgres + RLS + Edge Functions), StoreKit 2, WidgetKit (AppIntent), UserNotifications, XcodeGen (`xcodegen generate` after any new file), XCTest.

**Conventions for every task in this plan:**
- Worktree: `/Users/robbrown/CodingProjects/Apps/dosetrack-caregiver`, branch `caregiver-sharing`.
- After creating/deleting ANY `.swift` file, run `xcodegen generate` before building.
- Build check: `xcodebuild -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build` → expect `** BUILD SUCCEEDED **`.
- Test check: `xcodebuild -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test` → expect `Executed N tests, with 0 failures`. Baseline is 93 tests passing.
- Commit message trailer: `Co-Authored-By: Claude <noreply@anthropic.com>`.
- Follow superpowers:test-driven-development: write the failing test first, watch it fail, implement, watch it pass, commit.
- Core Data entities use `codeGenerationType="category"` — the base classes live in `DoseTrack/Models/*+CoreDataClass.swift`. Any new target that touches the model needs those three files (already done for the widget).

**Supabase note:** Several tasks add columns/functions to the hosted Supabase project (ref `ttosaeghpxhhzlvwlqnm`). Use the Supabase MCP `apply_migration` tool. Each such task calls it out explicitly. Local Swift changes and remote migrations must ship together or the app breaks.

---

## Chunk 1: Phase 1 — Data Integrity (Critical)

This phase eliminates the four critical findings: divergent dose-logging paths (#8), caregiver writes under the wrong user ID (#1), soft-delete resurrection (#2), Delete-All-Data not deleting cloud/notifications (#3), and cross-account local-store leakage (#4). It also folds in the stale supply decrement (#9), because the fix lives in the new shared logging service.

### File Structure (Phase 1)

- **Create** `DoseTrack/Services/DoseLoggingService.swift` — the single source of truth for writing a `DoseLog`. Owns: upsert the log, decrement supply by per-dose quantity on a taken transition, push to Supabase under the correct user ID, reload widgets. No HealthKit call — that integration is removed as part of this phase (see Task 1.10) rather than carried forward. Used by `TodayViewModel`, `AppDelegate`, and (via a thin sync entry point) anywhere else.
- **Create** `DoseTrack/Services/ActiveAccountResolver.swift` — a tiny `@MainActor` singleton holding the currently-viewed user ID (`nil` = own account). `RootView`/`ActiveSessionView` sets it on account switch; non-View code (`AppDelegate`, `DoseLoggingService`) reads it. This avoids threading `ActiveAccountContext` (a SwiftUI `EnvironmentObject`) into UIKit/service code.
- **Modify** `DoseTrack/ViewModels/TodayViewModel.swift` — delegate `markTaken`/`markSkipped` to `DoseLoggingService`; delete the local `log(...)` body.
- **Modify** `DoseTrack/App/AppDelegate.swift` — `logDose(...)` delegates to `DoseLoggingService`.
- **Modify** `DoseTrack/ViewModels/AddEditMedicationViewModel.swift` — push medication under active user ID; add per-dose `quantityPerDose` persistence for the decrement.
- **Modify** `DoseTrack/ViewModels/MedicationsViewModel.swift` + `DoseTrack/Views/Medications/MedicationDetailView.swift` — push `isActive=false` on soft delete.
- **Modify** `DoseTrack/Services/SupabaseSyncManager.swift` — respect a tombstone in `mergeMedications` (don't resurrect); add `deleteAllRemoteData()`.
- **Modify** `DoseTrack/Views/Settings/SettingsView.swift` — `deleteAllData()` also deletes remote, cancels notifications, reloads widgets, merges batch-delete into context.
- **Modify** `DoseTrack/Services/AuthManager.swift` — wipe the local store on sign-out.
- **Modify** `DoseTrack/App/RootView.swift` — set `ActiveAccountResolver` on account switch.
- **Test** `DoseTrackTests/DoseLoggingServiceTests.swift`, `DoseTrackTests/SyncMergeTests.swift` (new).

---

### Task 1.1: ActiveAccountResolver — a non-SwiftUI home for "who am I acting as"

**Files:**
- Create: `DoseTrack/Services/ActiveAccountResolver.swift`
- Modify: `DoseTrack/App/RootView.swift` (inside `ActiveSessionView.onChange(of: activeAccount.activeUserId)` and `.onAppear`)
- Test: `DoseTrackTests/ActiveAccountResolverTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// DoseTrackTests/ActiveAccountResolverTests.swift
import XCTest
@testable import DoseTrack

@MainActor
final class ActiveAccountResolverTests: XCTestCase {
    func test_defaultsToNil_meaningOwnAccount() {
        let sut = ActiveAccountResolver()
        XCTAssertNil(sut.activeUserId)
    }

    func test_setAndReadBack() {
        let sut = ActiveAccountResolver()
        let id = UUID()
        sut.set(activeUserId: id)
        XCTAssertEqual(sut.activeUserId, id)
    }

    func test_clearReturnsToOwnAccount() {
        let sut = ActiveAccountResolver()
        sut.set(activeUserId: UUID())
        sut.set(activeUserId: nil)
        XCTAssertNil(sut.activeUserId)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test` — Expected: FAIL, "cannot find 'ActiveAccountResolver' in scope".

- [ ] **Step 3: Write minimal implementation**

```swift
// DoseTrack/Services/ActiveAccountResolver.swift
import Foundation

/// Non-SwiftUI-scoped holder for "whose account is the UI currently acting on".
/// `nil` means the signed-in user's own account. `ActiveAccountContext` (a SwiftUI
/// EnvironmentObject) drives the UI; this mirror lets service/UIKit code — AppDelegate's
/// notification-action handler, DoseLoggingService — resolve the same value without an
/// environment. RootView keeps the two in sync on every account switch.
@MainActor
final class ActiveAccountResolver: ObservableObject {
    static let shared = ActiveAccountResolver()

    /// `nil` = own account; otherwise the overseen patient's userId.
    private(set) var activeUserId: UUID?

    func set(activeUserId: UUID?) {
        self.activeUserId = activeUserId
    }
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 5: Wire RootView to keep the resolver in sync**

In `DoseTrack/App/RootView.swift`, inside `ActiveSessionView`, update the account-switch handler and add an appear handler so the resolver always reflects the active account:

```swift
// In ActiveSessionView.body, on the MainTabView():
.onChange(of: activeAccount.activeUserId) { _, newUserId in
    let resolvedId: UUID? = (newUserId == activeAccount.ownUserId) ? nil : newUserId
    ActiveAccountResolver.shared.set(activeUserId: resolvedId)
    guard newUserId != activeAccount.ownUserId else { return }
    let patientContext = PersistenceController.shared.context(forPatient: newUserId)
    Task {
        await SupabaseSyncManager.shared.pullAll(context: patientContext, forUserId: newUserId)
    }
}
.onAppear {
    // existing onAppear body stays; add this line so the resolver is correct on first mount:
    ActiveAccountResolver.shared.set(
        activeUserId: activeAccount.isViewingOtherAccount ? activeAccount.activeUserId : nil
    )
    // ... existing watchManager.syncTodayMedications + pullAll ...
}
```

- [ ] **Step 6: Run `xcodegen generate`, build, test** — Expected: BUILD SUCCEEDED, 96 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add DoseTrack/Services/ActiveAccountResolver.swift DoseTrack/App/RootView.swift DoseTrackTests/ActiveAccountResolverTests.swift DoseTrack.xcodeproj/project.pbxproj
git commit -m "Add ActiveAccountResolver so non-SwiftUI code can resolve the active account"
```

---

### Task 1.2: Persist per-dose quantity for correct supply decrement

The medication currently stores `totalDosesPerDay = quantityPerDose × enabledScheduleCount`. To decrement correctly per taken dose we need `quantityPerDose` alone. Derive it as `totalDosesPerDay / enabledScheduleCount` at log time (no schema change needed), and unit-test that derivation as a pure function.

**Files:**
- Create: `DoseTrack/Services/SupplyMath.swift` (pure functions, unit-testable)
- Test: `DoseTrackTests/SupplyMathTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// DoseTrackTests/SupplyMathTests.swift
import XCTest
@testable import DoseTrack

final class SupplyMathTests: XCTestCase {
    func test_quantityPerDose_dividesTotalByScheduleCount() {
        // 2 tablets, 4x/day => totalDosesPerDay 8, 4 schedules => 2 per dose
        XCTAssertEqual(SupplyMath.quantityPerDose(totalDosesPerDay: 8, enabledScheduleCount: 4), 2)
    }
    func test_quantityPerDose_flooredAtOne_whenScheduleCountZero() {
        XCTAssertEqual(SupplyMath.quantityPerDose(totalDosesPerDay: 0, enabledScheduleCount: 0), 1)
    }
    func test_quantityPerDose_roundsDownButNeverBelowOne() {
        XCTAssertEqual(SupplyMath.quantityPerDose(totalDosesPerDay: 3, enabledScheduleCount: 2), 1)
    }
    func test_decrement_neverBelowZero() {
        XCTAssertEqual(SupplyMath.decrementedCount(current: 1, by: 2), 0)
    }
}
```

- [ ] **Step 2: Run test — Expected: FAIL** (no `SupplyMath`).

- [ ] **Step 3: Implement**

```swift
// DoseTrack/Services/SupplyMath.swift
import Foundation

enum SupplyMath {
    /// Units consumed by a single dose = daily consumption ÷ how many times a day it's taken.
    /// Never below 1 (a dose always consumes at least one unit).
    static func quantityPerDose(totalDosesPerDay: Int, enabledScheduleCount: Int) -> Int {
        guard enabledScheduleCount > 0 else { return max(totalDosesPerDay, 1) }
        return max(totalDosesPerDay / enabledScheduleCount, 1)
    }

    static func decrementedCount(current: Int, by amount: Int) -> Int {
        max(0, current - amount)
    }
}
```

- [ ] **Step 4: Run test — Expected: PASS.**

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/Services/SupplyMath.swift DoseTrackTests/SupplyMathTests.swift DoseTrack.xcodeproj/project.pbxproj
git commit -m "Add SupplyMath pure functions for per-dose supply decrement"
```

---

### Task 1.3: DoseLoggingService — one write path for all dose logging

Consolidates the two divergent code paths (`TodayViewModel.log` and `AppDelegate.logDose`) so every "mark taken/skipped" — from Today screen, notification action, or widget — has identical side effects: upsert log, decrement supply (taken only, per-dose quantity, on a fresh taken transition), push to Supabase under the resolved user ID, reload widgets. (No HealthKit call — see Task 1.10, which removes that integration in this same phase.)

**Files:**
- Create: `DoseTrack/Services/DoseLoggingService.swift`
- Test: `DoseTrackTests/DoseLoggingServiceTests.swift`

- [ ] **Step 1: Write the failing test** (uses in-memory store from `PersistenceController.preview` pattern)

```swift
// DoseTrackTests/DoseLoggingServiceTests.swift
import XCTest
import CoreData
@testable import DoseTrack

@MainActor
final class DoseLoggingServiceTests: XCTestCase {
    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).viewContext
    }

    func test_markTaken_createsLogWithTakenStatus() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "Metformin", dosage: "500mg")
        med.totalDosesPerDay = 2
        let sched = Schedule.create(in: ctx, medication: med, hour: 8, minute: 0)
        let at = Date()
        DoseLoggingService.shared.log(
            medication: med, schedule: sched, scheduledAt: at,
            status: .taken, existingLog: nil, notes: nil, context: ctx, pushUserId: nil
        )
        let logs = (try? ctx.fetch(DoseLog.fetchRequest())) ?? []
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.status, "taken")
    }

    func test_markTaken_decrementsSupplyByPerDoseQuantity() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "Metformin", dosage: "500mg")
        med.currentCount = 10
        med.totalDosesPerDay = 4            // 2 schedules => 2 per dose
        let s1 = Schedule.create(in: ctx, medication: med, hour: 8, minute: 0)
        _ = Schedule.create(in: ctx, medication: med, hour: 20, minute: 0)
        DoseLoggingService.shared.log(
            medication: med, schedule: s1, scheduledAt: Date(),
            status: .taken, existingLog: nil, notes: nil, context: ctx, pushUserId: nil
        )
        XCTAssertEqual(med.currentCount, 8)  // 10 - 2
    }

    func test_markSkipped_doesNotDecrementSupply() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "M", dosage: "1")
        med.currentCount = 5
        let s = Schedule.create(in: ctx, medication: med, hour: 8, minute: 0)
        DoseLoggingService.shared.log(
            medication: med, schedule: s, scheduledAt: Date(),
            status: .skipped, existingLog: nil, notes: "nausea", context: ctx, pushUserId: nil
        )
        XCTAssertEqual(med.currentCount, 5)
    }

    func test_reTakingExistingTakenLog_doesNotDoubleDecrement() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "M", dosage: "1")
        med.currentCount = 5
        med.totalDosesPerDay = 1
        let s = Schedule.create(in: ctx, medication: med, hour: 8, minute: 0)
        let at = Date()
        let existing = DoseLog.create(in: ctx, medication: med, scheduledAt: at, status: .taken)
        DoseLoggingService.shared.log(
            medication: med, schedule: s, scheduledAt: at,
            status: .taken, existingLog: existing, notes: nil, context: ctx, pushUserId: nil
        )
        XCTAssertEqual(med.currentCount, 5) // already taken => no further decrement
    }

    func test_skipReason_storedInNotes() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "M", dosage: "1")
        let s = Schedule.create(in: ctx, medication: med, hour: 8, minute: 0)
        DoseLoggingService.shared.log(
            medication: med, schedule: s, scheduledAt: Date(),
            status: .skipped, existingLog: nil, notes: "away", context: ctx, pushUserId: nil
        )
        let log = (try? ctx.fetch(DoseLog.fetchRequest()))?.first
        XCTAssertEqual(log?.notes, "away")
    }
}
```

- [ ] **Step 2: Run test — Expected: FAIL** (no `DoseLoggingService`).

- [ ] **Step 3: Implement**

```swift
// DoseTrack/Services/DoseLoggingService.swift
import CoreData
import WidgetKit

/// The single write path for logging a dose (taken / skipped / missed). Every caller —
/// TodayViewModel, AppDelegate's notification-action handler, the widget intent bridge —
/// goes through here so side effects (supply decrement, Supabase push, widget reload) are
/// identical no matter how a dose is logged. Previously TodayViewModel and AppDelegate had
/// separate, divergent implementations; that drift is the bug this fixes.
@MainActor
final class DoseLoggingService {
    static let shared = DoseLoggingService()
    private init() {}

    /// - Parameter pushUserId: which Supabase user this write belongs to. `nil` = the
    ///   signed-in user's own account. A caregiver acting on a patient MUST pass the
    ///   patient's id (resolve via ActiveAccountResolver at the call site) or the row
    ///   uploads under the wrong user.
    func log(
        medication: Medication,
        schedule: Schedule,
        scheduledAt: Date,
        status: DoseStatus,
        existingLog: DoseLog?,
        notes: String?,
        context: NSManagedObjectContext,
        pushUserId: UUID?
    ) {
        let wasAlreadyTaken = existingLog?.status == DoseStatus.taken.rawValue

        let doseLog: DoseLog
        if let existing = existingLog {
            existing.status = status.rawValue
            existing.loggedAt = Date()
            if let notes { existing.notes = notes }
            doseLog = existing
        } else {
            doseLog = DoseLog.create(in: context, medication: medication, scheduledAt: scheduledAt, status: status)
            if let notes { doseLog.notes = notes }
        }

        // Decrement supply only on a fresh not-taken -> taken transition.
        if status == .taken && !wasAlreadyTaken && medication.currentCount > 0 {
            let scheduleCount = medication.schedulesArray.filter { $0.isEnabled }.count
            let perDose = SupplyMath.quantityPerDose(
                totalDosesPerDay: Int(medication.totalDosesPerDay),
                enabledScheduleCount: scheduleCount
            )
            medication.currentCount = Int32(SupplyMath.decrementedCount(current: Int(medication.currentCount), by: perDose))
        }

        do { try context.save() } catch { assertionFailure("DoseLoggingService save failed: \(error)") }

        WidgetCenter.shared.reloadAllTimelines()
        Task { await SupabaseSyncManager.shared.pushDoseLog(doseLog, forUserId: pushUserId) }
    }
}
```

- [ ] **Step 4: Run test — Expected: PASS (5 new).**

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/Services/DoseLoggingService.swift DoseTrackTests/DoseLoggingServiceTests.swift DoseTrack.xcodeproj/project.pbxproj
git commit -m "Add DoseLoggingService as the single dose-write path with correct supply decrement"
```

---

### Task 1.4: Route TodayViewModel through DoseLoggingService

**Files:**
- Modify: `DoseTrack/ViewModels/TodayViewModel.swift` (replace `markTaken`, `markSkipped`, and the private `log(...)`)

- [ ] **Step 1: Update the two public methods + delete the private `log`**

Replace `markTaken`, `markSkipped`, and the whole private `log(entry:status:notes:)` with:

```swift
func markTaken(_ entry: DoseEntry) {
    DoseLoggingService.shared.log(
        medication: entry.medication, schedule: entry.schedule, scheduledAt: entry.scheduledAt,
        status: .taken, existingLog: entry.existingLog, notes: nil,
        context: context, pushUserId: ActiveAccountResolver.shared.activeUserId
    )
    // Celebration hook preserved: recompute + pulse if the last dose is now taken.
    refresh()
    if totalCount > 0 && takenCount == totalCount { celebrateNow = true }
}

func markSkipped(_ entry: DoseEntry, reason: String? = nil) {
    DoseLoggingService.shared.log(
        medication: entry.medication, schedule: entry.schedule, scheduledAt: entry.scheduledAt,
        status: .skipped, existingLog: entry.existingLog, notes: reason,
        context: context, pushUserId: ActiveAccountResolver.shared.activeUserId
    )
    refresh()
}
```

> NOTE for implementer: confirm the exact pre-existing celebration mechanism (`celebrateNow` pulse) before this change and preserve its behavior. If `refresh()` already sets `celebrateNow`, do not double-set it. Read the current `log(...)` body first.

- [ ] **Step 2: Build + run full test suite** — Expected: BUILD SUCCEEDED, all tests pass (the existing `TodayViewModelTests` for `markTaken`/`markSkipped` must still pass — if they assert supply behavior, adjust only if the assertion was wrong).

- [ ] **Step 3: Commit**

```bash
git add DoseTrack/ViewModels/TodayViewModel.swift
git commit -m "Route TodayViewModel dose logging through DoseLoggingService"
```

---

### Task 1.5: Route AppDelegate notification actions through DoseLoggingService

The notification-action handler runs outside SwiftUI. It must resolve the active account from `ActiveAccountResolver` and use the matching context (own store vs. patient store).

**Files:**
- Modify: `DoseTrack/App/AppDelegate.swift` (`logDose(...)`)

- [ ] **Step 1: Rewrite `logDose` to delegate**

```swift
private func logDose(medicationId: UUID, scheduledAt: Date, status: String, context ignored: NSManagedObjectContext) {
    Task { @MainActor in
        let activeId = ActiveAccountResolver.shared.activeUserId
        let context = activeId == nil
            ? PersistenceController.shared.viewContext
            : PersistenceController.shared.context(forPatient: activeId!)

        let req = NSFetchRequest<Medication>(entityName: "Medication")
        req.predicate = NSPredicate(format: "id == %@", medicationId as CVarArg)
        req.fetchLimit = 1
        guard let medication = try? context.fetch(req).first else { return }

        let logReq = NSFetchRequest<DoseLog>(entityName: "DoseLog")
        logReq.predicate = NSPredicate(format: "medication == %@ AND scheduledAt == %@", medication, scheduledAt as NSDate)
        logReq.fetchLimit = 1
        let existing = try? context.fetch(logReq).first

        // Find the schedule matching this dose so supply math has the right schedule set.
        let schedule = medication.schedulesArray.first { $0.isEnabled } ?? medication.schedulesArray.first
        guard let schedule else { return }

        DoseLoggingService.shared.log(
            medication: medication, schedule: schedule, scheduledAt: scheduledAt,
            status: DoseStatus(rawValue: status) ?? .taken, existingLog: existing, notes: nil,
            context: context, pushUserId: activeId
        )
    }
}
```

> NOTE: this changes `logDose` from synchronous `context.perform` to `@MainActor Task`. Confirm `DoseStatus(rawValue:)` exists; if `DoseStatus` is not `RawRepresentable` by `String`, map manually.

- [ ] **Step 2: Build + test** — Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add DoseTrack/App/AppDelegate.swift
git commit -m "Route notification-action dose logging through DoseLoggingService (correct account + side effects)"
```

---

### Task 1.6: Push medication edits under the active account

**Files:**
- Modify: `DoseTrack/ViewModels/AddEditMedicationViewModel.swift` (the `pushMedication` call site around line 192)

- [ ] **Step 1: Thread the active user id into the push**

Change:
```swift
await SupabaseSyncManager.shared.pushMedication(medCopy)
```
to:
```swift
await SupabaseSyncManager.shared.pushMedication(medCopy, forUserId: ActiveAccountResolver.shared.activeUserId)
```

> The `save()` runs on a `@MainActor` context; reading `ActiveAccountResolver.shared.activeUserId` must also be on the main actor. If the push is inside a detached `Task`, capture the id before the Task: `let pushId = ActiveAccountResolver.shared.activeUserId` then use `pushId`.

- [ ] **Step 2: Build + test** — Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add DoseTrack/ViewModels/AddEditMedicationViewModel.swift
git commit -m "Push medication edits under the active account's user id, not the caregiver's"
```

---

### Task 1.7: Soft delete must push the tombstone; merge must not resurrect it

Two halves: (a) push `isActive=false` after every soft delete; (b) make `mergeMedications` never flip a locally-inactive med back to active from a stale remote row. Because Phase 3 adds `updated_at`, this task uses the simpler interim rule: **a remote row never reactivates a locally-soft-deleted medication.**

**Files:**
- Modify: `DoseTrack/ViewModels/MedicationsViewModel.swift` (`confirmSoftDelete`)
- Modify: `DoseTrack/Views/Medications/MedicationDetailView.swift` (`softDeleteAndDismiss`)
- Modify: `DoseTrack/Services/SupabaseSyncManager.swift` (`mergeMedications`)
- Test: `DoseTrackTests/SyncMergeTests.swift`

- [ ] **Step 1: Write the failing merge test**

```swift
// DoseTrackTests/SyncMergeTests.swift
import XCTest
import CoreData
@testable import DoseTrack

@MainActor
final class SyncMergeTests: XCTestCase {
    func test_merge_doesNotResurrectLocallyDeactivatedMedication() {
        let ctx = PersistenceController(inMemory: true).viewContext
        let id = UUID()
        let med = Medication(context: ctx)
        med.id = id; med.name = "Old"; med.dosage = "1"; med.unit = "pill"
        med.colorHex = "#000000"; med.isActive = false   // locally soft-deleted
        try? ctx.save()

        // Remote row still says active (row predates the delete reaching the server).
        let row = MedicationRow.testRow(id: id.uuidString, isActive: true)
        SupabaseSyncManager.shared.mergeMedicationsForTesting([row], context: ctx)

        let fetched = (try? ctx.fetch(Medication.fetchRequest()))?.first
        XCTAssertEqual(fetched?.isActive, false, "a locally-deactivated med must not be resurrected by a stale remote row")
    }
}
```

> Implementer: add a `static func testRow(id:isActive:)` factory to `MedicationRow` guarded by `#if DEBUG`, and a `func mergeMedicationsForTesting(_:context:)` `#if DEBUG` shim that calls the private `mergeMedications`. Keep production API private.

- [ ] **Step 2: Run — Expected: FAIL** (currently overwrites `isActive`).

- [ ] **Step 3: Fix `mergeMedications`**

In the merge loop, replace `med.isActive = row.isActive` with:

```swift
// Never let a stale remote row reactivate a medication we've locally soft-deleted.
// (Phase 3 replaces this with an updated_at comparison.) A remote row CAN deactivate.
if !(existing != nil && existing!.isActive == false && row.isActive == true) {
    med.isActive = row.isActive
}
```

- [ ] **Step 4: Run — Expected: PASS.**

- [ ] **Step 5: Push the tombstone on soft delete**

In `MedicationsViewModel.confirmSoftDelete()`, after `med.isActive = false; try? context.save()`:

```swift
let pushId = ActiveAccountResolver.shared.activeUserId
if let med = medicationToDelete ?? nil { /* capture id before nil-out */ }
let medId = medForDeleteId // capture med.id before mutating state
Task { await SupabaseSyncManager.shared.pushMedication(med, forUserId: pushId) }
```

> Implementer: capture the `Medication` reference and `activeUserId` BEFORE clearing `medicationToDelete`. Simplest: push inside the same method right after save, before resetting `medicationToDelete = nil`. Do the equivalent in `MedicationDetailView.softDeleteAndDismiss()` (capture `medication` + resolver id, push, then dismiss).

- [ ] **Step 6: Build + test** — Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add DoseTrack/ViewModels/MedicationsViewModel.swift DoseTrack/Views/Medications/MedicationDetailView.swift DoseTrack/Services/SupabaseSyncManager.swift DoseTrackTests/SyncMergeTests.swift
git commit -m "Push soft-delete tombstone and stop stale remote rows resurrecting deleted meds"
```

---

### Task 1.8: Delete All Data must delete cloud data, cancel notifications, reload widgets

**Files:**
- Modify: `DoseTrack/Services/SupabaseSyncManager.swift` (add `deleteAllRemoteData()`)
- Modify: `DoseTrack/Views/Settings/SettingsView.swift` (`deleteAllData()`)

- [ ] **Step 1: Add `deleteAllRemoteData()` to SupabaseSyncManager**

```swift
/// Deletes all of the signed-in user's rows from Supabase. Best-effort; guarded so guests
/// (no server data) and unauth'd states are no-ops.
func deleteAllRemoteData() async {
    guard AuthManager.shared.isSignedIn, !AuthManager.shared.isGuest,
          let userId = AuthManager.shared.session?.user.id else { return }
    let uid = userId.uuidString
    for table in ["dose_logs", "schedules", "medications"] {
        do { try await client.from(table).delete().eq("user_id", value: uid).execute() }
        catch { print("deleteAllRemoteData(\(table)) error: \(error)") }
    }
}
```

- [ ] **Step 2: Rewrite `SettingsView.deleteAllData()`**

```swift
private func deleteAllData() {
    // Local batch delete, then merge the changes into the live context so the UI updates
    // without a relaunch (NSBatchDeleteRequest bypasses the context by default).
    for entity in ["DoseLog", "Schedule", "Medication"] {
        let req: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: entity)
        let del = NSBatchDeleteRequest(fetchRequest: req)
        del.resultType = .resultTypeObjectIDs
        if let result = try? context.execute(del) as? NSBatchDeleteResult,
           let ids = result.result as? [NSManagedObjectID] {
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: ids], into: [context])
        }
    }
    try? context.save()

    // Cancel all scheduled reminders and refresh widgets so nothing points at deleted data.
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    WidgetCenter.shared.reloadAllTimelines()

    // Delete the cloud copy too, or the next pullAll restores everything.
    Task { await SupabaseSyncManager.shared.deleteAllRemoteData() }
}
```

> Add `import UserNotifications` and `import WidgetKit` to SettingsView if not present.

- [ ] **Step 3: Build + test** — Expected: pass.

- [ ] **Step 4: Manual verification (document, don't automate):** on the sim — add meds, Delete All Data, force-quit, relaunch → list stays empty; check no pending notifications via a debug print or Xcode.

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/Services/SupabaseSyncManager.swift DoseTrack/Views/Settings/SettingsView.swift
git commit -m "Delete All Data now deletes cloud data, cancels notifications, and refreshes widgets"
```

---

### Task 1.9: Wipe the local store on sign-out to prevent cross-account leakage

Sign out currently leaves the previous user's medications in the shared store; a subsequent different sign-in sees them and re-uploads under the new user. Wipe on sign-out.

**Files:**
- Modify: `DoseTrack/App/PersistenceController.swift` (add `wipeLocalStore()`)
- Modify: `DoseTrack/Services/AuthManager.swift` (`signOut`)

- [ ] **Step 1: Add `wipeLocalStore()` to PersistenceController**

```swift
/// Removes all locally-stored data from the main store. Called on sign-out so a different
/// user signing in on the same device never sees (or re-uploads) the previous user's data.
func wipeLocalStore() {
    let ctx = container.viewContext
    for entity in ["DoseLog", "Schedule", "Medication"] {
        let req: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: entity)
        let del = NSBatchDeleteRequest(fetchRequest: req)
        del.resultType = .resultTypeObjectIDs
        if let result = try? ctx.execute(del) as? NSBatchDeleteResult,
           let ids = result.result as? [NSManagedObjectID] {
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: ids], into: [ctx])
        }
    }
    try? ctx.save()
    // Also drop cached per-patient stores so a former caregiver's patient data doesn't linger.
    patientContainers.removeAll()
}
```

> `patientContainers` is currently `private`. Keep it private; `wipeLocalStore` is a method on the same type, so it can clear it directly.

- [ ] **Step 2: Call it from `AuthManager.signOut()`** (read the method first; add after the Supabase sign-out succeeds, before clearing local session):

```swift
PersistenceController.shared.wipeLocalStore()
UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
WidgetCenter.shared.reloadAllTimelines()
```

> Add imports as needed. Ensure `hasCompletedOnboarding`/`guestMode` handling is unaffected — read the existing `signOut` first and integrate, don't blindly prepend.

- [ ] **Step 3: Build + test** — Expected: pass.

- [ ] **Step 4: Manual verification:** sign in as A, add med, sign out, sign in as B → B sees no meds.

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/App/PersistenceController.swift DoseTrack/Services/AuthManager.swift
git commit -m "Wipe local store on sign-out to prevent cross-account medical-data leakage"
```

---

### Task 1.10: Remove the HealthKit integration entirely

**Decision:** removed, not disclosed-and-kept. Logging doses as "mindfulness sessions" is a category misuse with no clean HK type to fall back to, it adds negligible value over the app's own History/export (which is the trustworthy source of truth), and it's a maintenance liability with no Android counterpart on the roadmap. Cheaper to delete now, before Task 1.3's `DoseLoggingService` carries the pattern forward, than to delete later once real users have HK data written under the mindfulness mislabel.

**Files:**
- Delete: `DoseTrack/Services/HealthKitManager.swift`
- Modify: `DoseTrack/Views/Settings/AppPreferencesView.swift` — remove the "Apple Health" section (`healthKitEnabled` AppStorage, the `@StateObject private var healthKit`, and the whole `if healthKit.isAvailable { Section { ... } }` block).
- Modify: `DoseTrack/Resources/Info.plist` — remove `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`.
- Modify: `DoseTrack/Resources/DoseTrack.entitlements` — remove `com.apple.developer.healthkit` / `com.apple.developer.healthkit.access`.
- Modify: `project.yml` — remove the `com.apple.developer.healthkit` / `com.apple.developer.healthkit.access` entitlement properties, remove `- sdk: HealthKit.framework` from the DoseTrack target's dependencies. Leave `Vision.framework` alone (used by the medication label scanner, unrelated).

- [ ] **Step 1: Remove Settings UI** — delete the `healthKitEnabled` AppStorage property, the `healthKit` StateObject, and the entire `if healthKit.isAvailable { Section { ... } }` block from `AppPreferencesView.swift`.

- [ ] **Step 2: Delete the service file**

```bash
rm DoseTrack/Services/HealthKitManager.swift
```

- [ ] **Step 3: Strip entitlements and Info.plist**

Remove from `DoseTrack/Resources/DoseTrack.entitlements`:
```xml
<key>com.apple.developer.healthkit</key>
<true/>
<key>com.apple.developer.healthkit.access</key>
<array/>
```
Remove from `DoseTrack/Resources/Info.plist`:
```xml
<key>NSHealthShareUsageDescription</key>
<string>...</string>
<key>NSHealthUpdateUsageDescription</key>
<string>...</string>
```

- [ ] **Step 4: Strip project.yml**

Remove `com.apple.developer.healthkit: true` and `com.apple.developer.healthkit.access: []` from the `DoseTrack` target's `entitlements.properties`, and remove `- sdk: HealthKit.framework` from its `dependencies`. Keep `- sdk: Vision.framework`.

- [ ] **Step 5: `xcodegen generate`, build, test** — Expected: BUILD SUCCEEDED, full suite passes with 0 failures (no HealthKit-specific tests should exist to remove; if any do, delete them too).

- [ ] **Step 6: Manual check:** Settings > App Preferences no longer shows an "Apple Health" section.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Remove HealthKit integration entirely (category misuse, low value, no Android counterpart)"
```

---

### Phase 1 checkpoint

- [ ] Run full suite: expect ≥ 101 tests, 0 failures.
- [ ] Reinstall on the iPhone 17 Pro Max sim and smoke test: mark taken from Today, from a delivered notification, and via widget → all decrement supply identically and appear in History; caregiver-mode preview write lands in patient context.

---

## Chunk 2: Phase 2 — Notification Reliability (High)

Fixes: snooze destruction on foreground (#5), unsorted 64-cap (#6), critical-alerts toggle ignored + hardcoded critical sound (#7), background refresh never armed (low/#process). No Supabase changes.

### File Structure (Phase 2)

- **Modify** `DoseTrack/Services/NotificationScheduler.swift` — targeted cancellation, global fire-date sort before the 64 cap, honor `criticalAlertsEnabled`, set `interruptionLevel`.
- **Modify** `DoseTrack/App/AppDelegate.swift` — arm `scheduleBackgroundRefresh()` at launch; add `expirationHandler`; do BG work on a background context.
- **Test** `DoseTrackTests/NotificationSchedulerTests.swift` (extend).

---

### Task 2.1: Preserve snoozes — cancel only `dt.`-prefixed requests

**Files:**
- Modify: `DoseTrack/Services/NotificationScheduler.swift` (`refreshAll`)
- Test: `DoseTrackTests/NotificationSchedulerTests.swift`

- [ ] **Step 1: Write a failing test that verifies snooze requests survive a refresh**

Because `UNUserNotificationCenter` is hard to unit-test directly, extract the cancellation predicate into a pure helper and test that:

```swift
func test_identifiersToCancel_keepsSnoozes_removesScheduled() {
    let all = ["dt.med.sch.123", "snooze.med.abc", "dt.interval.due.x.9"]
    let toCancel = NotificationScheduler.identifiersToCancel(from: all)
    XCTAssertEqual(Set(toCancel), Set(["dt.med.sch.123", "dt.interval.due.x.9"]))
    XCTAssertFalse(toCancel.contains("snooze.med.abc"))
}
```

- [ ] **Step 2: Run — Expected: FAIL** (no `identifiersToCancel`).

- [ ] **Step 3: Implement + use it**

Add:
```swift
/// Scheduled reminders are namespaced `dt.*`; one-off snoozes are `snooze.*`. A full refresh
/// must rebuild the former without destroying the latter (snoozes aren't rebuilt).
static func identifiersToCancel(from pending: [String]) -> [String] {
    pending.filter { $0.hasPrefix("dt.") }
}
```
In `refreshAll`, replace `center.removeAllPendingNotificationRequests()` with:
```swift
center.getPendingNotificationRequests { requests in
    let ids = Self.identifiersToCancel(from: requests.map(\.identifier))
    self.center.removePendingNotificationRequests(withIdentifiers: ids)
    self.buildAndAddRequests(medications: medications, now: now, horizon: horizon, calendar: calendar)
}
```

> Implementer: extract the request-building + add loop (current lines ~36–68) into a private `buildAndAddRequests(...)` so it can run inside the async completion. Move the `UserDefaults` lastRefresh write to the end of that method.

- [ ] **Step 4: Run — Expected: PASS.** Build + full suite pass.

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/Services/NotificationScheduler.swift DoseTrackTests/NotificationSchedulerTests.swift
git commit -m "Preserve snoozed reminders across notification refresh (cancel only dt.* requests)"
```

---

### Task 2.2: Sort all built requests by fire date before applying the 64 cap

**Files:**
- Modify: `DoseTrack/Services/NotificationScheduler.swift`
- Test: `DoseTrackTests/NotificationSchedulerTests.swift`

- [ ] **Step 1: Failing test on a pure sort/cap helper**

```swift
func test_capTo64_keepsEarliestFireDatesAcrossMedications() {
    let now = Date()
    // 100 requests, shuffled fire dates; expect the 64 earliest kept.
    let dates = (0..<100).map { now.addingTimeInterval(Double($0) * 3600) }.shuffled()
    let items = dates.map { NotificationScheduler.Fireable(id: UUID().uuidString, fireDate: $0) }
    let kept = NotificationScheduler.earliest64(items)
    XCTAssertEqual(kept.count, 64)
    let keptDates = kept.map(\.fireDate).sorted()
    XCTAssertEqual(keptDates.first, dates.sorted().first)
    XCTAssertEqual(keptDates.last, dates.sorted()[63])
}
```

- [ ] **Step 2: Run — Expected: FAIL.**

- [ ] **Step 3: Implement**

```swift
struct Fireable { let id: String; let fireDate: Date }

static func earliest64(_ items: [Fireable]) -> [Fireable] {
    Array(items.sorted { $0.fireDate < $1.fireDate }.prefix(64))
}
```
In `buildAndAddRequests`, tag each built `UNNotificationRequest` with its fire date (compute from the trigger's `nextTriggerDate()` or from the `fireDate` you already have when building), sort via `earliest64`, then `center.add` only those. Replace the current `requests.prefix(64)`.

- [ ] **Step 4: Run — Expected: PASS.** Build + full suite pass.

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/Services/NotificationScheduler.swift DoseTrackTests/NotificationSchedulerTests.swift
git commit -m "Sort reminders by fire date before the 64-notification cap so every med gets near-term coverage"
```

---

### Task 2.3: Honor the Critical Alerts toggle and set interruption level

**Files:**
- Modify: `DoseTrack/Services/NotificationScheduler.swift` (`makeContent`)
- Test: `DoseTrackTests/NotificationSchedulerTests.swift`

- [ ] **Step 1: Failing test on content-sound selection (pure helper)**

```swift
func test_sound_isCritical_onlyWhenToggleOn() {
    XCTAssertTrue(NotificationScheduler.useCriticalSound(criticalEnabled: true))
    XCTAssertFalse(NotificationScheduler.useCriticalSound(criticalEnabled: false))
}
```

- [ ] **Step 2: Run — Expected: FAIL.**

- [ ] **Step 3: Implement**

```swift
static func useCriticalSound(criticalEnabled: Bool) -> Bool { criticalEnabled }
```
In `makeContent`, read the setting and branch:
```swift
let criticalEnabled = UserDefaults.standard.object(forKey: "criticalAlertsEnabled") as? Bool ?? true
if Self.useCriticalSound(criticalEnabled: criticalEnabled) {
    content.sound = .defaultCritical
    content.interruptionLevel = .critical
} else {
    content.sound = .default
    content.interruptionLevel = .timeSensitive
}
```

> `.critical` interruption level and `.defaultCritical` sound both require the Critical Alerts entitlement to actually behave as critical; without it iOS silently downgrades. That's acceptable — the toggle still meaningfully switches sound/level.

- [ ] **Step 4: Run — Expected: PASS.** Build + full suite pass.

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/Services/NotificationScheduler.swift DoseTrackTests/NotificationSchedulerTests.swift
git commit -m "Honor Critical Alerts toggle and set notification interruption level"
```

---

### Task 2.4: Actually arm background refresh; make the handler safe

**Files:**
- Modify: `DoseTrack/App/AppDelegate.swift`

- [ ] **Step 1: Arm the task at launch**

At the end of `application(_:didFinishLaunchingWithOptions:)`, add `scheduleBackgroundRefresh()`.

- [ ] **Step 2: Make `handleNotificationRefresh` cancellation-safe and off-main**

```swift
private func handleNotificationRefresh(task: BGAppRefreshTask) {
    scheduleBackgroundRefresh()  // re-arm for next time
    let context = PersistenceController.shared.container.newBackgroundContext()
    let op = Operation()  // or a simple flag
    task.expirationHandler = { /* mark done / bail if the OS reclaims time */ }
    context.perform {
        NotificationScheduler.shared.refreshAll(context: context)
        task.setTaskCompleted(success: true)
    }
}
```

> `NotificationScheduler.refreshAll` is now async internally (uses `getPendingNotificationRequests`). Ensure `setTaskCompleted` fires after the add completes — thread a completion through `refreshAll`, or use a dispatch group. Implementer: add an optional `completion: (() -> Void)?` param to `refreshAll` and call it after `center.add` of the last request.

- [ ] **Step 3: Verify `Info.plist` has `BGTaskSchedulerPermittedIdentifiers` containing `com.robbrown.dosetrack.refresh` and `UIBackgroundModes` includes `fetch`/`processing`.** If missing, add via the plist (and note XcodeGen regen). Grep first:

Run: `plutil -p DoseTrack/Resources/Info.plist | grep -A3 BGTaskSchedulerPermittedIdentifiers` — if absent, add it.

- [ ] **Step 4: Build + test** — Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/App/AppDelegate.swift DoseTrack/Resources/Info.plist
git commit -m "Arm background notification refresh at launch; make handler cancellation-safe and off-main"
```

---

### Phase 2 checkpoint

- [ ] Full suite green (≥ 108 tests).
- [ ] Manual: schedule a snooze, background+foreground the app, confirm the snooze still fires; toggle Critical Alerts off and confirm a test notification uses the default sound.

---

## Chunk 3: Phase 3 — Sync Robustness (Medium)

Fixes: last-write-wins clobbering offline edits (#11), unbounded log pulls (#12), widget-logged doses never syncing (#10). Requires Supabase schema changes.

### File Structure (Phase 3)

- **Supabase migration** — add `updated_at timestamptz default now()` to `medications`, `schedules`, `dose_logs` with an `on update` trigger; ensure indexes on `(user_id, updated_at)`.
- **Modify** `DoseTrack/Services/SupabaseSyncManager.swift` — send/read `updatedAt`; merge compares timestamps; `pullAll` pulls dose logs incrementally (since last sync); add `pushUnsyncedLocalChanges(context:)`.
- **Core Data** — add `updatedAt: Date?` attribute to all three entities (model edit + regen). Set it on every local write (centralize in `DoseLoggingService` and the medication save path).
- **Modify** `DoseTrack/App/RootView.swift` / foreground hook — call `pushUnsyncedLocalChanges` on foreground.
- **Test** `DoseTrackTests/SyncMergeTests.swift` (extend).

---

### Task 3.1: Supabase migration — add `updated_at` to synced tables

**Files:**
- Supabase (MCP `apply_migration`, name `add_updated_at_to_sync_tables`)

- [ ] **Step 1: Apply migration**

```sql
alter table medications add column if not exists updated_at timestamptz not null default now();
alter table schedules   add column if not exists updated_at timestamptz not null default now();
alter table dose_logs   add column if not exists updated_at timestamptz not null default now();

create or replace function set_updated_at() returns trigger as $$
begin new.updated_at = now(); return new; end; $$ language plpgsql;

drop trigger if exists trg_medications_updated on medications;
create trigger trg_medications_updated before update on medications
  for each row execute function set_updated_at();
drop trigger if exists trg_schedules_updated on schedules;
create trigger trg_schedules_updated before update on schedules
  for each row execute function set_updated_at();
drop trigger if exists trg_dose_logs_updated on dose_logs;
create trigger trg_dose_logs_updated before update on dose_logs
  for each row execute function set_updated_at();

create index if not exists idx_dose_logs_user_updated on dose_logs(user_id, updated_at);
create index if not exists idx_medications_user_updated on medications(user_id, updated_at);
```

- [ ] **Step 2: Verify** with `list_tables` / a `select` that the columns exist. No app build here.

- [ ] **Step 3: Commit** (migration file if the repo tracks `supabase/migrations`; otherwise document in the plan's changelog):

```bash
git add supabase/migrations/  # if present
git commit -m "Add updated_at + triggers to medications/schedules/dose_logs for conflict resolution"
```

---

### Task 3.2: Add `updatedAt` to the Core Data model and set it on writes

**Files:**
- Modify: `DoseTrack/Models/DoseTrack.xcdatamodeld/DoseTrack.xcdatamodel/contents` (add `updatedAt` optional Date to Medication, Schedule, DoseLog)
- Modify: `DoseTrack/Services/DoseLoggingService.swift` + `DoseTrack/ViewModels/AddEditMedicationViewModel.swift` — stamp `updatedAt = Date()` on every write.

- [ ] **Step 1: Add the attribute to each entity in the model XML** (mirror existing optional Date attributes like `loggedAt`).

- [ ] **Step 2: `xcodegen generate` + build** — the `category` codegen regenerates `+CoreDataProperties`. Expect BUILD SUCCEEDED.

- [ ] **Step 3: Stamp on write** — in `DoseLoggingService.log`, set `doseLog.updatedAt = Date()` and `medication.updatedAt = Date()` (when supply changes). In `AddEditMedicationViewModel.save`, set `med.updatedAt = Date()` and each schedule's.

- [ ] **Step 4: Build + full suite** — Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/Models/DoseTrack.xcdatamodeld DoseTrack/Services/DoseLoggingService.swift DoseTrack/ViewModels/AddEditMedicationViewModel.swift DoseTrack.xcodeproj/project.pbxproj
git commit -m "Add updatedAt to Core Data model and stamp it on every local write"
```

---

### Task 3.3: Timestamp-based merge (newer wins)

**Files:**
- Modify: `DoseTrack/Services/SupabaseSyncManager.swift` — `MedicationRow`/`ScheduleRow`/`DoseLogRow` gain `updatedAt`; `merge*` compares and keeps the newer side; replace the Task-1.7 interim rule with the timestamp rule.
- Test: `DoseTrackTests/SyncMergeTests.swift`

- [ ] **Step 1: Failing test**

```swift
func test_merge_keepsLocalWhenLocalIsNewer() {
    let ctx = PersistenceController(inMemory: true).viewContext
    let id = UUID()
    let med = Medication(context: ctx)
    med.id = id; med.name = "LocalNew"; med.dosage = "1"; med.unit = "pill"; med.colorHex = "#000"
    med.isActive = true; med.updatedAt = Date()            // now
    try? ctx.save()
    let staleRow = MedicationRow.testRow(id: id.uuidString, isActive: true,
                                         name: "RemoteOld", updatedAt: Date().addingTimeInterval(-3600))
    SupabaseSyncManager.shared.mergeMedicationsForTesting([staleRow], context: ctx)
    XCTAssertEqual((try? ctx.fetch(Medication.fetchRequest()))?.first?.name, "LocalNew")
}
```

- [ ] **Step 2: Run — Expected: FAIL.**

- [ ] **Step 3: Implement the compare** — in each merge loop:

```swift
if let existing, let localTs = existing.updatedAt, localTs >= row.updatedAt {
    continue // local is newer or equal; keep it
}
// else apply remote fields (including isActive) as before, and set updatedAt = row.updatedAt
```
Remove the interim "never resurrect" special-case from Task 1.7 — the timestamp rule subsumes it (a fresh local soft-delete has a newer `updatedAt` than the stale remote row).

- [ ] **Step 4: Run — Expected: PASS** (both this and the Task-1.7 resurrection test still pass).

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/Services/SupabaseSyncManager.swift DoseTrackTests/SyncMergeTests.swift
git commit -m "Timestamp-based sync merge: newer side wins, replacing last-write-wins clobber"
```

---

### Task 3.4: Incremental dose-log pulls

**Files:**
- Modify: `DoseTrack/Services/SupabaseSyncManager.swift` (`fetchRemoteDoseLogs`, `pullAll`)

- [ ] **Step 1: Track last dose-log sync timestamp**

Store `lastDoseLogSyncAt` in `UserDefaults` (per user id key). In `fetchRemoteDoseLogs`, add `.gte("updated_at", value: lastSyncISO)` when present; window to last 90 days on first sync. After a successful pull, write the max `updated_at` seen.

- [ ] **Step 2: Verify no test regressions; add a doc note** that full history for export is fetched on demand (already the case — `ExportManager.fetchAllLogs` reads the local store, which now holds the windowed set; if a user needs older history for a report, add a one-shot "fetch full history" call — track as a follow-up, YAGNI for now).

- [ ] **Step 3: Build + test** — Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add DoseTrack/Services/SupabaseSyncManager.swift
git commit -m "Pull dose logs incrementally (since last sync, windowed) instead of the full history every launch"
```

---

### Task 3.5: Push unsynced local changes on foreground (fixes widget-logged doses)

**Files:**
- Modify: `DoseTrack/Services/SupabaseSyncManager.swift` (add `pushUnsyncedLocalChanges(context:forUserId:)`)
- Modify: `DoseTrack/App/RootView.swift` (call on `.appDidBecomeActive` / scenePhase active)
- Test: `DoseTrackTests/SyncMergeTests.swift`

- [ ] **Step 1: Failing test on the "which logs need pushing" selector**

```swift
func test_unsyncedLogs_selectsThoseUpdatedAfterLastSync() {
    let ctx = PersistenceController(inMemory: true).viewContext
    let med = Medication.create(in: ctx, name: "M", dosage: "1")
    let old = DoseLog.create(in: ctx, medication: med, scheduledAt: Date(), status: .taken)
    old.updatedAt = Date().addingTimeInterval(-1000)
    let new = DoseLog.create(in: ctx, medication: med, scheduledAt: Date(), status: .taken)
    new.updatedAt = Date()
    let cutoff = Date().addingTimeInterval(-500)
    let unsynced = SupabaseSyncManager.unsyncedLogs([old, new], since: cutoff)
    XCTAssertEqual(unsynced.map(\.objectID), [new.objectID])
}
```

- [ ] **Step 2: Run — Expected: FAIL.**

- [ ] **Step 3: Implement selector + push**

```swift
static func unsyncedLogs(_ logs: [DoseLog], since: Date?) -> [DoseLog] {
    guard let since else { return logs }
    return logs.filter { ($0.updatedAt ?? .distantPast) > since }
}

/// Push local logs newer than the last successful push. Covers doses logged while the app
/// was closed (e.g. the widget's Mark-Taken intent), which otherwise never reach Supabase.
func pushUnsyncedLocalChanges(context: NSManagedObjectContext, forUserId: UUID?) async {
    let since = /* read lastPushAt from UserDefaults */
    let logs = (try? context.fetch(DoseLog.fetchRequest())) ?? []
    for log in Self.unsyncedLogs(logs, since: since) {
        await pushDoseLog(log, forUserId: forUserId)
    }
    /* write lastPushAt = now */
}
```

- [ ] **Step 4: Call on foreground** in `RootView`'s scenePhase-active handler: `Task { await SupabaseSyncManager.shared.pushUnsyncedLocalChanges(context: <active context>, forUserId: ActiveAccountResolver.shared.activeUserId) }`.

- [ ] **Step 5: Run — Expected: PASS.** Build + full suite pass.

- [ ] **Step 6: Commit**

```bash
git add DoseTrack/Services/SupabaseSyncManager.swift DoseTrack/App/RootView.swift DoseTrackTests/SyncMergeTests.swift
git commit -m "Push unsynced local dose logs on foreground so widget-logged doses reach Supabase"
```

---

### Phase 3 checkpoint

- [ ] Full suite green.
- [ ] Manual: mark a dose via widget while app is closed → open app → confirm it appears in Supabase (or in a second device's pull).

---

## Chunk 4: Phase 4 — Polish & Hygiene (Medium/Low)

Fixes: PDF pagination (#14), widget ForEach identity (#13), widget timeline thrash clamp (#16), free-tier gating in caregiver view (#17), save-error reporting (#15), secrets template (process). (HealthKit removal (#18) already handled in Phase 1, Task 1.10.)

### File Structure (Phase 4)

- **Modify** `DoseTrack/Services/ReportGenerator.swift` — page-break logic.
- **Modify** `DoseTrackWidgets/MediumWidget.swift` — composite identity.
- **Modify** `DoseTrackWidgets/SmallWidget.swift` + `MediumWidget.swift` — timeline reload clamp `max(nextDose, now+15m)` (verify already done; if so, skip).
- **Modify** `DoseTrack/ViewModels/MedicationsViewModel.swift` — disable add when viewing another account.
- **Create** `DoseTrack/Utilities/CoreDataSave.swift` — `saveOrReport`.
- **Create** `DoseTrack/Resources/Secrets.example.swift` + README note.

---

### Task 4.1: `saveOrReport` helper and adopt it in the hottest paths

**Files:**
- Create: `DoseTrack/Utilities/CoreDataSave.swift`
- Modify: `DoseLoggingService.swift`, `AddEditMedicationViewModel.swift` (swap `try? context.save()` for the helper)
- Test: none (thin wrapper); covered indirectly.

- [ ] **Step 1: Implement**

```swift
// DoseTrack/Utilities/CoreDataSave.swift
import CoreData
import os

private let log = Logger(subsystem: "com.robbrown.dosetrack", category: "coredata")

extension NSManagedObjectContext {
    /// Save, or log+assert on failure. Replaces scattered `try? save()` that silently drop
    /// medical-data write errors.
    func saveOrReport(_ label: String = #function) {
        guard hasChanges else { return }
        do { try save() }
        catch { log.error("CoreData save failed [\(label)]: \(error.localizedDescription)"); assertionFailure("save failed: \(error)") }
    }
}
```

- [ ] **Step 2: Adopt** in `DoseLoggingService.log` and `AddEditMedicationViewModel.save` (leave others for a follow-up sweep — YAGNI to touch all at once).

- [ ] **Step 3: Build + test** — Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add DoseTrack/Utilities/CoreDataSave.swift DoseTrack/Services/DoseLoggingService.swift DoseTrack/ViewModels/AddEditMedicationViewModel.swift DoseTrack.xcodeproj/project.pbxproj
git commit -m "Add saveOrReport helper; stop silently dropping Core Data save errors on write paths"
```

---

### Task 4.2: Widget row identity uses medicationId + scheduledAt

**Files:**
- Modify: `DoseTrackWidgets/MediumWidget.swift`
- Modify: `DoseTrackWidgets/WidgetDataProvider.swift` (make `WidgetDoseEntry` carry a stable composite id or conform to `Identifiable`)

- [ ] **Step 1: Add a composite id** to `WidgetDoseEntry`: `var id: String { "\(medicationId)-\(Int(scheduledAt.timeIntervalSince1970))" }` and conform to `Identifiable`.
- [ ] **Step 2: Change** `ForEach(entry.entries, id: \.medicationId)` → `ForEach(entry.entries)` (now Identifiable). Fix the `dose.medicationId != entry.entries.last?.medicationId` divider check to compare `id`.
- [ ] **Step 3: Build** (widget target) — Expected: SUCCEEDED.
- [ ] **Step 4: Commit**

```bash
git add DoseTrackWidgets/MediumWidget.swift DoseTrackWidgets/WidgetDataProvider.swift
git commit -m "Fix medium-widget row identity for meds with multiple daily doses"
```

---

### Task 4.3: PDF report pagination

**Files:**
- Modify: `DoseTrack/Services/ReportGenerator.swift`
- Test: `DoseTrackTests/ReportGeneratorTests.swift` (assert page count > 1 for many rows)

- [ ] **Step 1: Failing test**

```swift
func test_generatePDF_paginates_whenManyMedications() {
    let ctx = PersistenceController(inMemory: true).viewContext
    var meds: [Medication] = []
    for i in 0..<40 { meds.append(Medication.create(in: ctx, name: "Med\(i)", dosage: "1")) }
    let data = ReportGenerator.shared.generatePDF(logs: [], medications: meds,
        dateRange: DateInterval(start: Date().addingTimeInterval(-2_592_000), end: Date()),
        patientName: "Test")
    let doc = PDFDocument(data: data)
    XCTAssertGreaterThan(doc?.pageCount ?? 0, 1)
}
```

- [ ] **Step 2: Run — Expected: FAIL** (single page).

- [ ] **Step 3: Implement** a `newPageIfNeeded(yOffset:pageHeight:margin:)` that, before drawing a row, checks `yOffset + rowHeight > pageHeight - margin` and if so calls `UIGraphicsBeginPDFPage()` and resets `yOffset = margin`. Route every per-row draw through it.

- [ ] **Step 4: Run — Expected: PASS.** Build + full suite.

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/Services/ReportGenerator.swift DoseTrackTests/ReportGeneratorTests.swift
git commit -m "Paginate the adherence PDF report so long reports don't clip off the page"
```

---

### Task 4.4: Don't offer "Add Medication" while viewing another account; fix free-tier math

**Files:**
- Modify: `DoseTrack/ViewModels/MedicationsViewModel.swift` (`canAddMedication`)
- Modify: `DoseTrack/Views/Medications/MedicationsView.swift` (hide/disable the + button in caregiver view)

- [ ] **Step 1: Gate `canAddMedication`** — return `false` (without showing the paywall) when `ActiveAccountResolver.shared.activeUserId != nil`; a caregiver shouldn't create meds in a patient's account from this UI. The free-tier count then always reflects the user's own store.
- [ ] **Step 2: Hide the toolbar `+`** in `MedicationsView` when `activeAccount.isViewingOtherAccount`.
- [ ] **Step 3: Build + test.**
- [ ] **Step 4: Commit**

```bash
git add DoseTrack/ViewModels/MedicationsViewModel.swift DoseTrack/Views/Medications/MedicationsView.swift
git commit -m "Disable add-medication while viewing a patient; free-tier limit counts only own meds"
```

---

### Task 4.5: Secrets template + clone safety

**Files:**
- Create: `DoseTrack/Resources/Secrets.example.swift`
- Modify: `README.md` or `CLAUDE.md` (one-line setup note)

- [ ] **Step 1: Create the template** (no real values):

```swift
// Copy to Secrets.swift (gitignored) and fill in. Supabase anon key is public-by-design.
enum Secrets {
    static let supabaseURL = "https://YOUR_PROJECT.supabase.co"
    static let supabaseAnonKey = "YOUR_ANON_KEY"
    static let googleClientID = ""
}
```

- [ ] **Step 2:** Confirm `Secrets.swift` is gitignored (`git check-ignore DoseTrack/Resources/Secrets.swift`); if not, add to `.gitignore`. Add a build-time sanity note to `CLAUDE.md`.
- [ ] **Step 3: Commit**

```bash
git add DoseTrack/Resources/Secrets.example.swift .gitignore CLAUDE.md
git commit -m "Add Secrets.example.swift template and document setup"
```

---

### Phase 4 checkpoint

- [ ] Full suite green.
- [ ] Manual: generate a month-long report with many meds → multiple pages; medium widget with a twice-daily med renders two distinct rows.

---

## Final review handoff

- [ ] Dispatch a final code-reviewer subagent over the full diff of all four phases.
- [ ] Update the `dosetrack_dev_only_features.md` memory if any debug affordances were added.
- [ ] Use superpowers:finishing-a-development-branch.

**Sequencing guidance:** Phases 1 and 2 are release-blocking (silent wrong data + unreliable reminders). Phase 3 depends on Phase 1 (the merge/timestamp work assumes the consolidated write path and `updatedAt`). Phase 4 is independent and can be interleaved or deferred. Do not ship a TestFlight build before Phases 1 and 2 land.
