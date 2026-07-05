# DoseTrack iOS — Claude Code Project Brief

> **Claude Code:** Read this entire document before writing a single line of code. Use every capability available to you at every step — web search for current Apple API documentation, bash for scaffolding and validation, file tools for code generation, and your full reasoning capacity for architecture decisions. Never wait to be asked to use a tool or capability. If something can be automated, automate it.

---

## 1. Project Overview

**App name:** DoseTrack  
**Tagline:** Never miss a dose.  
**Platform:** iOS 17+ (minimum), watchOS 10+ (companion)  
**Language:** Swift 5.9+ / SwiftUI  
**Architecture:** MVVM  
**Local path:** `/Users/robbrown/CodingProjects/Apps/dosetrack-ios`  
**Bundle ID:** `com.robbrown.dosetrack`  
**App Store category:** Health & Fitness  

### First-time setup

`DoseTrack/Resources/Secrets.swift` is gitignored and required to build. Copy
`Secrets.example.txt` (repo root) to `DoseTrack/Resources/Secrets.swift` and fill in your
Supabase project URL/anon key.

### What DoseTrack is

A medication and supplement tracker that wins on three things competitors fail at:

1. **Reliable notifications** — reminders that actually fire, every time, including on Apple Watch
2. **Local-first data** — no forced account, data lives on device, always exportable
3. **Honest free tier** — 5 medications free forever, transparent upgrade path

### Why this exists right now

Medisafe (the dominant free medication tracker) moved to a mandatory paid subscription in January 2026, displacing millions of users. Those users are actively searching for alternatives. DoseTrack is the clean, trustworthy replacement they're looking for.

---

## 2. Claude Code Operating Instructions

**These instructions apply at every step. Do not wait to be asked.**

- **Search before assuming.** Before implementing any Apple framework feature (StoreKit 2, WidgetKit, WatchKit, CloudKit, UNUserNotificationCenter, HealthKit), web search the current Apple developer documentation. APIs evolve. Use what's current for iOS 17+ / Xcode 16+.
- **Validate as you build.** After every major component, compile and check for errors in bash. Don't accumulate broken code.
- **Generate boilerplate automatically.** Use bash scripts to scaffold repetitive files (model structs, preview providers, test stubs). Don't hand-type what can be generated.
- **Write tests as you go.** Every ViewModel and service layer function gets a unit test. Don't defer testing to the end.
- **Check Apple Human Interface Guidelines** for any UI pattern you're unsure about — web search `site:developer.apple.com HIG [component]`.
- **Use Swift Package Manager** for all dependencies. No CocoaPods.
- **Commit-ready code only.** Every file you write should be production-quality, properly commented, and free of TODO placeholders before moving to the next milestone.

---

## 3. Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| UI | SwiftUI | iOS 17+ features permitted |
| Data (local) | CoreData | With CloudKit sync for Pro |
| Notifications | UNUserNotificationCenter | + Critical Alerts entitlement |
| Widgets | WidgetKit | Interactive widgets (iOS 17+) |
| Watch | WatchKit + SwiftUI | watchOS 10+ companion |
| Subscriptions | StoreKit 2 | Native Swift async/await API |
| Cloud sync | CloudKit | Pro tier only |
| Charts | Swift Charts | Adherence visualisation |
| Export | UIActivityViewController | CSV + PDF |
| PDF generation | PDFKit | Doctor reports |

**No third-party dependencies for core functionality.** If a Swift package is genuinely needed, use SPM and document the reason in a comment.

---

## 4. CoreData Schema

Create a CoreData model named `DoseTrack.xcdatamodeld` with the following entities.

### Entity: Medication

