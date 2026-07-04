# Guided Schedule Builder Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat, form-based Schedule section in Add/Edit Medication with a question-driven guided flow for anything beyond "once daily, every day," add a global Meal Times preference, and sync it all through the existing Supabase settings path.

**Architecture:** A new global `MealTimes` model (7 fixed slots) persisted in UserDefaults and synced via 14 new flat columns on the existing `user_settings` table/`UserSettingsRow` — no new tables. A new pure `ScheduleGenerator` computes concrete `[ScheduleDraft]` from the guided flow's answers (every day/specific days × interval/meal/manual). A new `GuidedScheduleView` replaces the old per-row `ScheduleBuilderView` in `AddEditMedicationView`, showing a collapsed summary by default and expanding into the question sequence on demand.

**Tech Stack:** Swift 5.9/SwiftUI (iOS 17+), CoreData (unchanged), Supabase Postgres (`user_settings` table), XCTest.

**Spec:** `docs/superpowers/specs/2026-07-04-guided-schedule-builder-design.md` — read this in full before starting.

**Supabase access:** Use the Supabase MCP tools (`execute_sql`, `apply_migration`, `get_advisors`) for the migration in Task 1 — project id `ttosaeghpxhhzlvwlqnm`. Confirmed current `user_settings` columns (via `information_schema.columns`): `user_id, color_theme, appearance, time_format, snooze_duration, haptics_enabled, show_dose_badge, compact_rows, selected_avatar, patient_name, patient_gender, patient_dob, patient_phone, patient_country, patient_state, updated_at`.

**Repo:** work in `/Users/robbrown/CodingProjects/Apps/dosetrack-caregiver` (git worktree, branch `caregiver-sharing` — this plan is intentionally built on top of that branch per explicit user instruction, not a separate branch).

**This project uses XcodeGen.** Any new file must be followed by `xcodegen generate`, and every test claim must be backed by literal `xcodebuild` output showing "Executed N tests" — never trust "no compile errors" alone as proof tests ran (this has bitten prior work in this repo).

---

## Chunk 1: Meal Times model, Supabase sync, Settings screen

### Task 1: Add 14 meal-time columns to `user_settings`

**Files:** none (Supabase migration via MCP tool)

- [ ] **Step 1: Apply the migration**

Use `apply_migration` (name `add_meal_times_to_user_settings`):

```sql
alter table user_settings
  add column meal_breakfast_hour smallint,
  add column meal_breakfast_minute smallint,
  add column meal_morning_tea_hour smallint,
  add column meal_morning_tea_minute smallint,
  add column meal_lunch_hour smallint,
  add column meal_lunch_minute smallint,
  add column meal_afternoon_tea_hour smallint,
  add column meal_afternoon_tea_minute smallint,
  add column meal_dinner_hour smallint,
  add column meal_dinner_minute smallint,
  add column meal_dessert_hour smallint,
  add column meal_dessert_minute smallint,
  add column meal_midnight_snack_hour smallint,
  add column meal_midnight_snack_minute smallint;
```

All columns are nullable — a row written before this migration existed simply has nulls here, and the client falls back to hardcoded defaults (Task 4) when a value is missing, exactly like every other optional field in `UserSettingsRow` already does (e.g. `patientDob`).

- [ ] **Step 2: Verify with `execute_sql`**

```sql
select column_name, data_type from information_schema.columns where table_name = 'user_settings' order by ordinal_position;
```
Confirm all 14 new columns appear with `data_type = smallint`.