| Attribute | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key, auto-generated |
| `name` | String | e.g. "Metformin" |
| `dosage` | String | e.g. "500mg" |
| `unit` | String | "pill", "ml", "mg", "injection", "supplement" |
| `colorHex` | String | Hex string for UI colour coding |
| `photoData` | Binary Data | Optional bottle photo, allows external storage |
| `notes` | String | Optional free text |
| `isActive` | Boolean | Soft delete / suspend support |
| `currentCount` | Integer32 | Current pill/dose count for refill tracking |
| `refillThreshold` | Integer32 | Alert when count drops below this |
| `totalDosesPerDay` | Integer32 | Computed from schedules |
| `createdAt` | Date | |
| `sortOrder` | Integer32 | User-defined sort |

**Relationships:**
- `schedules` → Schedule (one-to-many, cascade delete)
- `doseLogs` → DoseLog (one-to-many, cascade delete)

---

### Entity: Schedule

| Attribute | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `hour` | Integer16 | 0–23 |
| `minute` | Integer16 | 0–59 |
| `daysOfWeek` | Transformable | `[Int]` — 1=Sun through 7=Sat. Empty = every day |
| `frequency` | String | "daily", "weekly", "custom", "as_needed" |
| `intervalDays` | Integer16 | For "every N days" schedules |
| `isEnabled` | Boolean | Allow disabling individual schedules |
| `notificationIds` | Transformable | `[String]` — UNNotificationRequest identifiers |

**Relationships:**
- `medication` → Medication (many-to-one)

---

### Entity: DoseLog

| Attribute | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `scheduledAt` | Date | When the dose was due |
| `loggedAt` | Date | When user confirmed/skipped |
| `status` | String | "taken", "skipped", "missed" |
| `notes` | String | Optional user note |

**Relationships:**
- `medication` → Medication (many-to-one)

---

### CoreData Configuration

```swift
// In PersistenceController.swift
// Use NSPersistentCloudKitContainer for Pro users
// Use NSPersistentContainer for free users
// Switch containers when subscription status changes
```

Enable CloudKit sync only when Pro subscription is active. Store subscription status in `UserDefaults` and re-initialise the persistence stack when it changes.

---

## 5. Subscription & Paywall (StoreKit 2)

### Products

Define these in App Store Connect AND in a local `Products.storekit` configuration file for development:

| Product ID | Type | Price | Description |
|---|---|---|---|
| `com.robbrown.dosetrack.pro.monthly` | Auto-renewable subscription | $3.99/mo | Pro Monthly |
| `com.robbrown.dosetrack.pro.annual` | Auto-renewable subscription | $29.99/yr | Pro Annual |

### SubscriptionManager

```swift
// Services/SubscriptionManager.swift
// Use StoreKit 2's Product and Transaction APIs
// Implement with @MainActor and async/await
// Cache entitlement status in UserDefaults for offline access
// Listen to Transaction.updates for real-time status changes
```

Key methods:
- `checkEntitlement() async -> Bool`
- `purchase(_ product: Product) async throws`
- `restorePurchases() async`
- `isProSubscriber: Bool` (published property)

### Free Tier Limits

- Maximum 5 medications (check before allowing new medication creation)
- No family/caregiver sharing
- No iCloud sync
- No PDF doctor reports
- All other features fully functional

### Paywall Trigger Points

Show paywall when:
1. User tries to add medication #6
2. User taps "Family Sharing" in settings
3. User taps "Sync to iCloud" in settings
4. User taps "Doctor Report" in history

**Paywall design:** Native SwiftUI sheet. Show both monthly and annual options. Highlight annual with "Best Value — Save 37%" badge. Always include restore purchases button. 7-day free trial messaging on monthly plan.

---

## 6. Notification Architecture

> **Critical:** This is the app's primary value proposition. Get this right before anything else.

### Setup

```swift
// Services/NotificationManager.swift
```

Request authorisation at onboarding with `.alert`, `.sound`, `.badge`. Also request `.criticalAlert` entitlement — this requires a separate entitlement from Apple (`com.apple.developer.usernotifications.critical-alerts`). Add it to the entitlements file and note in the App Store review notes that the app is for medication reminders where missing a dose can have medical consequences.

### Notification Categories & Actions

Register these categories on app launch:

```swift
// Category: "MEDICATION_DUE"
// Actions:
//   - "TAKE_DOSE"    title: "Taken ✓"     foreground: false
//   - "SKIP_DOSE"    title: "Skip"          foreground: false  
//   - "SNOOZE_30"    title: "Snooze 30 min" foreground: false
```

Handle actions in `AppDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)` — log the DoseLog entry immediately without opening the app.

### Scheduling Logic

```swift
// Services/NotificationScheduler.swift
```

- Schedule notifications up to 64 days in advance (iOS limit is 64 pending notifications per app)
- On each app open, refresh the notification queue for the next 30 days
- After a medication is added, edited, or deleted, cancel all notifications for that medication and reschedule
- Use `UNCalendarNotificationTrigger` not `UNTimeIntervalNotificationTrigger` — calendar triggers survive device restarts

**Notification payload:**
```swift
content.title = medication.name
content.body = "Time to take \(medication.dosage)"
content.sound = .defaultCritical  // For critical alerts
content.userInfo = [
    "medicationId": medication.id.uuidString,
    "scheduleId": schedule.id.uuidString,
    "scheduledAt": scheduledDate.timeIntervalSince1970
]
content.categoryIdentifier = "MEDICATION_DUE"
```

### watchOS Notification Mirroring

iOS notifications mirror to Apple Watch automatically, but you must configure the watch notification interface explicitly:

```swift
// WatchApp/NotificationController.swift (WatchKit Extension)
// Implement WKUserNotificationHostingController
// Show medication name, dose, and action buttons
// Do NOT rely on automatic mirroring for action buttons — register categories on the watch too
```

In the Watch extension's `ExtensionDelegate`, register the same notification categories as on iOS so action buttons appear on the watch face.

---

## 7. WidgetKit — Home Screen & Lock Screen Widgets

> **Requires iOS 17+ for interactive widgets (mark-as-taken from home screen).**

### Widget Types to Build

1. **Small widget** — Next upcoming dose name + time countdown
2. **Medium widget** — Today's medication list with taken/pending status + interactive checkboxes
3. **Lock screen widget** (rectangular) — Next dose name + time

### Widget Timeline Provider

```swift
// Widgets/DoseTrackWidget.swift
```

- `getTimeline()` generates entries for the next 24 hours
- Each entry contains a snapshot of due medications at that time
- Reload policy: `.after(nextDoseDate)` — reload exactly when the next dose is due
- Use `AppGroup` to share CoreData between app and widget extension

### App Group Setup

Create an App Group: `group.com.robbrown.dosetrack`

Use this group for:
- Shared `NSPersistentContainer` store URL
- Shared `UserDefaults` for subscription status and settings

```swift
// In PersistenceController — use FileManager.containerURL(forSecurityApplicationGroupIdentifier:)
// for the persistent store URL so widgets can read the same data
```

### Interactive Widget (iOS 17+)

```swift
// Use AppIntent for widget button actions
struct MarkDoseTakenIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Dose Taken"
    @Parameter(title: "Medication ID") var medicationId: String
    @Parameter(title: "Scheduled At") var scheduledAt: Date
    
    func perform() async throws -> some IntentResult {
        // Write DoseLog entry to shared CoreData store
        // Update widget timeline
        return .result()
    }
}
```

---

## 8. Apple Watch Companion App

### Architecture

- Standalone WatchKit app (not just a notification extension)
- Uses WatchConnectivity framework to sync with iPhone when in range
- Falls back to direct CloudKit reads for Pro users when iPhone isn't nearby

### Watch Screens

1. **Today view** — Scrollable list of today's medications with status indicators. Tap to mark taken.
2. **Next dose** — Single large display of the next upcoming dose. Complication source.
3. **Notification interface** — Custom notification view with Taken/Skip/Snooze buttons

### Watch Complication

```swift
// WatchApp/Complications/DoseTrackComplication.swift
// Support: .modularSmall, .circularSmall, .graphicCorner, .graphicCircular
// Show: next dose time + medication name truncated to fit
// Reload: after each dose time passes
```