- [ ] **Step 3: Run `get_advisors`** and confirm no new warnings tied to `user_settings` (existing RLS policy already covers all columns on the table, so adding columns shouldn't introduce anything new — confirm this is the case rather than assuming).

### Task 2: `MealTimes` model + local persistence

**Files:**
- Create: `DoseTrack/Models/MealTimes.swift`
- Test: `DoseTrackTests/MealTimesTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import DoseTrack

final class MealTimesTests: XCTestCase {
    func test_defaultsMatchSpec() {
        let times = MealTimes.default
        XCTAssertEqual(times.breakfast, MealTime(hour: 7, minute: 30))
        XCTAssertEqual(times.morningTea, MealTime(hour: 10, minute: 0))
        XCTAssertEqual(times.lunch, MealTime(hour: 12, minute: 30))
        XCTAssertEqual(times.afternoonTea, MealTime(hour: 15, minute: 0))
        XCTAssertEqual(times.dinner, MealTime(hour: 18, minute: 30))
        XCTAssertEqual(times.dessert, MealTime(hour: 19, minute: 30))
        XCTAssertEqual(times.midnightSnack, MealTime(hour: 23, minute: 0))
    }

    func test_loadFallsBackToDefaultsWhenUnset() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let times = MealTimes.load(from: defaults)
        XCTAssertEqual(times, MealTimes.default)
    }

    func test_saveThenLoadRoundTrips() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        var times = MealTimes.default
        times.lunch = MealTime(hour: 13, minute: 15)
        times.save(to: defaults)
        let loaded = MealTimes.load(from: defaults)
        XCTAssertEqual(loaded.lunch, MealTime(hour: 13, minute: 15))
        // Untouched slots still round-trip correctly, not just the one we changed
        XCTAssertEqual(loaded.breakfast, MealTimes.default.breakfast)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DoseTrackTests/MealTimesTests 2>&1 | tail -30`
Expected: FAIL — `MealTimes`/`MealTime` not defined.

- [ ] **Step 3: Implement**

```swift
// DoseTrack/Models/MealTimes.swift
import Foundation

/// A single meal's clock time (hour/minute only — no date component, since this
/// represents a daily recurring time-of-day, same convention as `Schedule`).
struct MealTime: Equatable, Codable {
    var hour: Int
    var minute: Int
}

/// The app-wide (not per-medication) set of meal times a user can tie a
/// medication's schedule to. See the design spec's "Meal Times" section —
/// this is intentionally global: "the person is the variable with meal
/// times, not the medication."
struct MealTimes: Equatable {
    var breakfast: MealTime
    var morningTea: MealTime
    var lunch: MealTime
    var afternoonTea: MealTime
    var dinner: MealTime
    var dessert: MealTime
    var midnightSnack: MealTime

    static let `default` = MealTimes(
        breakfast: MealTime(hour: 7, minute: 30),
        morningTea: MealTime(hour: 10, minute: 0),
        lunch: MealTime(hour: 12, minute: 30),
        afternoonTea: MealTime(hour: 15, minute: 0),
        dinner: MealTime(hour: 18, minute: 30),
        dessert: MealTime(hour: 19, minute: 30),
        midnightSnack: MealTime(hour: 23, minute: 0)
    )

    private static let defaultsKey = "mealTimes"

    /// Loads from UserDefaults, falling back to `.default` if unset or unparseable.
    static func load(from defaults: UserDefaults = .standard) -> MealTimes {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(MealTimes.self, from: data)
        else { return .default }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

extension MealTimes: Codable {}
```

Note: this stores the whole `MealTimes` struct as one JSON blob in `UserDefaults` under a single key (`"mealTimes"`) for simplicity on the **local** side — this is independent of the Supabase side, which Task 3 stores as 14 flat columns per the spec's explicit decision to match `UserSettingsRow`'s all-scalar pattern. Task 3's `UserSettingsRow` reads/writes the same `UserDefaults` key indirectly by decoding/encoding through `MealTimes.load`/`.save`, not by reading 14 separate UserDefaults keys — this keeps `MealTimes` the single source of truth for the local representation, while the Supabase row shape is a flat encoding used only for the network round-trip.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DoseTrackTests/MealTimesTests 2>&1 | tail -30`
Expected: literal "Executed 3 tests, with 0 failures"

- [ ] **Step 5: Run `xcodegen generate`**, verify `MealTimes.swift`/`MealTimesTests.swift` referenced in `project.pbxproj` via grep.

- [ ] **Step 6: Commit**

```bash
git add DoseTrack/Models/MealTimes.swift DoseTrackTests/MealTimesTests.swift DoseTrack.xcodeproj/project.pbxproj
git commit -m "feat: add MealTimes model with default meal-time slots"
```

### Task 3: Sync `MealTimes` through `UserSettingsRow`

**Files:**
- Modify: `DoseTrack/Services/SupabaseSyncManager.swift:210-229` (`applySettings`), `:339-395` (`UserSettingsRow`)

- [ ] **Step 1: Read the current full `UserSettingsRow` struct and `applySettings` function** in `SupabaseSyncManager.swift` (already quoted above in this plan's research, but re-read the live file since other work may have touched it).

- [ ] **Step 2: Add the 14 meal-time fields to `UserSettingsRow`**, matching the existing flat-scalar pattern exactly (no nested struct, no JSON blob column — per the spec's explicit decision):

```swift
struct UserSettingsRow: Codable {
    var userId: String
    var colorTheme: String
    var appearance: String
    var timeFormat: String
    var snoozeDuration: Int
    var hapticsEnabled: Bool
    var showDoseBadge: Bool
    var compactRows: Bool
    var selectedAvatar: String
    var patientName: String
    var patientGender: String
    var patientDob: String?
    var patientPhone: String
    var patientCountry: String
    var patientState: String
    var mealBreakfastHour: Int
    var mealBreakfastMinute: Int
    var mealMorningTeaHour: Int
    var mealMorningTeaMinute: Int
    var mealLunchHour: Int
    var mealLunchMinute: Int
    var mealAfternoonTeaHour: Int
    var mealAfternoonTeaMinute: Int
    var mealDinnerHour: Int
    var mealDinnerMinute: Int
    var mealDessertHour: Int
    var mealDessertMinute: Int
    var mealMidnightSnackHour: Int
    var mealMidnightSnackMinute: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case colorTheme = "color_theme"
        case appearance
        case timeFormat = "time_format"
        case snoozeDuration = "snooze_duration"
        case hapticsEnabled = "haptics_enabled"
        case showDoseBadge = "show_dose_badge"
        case compactRows = "compact_rows"
        case selectedAvatar = "selected_avatar"
        case patientName = "patient_name"
        case patientGender = "patient_gender"
        case patientDob = "patient_dob"
        case patientPhone = "patient_phone"
        case patientCountry = "patient_country"
        case patientState = "patient_state"
        case mealBreakfastHour = "meal_breakfast_hour"
        case mealBreakfastMinute = "meal_breakfast_minute"
        case mealMorningTeaHour = "meal_morning_tea_hour"
        case mealMorningTeaMinute = "meal_morning_tea_minute"
        case mealLunchHour = "meal_lunch_hour"
        case mealLunchMinute = "meal_lunch_minute"
        case mealAfternoonTeaHour = "meal_afternoon_tea_hour"
        case mealAfternoonTeaMinute = "meal_afternoon_tea_minute"
        case mealDinnerHour = "meal_dinner_hour"
        case mealDinnerMinute = "meal_dinner_minute"
        case mealDessertHour = "meal_dessert_hour"
        case mealDessertMinute = "meal_dessert_minute"
        case mealMidnightSnackHour = "meal_midnight_snack_hour"
        case mealMidnightSnackMinute = "meal_midnight_snack_minute"
    }

    init(userId: UUID) {
        let d = UserDefaults.standard
        self.userId      = userId.uuidString
        colorTheme       = d.string(forKey: "colorTheme") ?? "Ocean Blue"
        appearance       = d.string(forKey: "appearanceOverride") ?? "system"
        timeFormat       = d.string(forKey: "timeFormat") ?? "system"
        snoozeDuration   = d.integer(forKey: "defaultSnoozeDuration").nonZeroOr(30)
        hapticsEnabled   = d.bool(forKey: "hapticsEnabled")
        showDoseBadge    = d.bool(forKey: "showDoseBadge")
        compactRows      = d.bool(forKey: "compactRows")
        selectedAvatar   = d.string(forKey: "selectedAvatar") ?? "milli"
        patientName      = d.string(forKey: "patientName") ?? ""
        patientGender    = d.string(forKey: "patientGender") ?? ""
        patientPhone     = d.string(forKey: "patientPhone") ?? ""
        patientCountry   = d.string(forKey: "patientCountry") ?? ""
        patientState     = d.string(forKey: "patientState") ?? ""
        let dobInterval  = d.double(forKey: "patientDOBInterval")
        if dobInterval > 0 {
            patientDob = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: dobInterval))
        }
        let meals = MealTimes.load(from: d)
        mealBreakfastHour = meals.breakfast.hour
        mealBreakfastMinute = meals.breakfast.minute
        mealMorningTeaHour = meals.morningTea.hour
        mealMorningTeaMinute = meals.morningTea.minute
        mealLunchHour = meals.lunch.hour
        mealLunchMinute = meals.lunch.minute
        mealAfternoonTeaHour = meals.afternoonTea.hour
        mealAfternoonTeaMinute = meals.afternoonTea.minute
        mealDinnerHour = meals.dinner.hour
        mealDinnerMinute = meals.dinner.minute
        mealDessertHour = meals.dessert.hour
        mealDessertMinute = meals.dessert.minute
        mealMidnightSnackHour = meals.midnightSnack.hour
        mealMidnightSnackMinute = meals.midnightSnack.minute
    }
}
```

- [ ] **Step 3: Update `applySettings` to write the pulled meal times back into local storage**, appending to the existing function body:

```swift
private func applySettings(_ row: UserSettingsRow) {
    let d = UserDefaults.standard
    d.set(row.colorTheme,      forKey: "colorTheme")
    d.set(row.appearance,      forKey: "appearanceOverride")
    d.set(row.timeFormat,      forKey: "timeFormat")
    d.set(row.snoozeDuration,  forKey: "defaultSnoozeDuration")
    d.set(row.hapticsEnabled,  forKey: "hapticsEnabled")
    d.set(row.showDoseBadge,   forKey: "showDoseBadge")
    d.set(row.compactRows,     forKey: "compactRows")
    d.set(row.selectedAvatar,  forKey: "selectedAvatar")
    d.set(row.patientName,     forKey: "patientName")
    d.set(row.patientGender,   forKey: "patientGender")
    d.set(row.patientPhone,    forKey: "patientPhone")
    d.set(row.patientCountry,  forKey: "patientCountry")
    d.set(row.patientState,    forKey: "patientState")
    if let dob = row.patientDob {
        let ts = ISO8601DateFormatter().date(from: dob)?.timeIntervalSince1970 ?? 0
        d.set(ts, forKey: "patientDOBInterval")
    }
    let meals = MealTimes(
        breakfast: MealTime(hour: row.mealBreakfastHour, minute: row.mealBreakfastMinute),
        morningTea: MealTime(hour: row.mealMorningTeaHour, minute: row.mealMorningTeaMinute),
        lunch: MealTime(hour: row.mealLunchHour, minute: row.mealLunchMinute),
        afternoonTea: MealTime(hour: row.mealAfternoonTeaHour, minute: row.mealAfternoonTeaMinute),
        dinner: MealTime(hour: row.mealDinnerHour, minute: row.mealDinnerMinute),
        dessert: MealTime(hour: row.mealDessertHour, minute: row.mealDessertMinute),
        midnightSnack: MealTime(hour: row.mealMidnightSnackHour, minute: row.mealMidnightSnackMinute)
    )
    meals.save(to: d)
}
```

- [ ] **Step 4: Build to confirm it compiles.** `xcodebuild -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator build 2>&1 | tail -40` — quote actual output, expect `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual verification against the live Supabase table.** Since this reads/writes real Supabase columns, do a code-review-level check (not a live push/pull test — that needs a signed-in session and is better covered in this plan's final smoke-test task): re-run `execute_sql` (`select column_name from information_schema.columns where table_name = 'user_settings'`) and confirm every `CodingKeys` raw value added in Step 2 matches an actual column name — a single typo here (e.g. `meal_morning_tea_hour` vs. `meal_morningtea_hour`) would silently fail to decode/encode that one field with no compile-time error, since it's just a string key.

- [ ] **Step 6: Commit**

```bash
git add DoseTrack/Services/SupabaseSyncManager.swift
git commit -m "feat: sync MealTimes through the existing user_settings row"
```

### Task 4: Meal Times settings screen

**Files:**
- Create: `DoseTrack/Views/Settings/MealTimesView.swift`
- Modify: `DoseTrack/Views/Settings/AppPreferencesView.swift`

- [ ] **Step 1: Build the settings screen**

```swift
// DoseTrack/Views/Settings/MealTimesView.swift
import SwiftUI

/// Settings → Preferences → Meal Times. Lets the user adjust the app-wide meal
/// times used when a medication's schedule is tied to meals (see
/// `GuidedScheduleView`). Global, not per-medication — see design spec.
struct MealTimesView: View {
    @State private var meals: MealTimes = MealTimes.load()

    private let slots: [(name: String, keyPath: WritableKeyPath<MealTimes, MealTime>)] = [
        ("Breakfast", \.breakfast),
        ("Morning Tea", \.morningTea),
        ("Lunch", \.lunch),
        ("Afternoon Tea", \.afternoonTea),
        ("Dinner", \.dinner),
        ("Dessert", \.dessert),
        ("Midnight Snack", \.midnightSnack),
    ]

    var body: some View {
        List {
            ForEach(slots, id: \.name) { slot in
                DatePicker(
                    slot.name,
                    selection: timeBinding(for: slot.keyPath),
                    displayedComponents: .hourAndMinute
                )
            }
        }
        .navigationTitle("Meal Times")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeBinding(for keyPath: WritableKeyPath<MealTimes, MealTime>) -> Binding<Date> {
        Binding(
            get: {
                let meal = meals[keyPath: keyPath]
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = meal.hour
                c.minute = meal.minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                meals[keyPath: keyPath] = MealTime(hour: c.hour ?? 0, minute: c.minute ?? 0)
                meals.save()
                Task { await SupabaseSyncManager.shared.pushSettings() }
            }
        )
    }
}

#Preview {
    NavigationStack { MealTimesView() }
}
```

- [ ] **Step 2: Add the NavigationLink in `AppPreferencesView.swift`.** Read the file first to find where "Change App Icon" (or the nearest similar link) sits, and add a new link near it in the same `Section`:

```swift
NavigationLink {
    MealTimesView()
} label: {
    Label("Meal Times", systemImage: "fork.knife")
}
```

- [ ] **Step 3: Build.** `xcodebuild -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator build 2>&1 | tail -40` — quote actual output, expect `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run `xcodegen generate`**, confirm `MealTimesView` referenced in `project.pbxproj`.

- [ ] **Step 5: Commit**

```bash
git add DoseTrack/Views/Settings/MealTimesView.swift DoseTrack/Views/Settings/AppPreferencesView.swift DoseTrack.xcodeproj/project.pbxproj
git commit -m "feat: add Meal Times settings screen"
```

---

## Chunk 2: Interval generation, guided flow UI, integration

### Task 5: Pure interval-generation function

**Files:**
- Create: `DoseTrack/Services/ScheduleGenerator.swift`
- Test: `DoseTrackTests/ScheduleGeneratorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import DoseTrack

final class ScheduleGeneratorTests: XCTestCase {
    func test_generatesSequentialTimesWithoutWrapping() {
        let times = ScheduleGenerator.intervalTimes(
            first: MealTime(hour: 6, minute: 0), intervalHours: 4, count: 4
        )
        XCTAssertEqual(times, [
            MealTime(hour: 6, minute: 0),
            MealTime(hour: 10, minute: 0),
            MealTime(hour: 14, minute: 0),
            MealTime(hour: 18, minute: 0),
        ])
    }

    func test_wrapsPastMidnightRatherThanErroring() {
        let times = ScheduleGenerator.intervalTimes(
            first: MealTime(hour: 22, minute: 0), intervalHours: 6, count: 4
        )
        XCTAssertEqual(times, [
            MealTime(hour: 22, minute: 0),
            MealTime(hour: 4, minute: 0),
            MealTime(hour: 10, minute: 0),
            MealTime(hour: 16, minute: 0),
        ])
    }

    func test_countOfOneReturnsJustTheFirstTime() {
        let times = ScheduleGenerator.intervalTimes(
            first: MealTime(hour: 9, minute: 15), intervalHours: 5, count: 1
        )
        XCTAssertEqual(times, [MealTime(hour: 9, minute: 15)])
    }

    func test_largeCountAndIntervalCanProduceDuplicatesWithoutCrashing() {
        // Per spec: duplicates from wrap-around are allowed, not deduplicated —
        // this is a total function with no special-cased failure mode.
        let times = ScheduleGenerator.intervalTimes(
            first: MealTime(hour: 0, minute: 0), intervalHours: 24, count: 3
        )
        XCTAssertEqual(times, [
            MealTime(hour: 0, minute: 0),
            MealTime(hour: 0, minute: 0),
            MealTime(hour: 0, minute: 0),
        ])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DoseTrackTests/ScheduleGeneratorTests 2>&1 | tail -30`
Expected: FAIL — `ScheduleGenerator` not defined.

- [ ] **Step 3: Implement**

```swift
// DoseTrack/Services/ScheduleGenerator.swift
import Foundation

/// Pure logic for turning the guided schedule flow's answers into concrete
/// clock times. Never divides 24 hours by a dose count — always walks forward
/// from a user-supplied first time by a user-supplied hour interval, per the
/// design spec (this deliberately doesn't assume doses are evenly spread
/// across a full day, since that ignores sleep hours).
enum ScheduleGenerator {
    /// Generates `count` times starting at `first`, each `intervalHours` after
    /// the previous, wrapping past midnight (mod 24) rather than erroring.
    /// `intervalHours` must be >= 1 (enforced by the UI's input control, per
    /// spec — not re-validated here). Duplicate times from a wrap are returned
    /// as-is, not deduplicated; the caller (guided flow's Review step) is
    /// where a user notices and fixes an unintended duplicate.
    static func intervalTimes(first: MealTime, intervalHours: Int, count: Int) -> [MealTime] {
        guard count > 0 else { return [] }
        let firstTotalMinutes = first.hour * 60 + first.minute
        return (0..<count).map { i in
            let totalMinutes = (firstTotalMinutes + i * intervalHours * 60).mod(24 * 60)
            return MealTime(hour: totalMinutes / 60, minute: totalMinutes % 60)
        }
    }
}

private extension Int {
    /// True (non-negative) modulo, since Swift's `%` can return negative results
    /// for negative operands — not expected here given non-negative inputs, but
    /// keeps this function correct rather than relying on caller discipline.
    func mod(_ m: Int) -> Int {
        let r = self % m
        return r >= 0 ? r : r + m
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DoseTrackTests/ScheduleGeneratorTests 2>&1 | tail -30`
Expected: literal "Executed 4 tests, with 0 failures"

- [ ] **Step 5: Run `xcodegen generate`**, verify referenced in `project.pbxproj`.

- [ ] **Step 6: Commit**

```bash
git add DoseTrack/Services/ScheduleGenerator.swift DoseTrackTests/ScheduleGeneratorTests.swift DoseTrack.xcodeproj/project.pbxproj
git commit -m "feat: add pure interval-generation logic for guided schedule flow"
```

### Task 6: `GuidedScheduleView` — collapsed summary + question flow

**Files:**
- Create: `DoseTrack/Views/Medications/GuidedScheduleView.swift`
- Delete: `DoseTrack/Views/Medications/ScheduleBuilderView.swift` (fully superseded — confirm via `grep -rln "ScheduleBuilderView" DoseTrack/ --include="*.swift"` that `AddEditMedicationView.swift` is the only consumer before deleting, then update that consumer in Task 7)

This is the most involved task in the plan — it's a real, moderately complex piece of stateful UI, not boilerplate. Take it in the sub-steps below rather than writing it all at once.

- [ ] **Step 1: Read `ScheduleBuilderView.swift` in full** (already quoted in the spec's context) to reuse its `DayToggleButtonStyle` and day-of-week row pattern rather than reinventing it.

- [ ] **Step 2: Define the view's internal flow state.** `GuidedScheduleView` takes a `@Binding<[ScheduleDraft]>` (the same array `AddEditMedicationViewModel.schedules` already is) plus the medication's name/dose description for the question text, and manages its own local `@State` for "which step of the flow is showing" — it does not need new persisted state, only ephemeral UI state while the user answers questions, which then writes the final `[ScheduleDraft]` back through the binding once.

```swift
// DoseTrack/Views/Medications/GuidedScheduleView.swift
import SwiftUI

struct GuidedScheduleView: View {
    @Binding var schedules: [ScheduleDraft]
    let medicationName: String
    let doseDescription: String // e.g. "500mg" — used in the Q1 prompt text
    /// Passed straight through from `AddEditMedicationViewModel.isEditing` rather than
    /// inferred from the schedule data — see `seedStateFromExistingSchedules()` below,
    /// this is the reliable signal an editing session already has, no heuristic needed.
    let isEditingExistingMedication: Bool

    private enum Step: Equatable {
        case collapsed
        case howOften
        case specificDays
        case timesPerDay
        case spacing
        case intervalDetails
        case mealSelection
        case manualTimes
        case review
    }

    @State private var step: Step = .collapsed
    @State private var everyDay = true
    @State private var daysOfWeek: [Int] = []
    @State private var timesPerDay = 1
    @State private var spacingChoice: SpacingChoice = .manual
    @State private var intervalFirstTime = defaultTime(hour: 8, minute: 0)
    @State private var intervalHours = 8
    @State private var selectedMeals: Set<MealSlot> = []
    @State private var mealTimes: MealTimes = MealTimes.load()
    @State private var manualTimes: [Date] = [defaultTime(hour: 8, minute: 0)]

    private enum SpacingChoice { case fixedInterval, meals, manual }

    private enum MealSlot: String, CaseIterable, Identifiable {
        case breakfast, morningTea, lunch, afternoonTea, dinner, dessert, midnightSnack
        var id: String { rawValue }
        var label: String {
            switch self {
            case .breakfast: return "Breakfast"
            case .morningTea: return "Morning Tea"
            case .lunch: return "Lunch"
            case .afternoonTea: return "Afternoon Tea"
            case .dinner: return "Dinner"
            case .dessert: return "Dessert"
            case .midnightSnack: return "Midnight Snack"
            }
        }
        func time(in meals: MealTimes) -> MealTime {
            switch self {
            case .breakfast: return meals.breakfast
            case .morningTea: return meals.morningTea
            case .lunch: return meals.lunch
            case .afternoonTea: return meals.afternoonTea
            case .dinner: return meals.dinner
            case .dessert: return meals.dessert
            case .midnightSnack: return meals.midnightSnack
            }
        }
    }

    private static func defaultTime(hour: Int, minute: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c) ?? Date()
    }

    var body: some View {
        Group {
            switch step {
            case .collapsed:      collapsedRow
            case .howOften:       howOftenQuestion
            case .specificDays:   specificDaysQuestion
            case .timesPerDay:    timesPerDayQuestion
            case .spacing:        spacingQuestion
            case .intervalDetails: intervalDetailsQuestion
            case .mealSelection:  mealSelectionQuestion
            case .manualTimes:    manualTimesQuestion
            case .review:         reviewStep
            }
        }
        .animation(.default, value: step)
        .onAppear { seedStateFromExistingSchedules() }
    }

    // MARK: - Collapsed summary

    private var collapsedRow: some View {
        Button {
            // `isEditingExistingMedication`, not `schedules.count > 1` — a fresh
            // once-daily draft and a genuinely-edited once-daily schedule both have
            // exactly 1 entry, so count alone can't distinguish them. Any existing
            // medication (even once-daily) should open on Review, not restart at Q1;
            // any new medication should always start the question flow.
            step = isEditingExistingMedication ? .review : .howOften
        } label: {
            HStack {
                Text("Taken: \(summaryText)")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private var summaryText: String {
        guard let first = schedules.first else { return "Not scheduled" }
        let timeText = formattedTime(hour: first.hour, minute: first.minute)
        if schedules.count > 1 {
            return "\(schedules.count) times daily, starting \(timeText)"
        }
        return first.daysOfWeek.isEmpty
            ? "Once daily at \(timeText)"
            : "Once on selected days at \(timeText)"
    }

    private func formattedTime(hour: Int, minute: Int) -> String {
        var c = DateComponents()
        c.hour = hour; c.minute = minute
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Q1: How often

    private var howOftenQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How often is \(doseDescription) of \(medicationName) taken?")
                .font(.headline)
            Picker("", selection: $everyDay) {
                Text("Every day").tag(true)
                Text("Specific days").tag(false)
            }
            .pickerStyle(.segmented)
            Button("Next") {
                step = everyDay ? .timesPerDay : .specificDays
            }
        }
    }

    // MARK: - Specific days (reuses the existing day-toggle pattern)

    private let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var specificDaysQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which days?")
                .font(.headline)
            HStack(spacing: 6) {
                ForEach(Array(dayLabels.enumerated()), id: \.offset) { index, label in
                    let weekday = index + 1
                    let selected = daysOfWeek.contains(weekday)
                    Button(label) {
                        if selected {
                            daysOfWeek.removeAll { $0 == weekday }
                        } else {
                            daysOfWeek.append(weekday)
                            daysOfWeek.sort()
                        }
                    }
                    .buttonStyle(DayToggleButtonStyle(selected: selected))
                }
            }
            Button("Next") { step = .timesPerDay }
                .disabled(daysOfWeek.isEmpty)
        }
    }

    // MARK: - Q2: Times per day

    private var timesPerDayQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How many times per day?")
                .font(.headline)
            Stepper("\(timesPerDay) time\(timesPerDay == 1 ? "" : "s") per day", value: $timesPerDay, in: 1...12)
            Button("Next") {
                // `manualTimes` only ever gets resized in `spacingQuestion`'s `.manual`
                // branch (for timesPerDay > 1); the timesPerDay == 1 path relies on
                // `manualTimes`'s `@State` default already being a 1-element array, so
                // it's correct as-is here without a resize — don't add one, and don't
                // let a future change to `timesPerDay` after this point skip that resize.
                step = timesPerDay == 1 ? .manualTimes : .spacing
            }
        }
    }

    // MARK: - Q3: Spacing (only reached when timesPerDay > 1)

    private var spacingQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How are doses spaced?")
                .font(.headline)
            Picker("", selection: $spacingChoice) {
                Text("Fixed intervals").tag(SpacingChoice.fixedInterval)
                Text("Tied to meals").tag(SpacingChoice.meals)
                Text("Set each manually").tag(SpacingChoice.manual)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Button("Next") {
                switch spacingChoice {
                case .fixedInterval: step = .intervalDetails
                case .meals:         step = .mealSelection
                case .manual:        manualTimes = Array(repeating: manualTimes.first ?? Self.defaultTime(hour: 8, minute: 0), count: timesPerDay); step = .manualTimes
                }
            }
        }
    }

    // MARK: - Fixed interval details

    private var intervalDetailsQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("First dose time, and hours between doses")
                .font(.headline)
            DatePicker("First dose", selection: $intervalFirstTime, displayedComponents: .hourAndMinute)
            Stepper("Every \(intervalHours) hour\(intervalHours == 1 ? "" : "s")", value: $intervalHours, in: 1...24)
            Button("Next") { applyGeneratedSchedulesFromInterval(); step = .review }
        }
    }

    private func applyGeneratedSchedulesFromInterval() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: intervalFirstTime)
        let first = MealTime(hour: c.hour ?? 8, minute: c.minute ?? 0)
        let generated = ScheduleGenerator.intervalTimes(first: first, intervalHours: intervalHours, count: timesPerDay)
        schedules = generated.map { makeDraft(hour: $0.hour, minute: $0.minute) }
    }

    // MARK: - Meal selection

    private var mealSelectionQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which meals? (\(selectedMeals.count) of \(timesPerDay) selected)")
                .font(.headline)
            ForEach(MealSlot.allCases) { meal in
                let time = meal.time(in: mealTimes)
                Toggle(isOn: Binding(
                    get: { selectedMeals.contains(meal) },
                    set: { isOn in
                        if isOn { selectedMeals.insert(meal) } else { selectedMeals.remove(meal) }
                    }
                )) {
                    HStack {
                        Text(meal.label)
                        Spacer()
                        Text(formattedTime(hour: time.hour, minute: time.minute))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Next") { applyGeneratedSchedulesFromMeals(); step = .review }
                .disabled(selectedMeals.count != timesPerDay)
        }
    }

    private func applyGeneratedSchedulesFromMeals() {
        schedules = selectedMeals.sorted { a, b in
            let ta = a.time(in: mealTimes); let tb = b.time(in: mealTimes)
            return (ta.hour, ta.minute) < (tb.hour, tb.minute)
        }.map { meal in
            let t = meal.time(in: mealTimes)
            return makeDraft(hour: t.hour, minute: t.minute)
        }
    }

    // MARK: - Manual times (used for timesPerDay == 1 too, as a single-item case)

    private var manualTimesQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(manualTimes.indices, id: \.self) { i in
                DatePicker("Dose \(i + 1) time", selection: Binding(
                    get: { manualTimes[i] },
                    set: { manualTimes[i] = $0 }
                ), displayedComponents: .hourAndMinute)
            }
            Button("Next") { applyGeneratedSchedulesFromManual(); step = .review }
        }
    }

    private func applyGeneratedSchedulesFromManual() {
        schedules = manualTimes.map { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            return makeDraft(hour: c.hour ?? 8, minute: c.minute ?? 0)
        }
    }

    // MARK: - Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule").font(.headline)
            ForEach(schedules.indices, id: \.self) { i in
                HStack {
                    DatePicker("", selection: Binding(
                        get: {
                            var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                            c.hour = schedules[i].hour; c.minute = schedules[i].minute
                            return Calendar.current.date(from: c) ?? Date()
                        },
                        set: { date in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                            schedules[i].hour = c.hour ?? 8
                            schedules[i].minute = c.minute ?? 0
                        }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                }
            }
            HStack {
                Button("Change Schedule Type") { step = .howOften }
                Spacer()
                Button("Done") { step = .collapsed }
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Helpers

    private func makeDraft(hour: Int, minute: Int) -> ScheduleDraft {
        ScheduleDraft(
            hour: hour, minute: minute,
            frequency: everyDay ? "daily" : "custom",
            daysOfWeek: everyDay ? [] : daysOfWeek
        )
    }

    /// If editing an existing medication (per `isEditingExistingMedication`, passed
    /// straight through from `AddEditMedicationViewModel.isEditing` — not inferred
    /// from the schedule data, since a genuinely-edited once-daily-8am-every-day
    /// schedule is indistinguishable from a fresh unedited draft by data alone),
    /// seed the local flow state and jump straight to the collapsed summary per the
    /// spec's re-entry rule — never restart at Q1 for an existing schedule.
    private func seedStateFromExistingSchedules() {
        guard isEditingExistingMedication, let first = schedules.first else { return }
        everyDay = first.daysOfWeek.isEmpty
        daysOfWeek = first.daysOfWeek
        timesPerDay = schedules.count
        step = .collapsed
    }
}

private struct DayToggleButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(selected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

#Preview {
    Form {
        GuidedScheduleView(schedules: .constant([ScheduleDraft()]), medicationName: "Metformin", doseDescription: "500mg", isEditingExistingMedication: false)
    }
}
```

- [ ] **Step 3: Manual verification.** Since `GuidedScheduleView.isEditingExistingMedication` is a plain `Bool` parameter (not a heuristic inferred from the schedule data), there's no ambiguous case to test around — a genuinely-edited once-daily-8am-every-day medication and a fresh unedited draft are both handled correctly because the caller (Task 7) tells this view directly which one it is. Do a quick manual sanity check anyway: edit an existing once-daily medication and confirm it opens on the collapsed summary, not Question 1.

- [ ] **Step 4: Delete the old file** now that `GuidedScheduleView` supersedes it (Task 7 updates the only consumer):
```bash
git rm DoseTrack/Views/Medications/ScheduleBuilderView.swift
```
(Don't run this in isolation — do it together with Task 7's changes and commit once, so the repo never has a broken intermediate state where the old view is deleted but its only call site still references it.)

### Task 7: Wire `GuidedScheduleView` into `AddEditMedicationView`

**Files:**
- Modify: `DoseTrack/Views/Medications/AddEditMedicationView.swift:114-126`

- [ ] **Step 1: Replace the old per-row Schedule section.** Read the file's current Schedule section (already quoted in this plan's research above — `ForEach($viewModel.schedules) { $draft in ScheduleBuilderView(draft: $draft) }` plus the "Add Another Time" button and `.onDelete`) and replace the whole block with:

```swift
// MARK: Schedule
Section("Schedule") {
    GuidedScheduleView(
        schedules: $viewModel.schedules,
        medicationName: viewModel.name.isEmpty ? "this medication" : viewModel.name,
        doseDescription: viewModel.doseAmount.isEmpty ? "a dose" : "\(viewModel.doseAmount)\(viewModel.doseUnit)",
        isEditingExistingMedication: viewModel.isEditing
    )
}
```

- [ ] **Step 2: Build.** `xcodebuild -project DoseTrack.xcodeproj -scheme DoseTrack -sdk iphonesimulator build 2>&1 | tail -40` — quote actual output, expect `** BUILD SUCCEEDED **`. This is the step that proves `ScheduleBuilderView`'s deletion (Task 6 Step 4) didn't leave a dangling reference anywhere.

- [ ] **Step 3: Run the full test suite** to confirm nothing regressed: `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -100`, quote the actual pass/fail summary (expect the known pre-existing `NotificationSchedulerTests` full-suite flake to be the only possible failure, passing in isolation as it always has in this repo).

- [ ] **Step 4: Run `xcodegen generate`** (in case any file membership changed from the deletion) and confirm via grep that `ScheduleBuilderView` no longer appears in `project.pbxproj` while `GuidedScheduleView` does.

- [ ] **Step 5: Manual verification.** Build and install into the simulator (`xcrun simctl install <device-id> <path-to-.app>` then `xcrun simctl launch <device-id> com.robbrown.dosetrack` — reuse whichever simulator device/id is already running from prior manual testing in this session if one exists), then walk through: adding a new medication with the default once-daily flow, editing it to 3 times/day tied to meals, and confirming Settings → Preferences → Meal Times shows/edits the same values used during that flow.

- [ ] **Step 6: Commit** (this is the single commit that both deletes the old file and wires in the new one, per Task 6 Step 4's note):

```bash
git add -A
git commit -m "feat: replace flat schedule form with guided question-driven flow"
```

### Task 8: Full test suite confirmation

**Files:** none (verification only)

- [ ] **Step 1:** `xcodebuild test -project DoseTrack.xcodeproj -scheme DoseTrack -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -100` — quote the literal summary line. Confirm the new tests from Tasks 2 and 5 (`MealTimesTests`, `ScheduleGeneratorTests`) are present and passing alongside every pre-existing suite, with the known `NotificationSchedulerTests` full-suite flake (if it occurs) verified to pass in isolation exactly as documented in every prior task in this repo's history.
- [ ] **Step 2:** No commit needed if nothing changed in this step (pure verification) — if you had to fix anything to get here, that fix gets its own commit with a message describing what broke and why.