### WatchConnectivity Sync

```swift
// Services/WatchConnectivityManager.swift
// Send medication list and today's schedule to watch on each app open
// Watch sends dose confirmations back to iPhone
// Handle the case where watch is not paired (graceful degradation)
```

---

## 9. Screen Architecture & Navigation

```
TabView (bottom tabs)
├── Tab 1: Today          (house icon)
├── Tab 2: Medications    (pill icon)  
├── Tab 3: History        (calendar icon)
└── Tab 4: Settings       (gear icon)
```

### Tab 1: Today Screen

- Header: greeting + date + daily adherence score ("3 of 4 doses taken")
- List of all medications due today, grouped by time slot
- Each row: colour dot + medication name + dose + time + status chip
- Tap row → Mark Taken / Skip / Snooze sheet
- Upcoming section: medications due later today
- Empty state: "All doses taken for today 🎉"

### Tab 2: Medications Screen

- List of all active medications
- Each row: colour dot + name + dose + next due time + refill warning if low
- FAB (+) button to add medication — check free tier limit before presenting form
- Swipe left: Edit / Delete (with confirmation)
- Tap row → Medication Detail screen

**Add/Edit Medication Form:**
- Name field (with autocomplete suggestions — common medication names)
- Dose field + unit picker
- Colour picker (8 preset colours)
- Schedule builder (time picker + days of week)
- Pill count field + refill threshold
- Optional photo (camera or photo library)
- Notes field

### Tab 3: History Screen

- Week/Month/Custom date range toggle
- Adherence chart (Swift Charts — bar chart, one bar per day, coloured by adherence %)
- Per-medication breakdown below chart
- Calendar view option (month grid, coloured dots per day)
- Export button → CSV (free) | PDF report (Pro paywall)

### Tab 4: Settings Screen

- **My Medications** shortcut
- **Notifications** — test notification button, critical alerts toggle
- **Subscription** — current plan, upgrade/manage button
- **Family Sharing** — Pro feature
- **iCloud Sync** — Pro feature, toggle
- **Export Data** — CSV export (always free)
- **Reminders** — default snooze duration, sound selection
- **About** — version, privacy policy link, rate app link
- **Delete All Data** — with strong confirmation

---

## 10. Onboarding Flow

3-screen onboarding shown on first launch only:

1. **Welcome** — App name + tagline + illustration
2. **Notifications permission** — Explain why notifications are needed. Request permission here, not at app launch.
3. **Add first medication** — Inline version of the add form. User can skip.

Store `hasCompletedOnboarding` in UserDefaults. Never show again after completion.

---

## 11. Data Export

### CSV Export (Free)

Generate a CSV with columns: `Date, Medication, Dose, Status, Time Taken, Notes`

```swift
// Services/ExportManager.swift
func generateCSV(from logs: [DoseLog], dateRange: DateInterval) -> Data
```

Present via `UIActivityViewController` — user can AirDrop, email, save to Files.

### PDF Doctor Report (Pro)

```swift
// Services/ReportGenerator.swift
// Use PDFKit to generate a formatted report
// Include: patient name (from Settings), date range, per-medication adherence table
// Header: "Medication Adherence Report — Generated by DoseTrack"
// Disclaimer footer: "This report is a reminder tool record only and does not constitute medical advice."
```

---

## 12. Build Phases & Execution Order

Work through these in strict order. Do not begin the next phase until the current one compiles and runs on simulator.

### Phase 1 — Project Setup & Data Layer
1. Create Xcode project (SwiftUI, iOS 17+, include Tests target)
2. Create App Group entitlement
3. Build CoreData model (all three entities)
4. Write `PersistenceController` with both `NSPersistentContainer` and `NSPersistentCloudKitContainer` paths
5. Write unit tests for CoreData CRUD operations
6. Create `Products.storekit` configuration file
7. Write `SubscriptionManager` with StoreKit 2
8. Create `CLAUDE.md` (this file) in the project root

### Phase 2 — Core UI
1. Build `TabView` shell with placeholder screens
2. Build Today screen (read-only first, no actions yet)
3. Build Medications list screen
4. Build Add/Edit Medication form
5. Build Medication Detail screen
6. Write UI snapshot tests for all screens

### Phase 3 — Notifications Engine
1. Build `NotificationManager` (authorisation, categories, actions)
2. Build `NotificationScheduler` (scheduling, cancellation, refresh)
3. Handle notification action responses (mark taken/skip/snooze without opening app)
4. Add background refresh task to refresh notification queue
5. Write unit tests for scheduling logic (mock `UNUserNotificationCenter`)

### Phase 4 — History & Adherence
1. Build History screen with Swift Charts bar chart
2. Build calendar month view
3. Implement adherence score calculation
4. Build `ExportManager` (CSV)
5. Build `ReportGenerator` (PDF, Pro-gated)

### Phase 5 — Widgets
1. Add WidgetKit extension target
2. Configure shared App Group for CoreData access
3. Build Small widget
4. Build Medium interactive widget (AppIntent for mark-as-taken)
5. Build Lock screen widget
6. Write widget timeline tests

### Phase 6 — Apple Watch
1. Add WatchKit App + Extension targets
2. Build `WatchConnectivityManager`
3. Build Watch Today screen
4. Build Watch notification interface
5. Build Watch complication
6. Test on simulator (no physical device needed for initial build)

### Phase 7 — Polish & Submission Prep
1. Implement Haptic feedback on dose confirmation (`.success` impact)
2. Implement Dynamic Type support (all text scales with system font size)
3. Implement Dark Mode (verify all screens)
4. Implement accessibility labels on all interactive elements
5. Add App Store privacy nutrition label manifest (`PrivacyInfo.xcprivacy`)
6. Add Critical Alerts entitlement (`com.apple.developer.usernotifications.critical-alerts`)
7. Add usage descriptions to `Info.plist`: camera, photo library, health
8. Run all unit tests — 100% pass required before submission
9. Generate App Store screenshots for all required device sizes

---

## 13. Key Technical Decisions & Rationale

| Decision | Rationale |
|---|---|
| iOS 17+ minimum | Required for interactive WidgetKit buttons (mark-as-taken from home screen). This covers 90%+ of active devices as of mid-2026. |
| CoreData not SwiftData | SwiftData's CloudKit sync support is still maturing. CoreData + NSPersistentCloudKitContainer is proven and stable. |
| Local-first, account optional | Core brand promise. Data never leaves the device without explicit user action. This is the key trust differentiator from Medisafe. |
| StoreKit 2 | Native async/await API. No RevenueCat or third-party dependency needed for a two-product subscription setup this simple. |
| UNCalendarNotificationTrigger | Survives device restarts and timezone changes. Never use time interval triggers for medication reminders. |
| Swift Charts not third-party | Native, zero-dependency, sufficient for adherence bar/line charts at this scope. |
| PDFKit not HTML-to-PDF | Native framework, no WebKit dependency, appropriate for structured tabular reports. |

---

## 14. Critical Rules — Never Violate These

1. **Never store medication data on a server without explicit user opt-in.** Free tier is 100% local.
2. **Never put a hard paywall on core reminder functionality.** Unlimited medications is Pro. Reminders always work on free tier.
3. **Never use `UNTimeIntervalNotificationTrigger` for recurring medication reminders.** It doesn't survive restarts.
4. **Never show a paywall on first app open.** The user must experience the app first.
5. **Never delete a medication permanently without a soft-delete confirmation step.** Use `isActive = false` first, then offer permanent delete.
6. **Always include the disclaimer** on any medical-adjacent UI: *"DoseTrack is a reminder tool, not medical advice. Always follow your healthcare provider's instructions."*
7. **Data export must always be free.** Never gate CSV export behind Pro. Users own their data.
8. **The refill countdown must work on the free tier.** It is a safety feature, not a premium feature.

---

## 15. File Structure

```
dosetrack-ios/
├── CLAUDE.md                          ← This file
├── DoseTrack.xcodeproj
├── DoseTrack/
│   ├── App/
│   │   ├── DoseTrackApp.swift
│   │   ├── AppDelegate.swift          ← Notification delegate
│   │   └── PersistenceController.swift
│   ├── Models/
│   │   ├── DoseTrack.xcdatamodeld
│   │   ├── Medication+Extensions.swift
│   │   ├── Schedule+Extensions.swift
│   │   └── DoseLog+Extensions.swift
│   ├── Services/
│   │   ├── NotificationManager.swift
│   │   ├── NotificationScheduler.swift
│   │   ├── SubscriptionManager.swift
│   │   ├── ExportManager.swift
│   │   ├── ReportGenerator.swift
│   │   └── WatchConnectivityManager.swift
│   ├── ViewModels/
│   │   ├── TodayViewModel.swift
│   │   ├── MedicationsViewModel.swift
│   │   ├── HistoryViewModel.swift
│   │   └── SettingsViewModel.swift
│   ├── Views/
│   │   ├── Today/
│   │   │   ├── TodayView.swift
│   │   │   ├── DoseRowView.swift
│   │   │   └── DoseActionSheet.swift
│   │   ├── Medications/
│   │   │   ├── MedicationsView.swift
│   │   │   ├── MedicationDetailView.swift
│   │   │   ├── AddEditMedicationView.swift
│   │   │   └── ScheduleBuilderView.swift
│   │   ├── History/
│   │   │   ├── HistoryView.swift
│   │   │   ├── AdherenceChartView.swift
│   │   │   └── CalendarView.swift
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift
│   │   │   └── FamilySharingView.swift
│   │   ├── Onboarding/
│   │   │   └── OnboardingView.swift
│   │   └── Paywall/
│   │       └── PaywallView.swift
│   ├── Utilities/
│   │   ├── ColorExtensions.swift
│   │   ├── DateExtensions.swift
│   │   └── Constants.swift
│   └── Resources/
│       ├── Assets.xcassets
│       ├── Info.plist
│       ├── DoseTrack.entitlements
│       └── Products.storekit
├── DoseTrackWidgets/
│   ├── DoseTrackWidgets.swift
│   ├── SmallWidget.swift
│   ├── MediumWidget.swift
│   ├── LockScreenWidget.swift
│   ├── MarkDoseTakenIntent.swift
│   └── WidgetBundle.swift
├── DoseTrackWatch Watch App/
│   ├── DoseTrackWatchApp.swift
│   ├── TodayWatchView.swift
│   ├── NotificationController.swift
│   └── ComplicationProvider.swift
└── DoseTrackTests/
    ├── CoreDataTests.swift
    ├── NotificationSchedulerTests.swift
    ├── SubscriptionManagerTests.swift
    ├── ExportManagerTests.swift
    └── AdherenceCalculatorTests.swift
```

---

## 16. App Store Submission Checklist

Before submitting, verify every item:

- [ ] `PrivacyInfo.xcprivacy` manifest complete — declare data types collected
- [ ] Privacy policy URL live and linked in App Store Connect
- [ ] Critical Alerts entitlement added and justification written for review notes
- [ ] All `Info.plist` usage descriptions present (camera, photo library)
- [ ] Disclaimer text present in onboarding and Settings → About
- [ ] Screenshots generated for iPhone 15 Pro Max, iPhone SE (3rd gen), iPad Pro 12.9"
- [ ] App preview video optional but recommended
- [ ] Age rating: 4+ (no mature content)
- [ ] Review notes explain: medication reminder use case, why critical alerts are needed
- [ ] TestFlight build tested on physical device before submission
- [ ] Subscription terms URL linked in App Store Connect

---

*Last updated: June 2026. Built by Rob Brown using Claude Code.*
