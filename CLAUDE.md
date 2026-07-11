# DoseTrack iOS — Claude Code Project Brief

> **Claude Code:** Read this entire document before writing a single line of code. Use every capability available to you at every step — web search for current Apple API documentation, bash for scaffolding and validation, file tools for code generation, and your full reasoning capacity for architecture decisions. Never wait to be asked to use a tool or capability. If something can be automated, automate it.

> **This is a living document.** DoseTrack is built and shipping (currently build 21). Sections 1–11 and 13–16 describe the app as it actually exists today, not just as originally planned — keep them in sync with the codebase as it changes. Section 12 ("Build Phases") is a historical record of how the app was originally built; new work should be logged in §12b instead of rewriting the phases.

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
**Legal entity:** Neurotrocity

### First-time setup

`DoseTrack/Resources/Secrets.swift` is gitignored and required to build. Copy
`Secrets.example.txt` (repo root) to `DoseTrack/Resources/Secrets.swift` and fill in your
Supabase project URL/anon key.

### What DoseTrack is

A medication and supplement tracker that wins on three things competitors fail at:

1. **Reliable notifications** — reminders that actually fire, every time, including on Apple Watch. Reminder copy is drawn from a large, varied pool (233+ lines) so it never feels robotic, and never states dose/pill-count information (the patient already knows their own dose).
2. **Local-first data** — no forced account, data lives on device, always exportable. Signing in adds cross-device sync and caregiver sharing via Supabase, but nothing is required to use the app fully.
3. **Honest free tier** — 5 medications free forever, transparent upgrade path. Pro features are shown (not hidden) to free users, dimmed with a lock badge, so people can see what they're missing rather than not knowing it exists.

### Why this exists right now

Medisafe (the dominant free medication tracker) moved to a mandatory paid subscription in January 2026, displacing millions of users. Those users are actively searching for alternatives. DoseTrack is the clean, trustworthy replacement they're looking for.

---

## 2. Claude Code Operating Instructions

**These instructions apply at every step. Do not wait to be asked.**

- **Search before assuming.** Before implementing any Apple framework feature (StoreKit 2, WidgetKit, WatchKit, VisionKit, UNUserNotificationCenter), web search the current Apple developer documentation. APIs evolve. Use what's current for iOS 17+ / Xcode 16+.
- **Validate as you build.** After every major component, compile and check for errors in bash. Don't accumulate broken code.
- **Generate boilerplate automatically.** Use bash scripts to scaffold repetitive files (model structs, preview providers, test stubs). Don't hand-type what can be generated.
- **Write tests as you go.** Every ViewModel and service layer function gets a unit test. Don't defer testing to the end.
- **Check Apple Human Interface Guidelines** for any UI pattern you're unsure about — web search `site:developer.apple.com HIG [component]`.
- **Use Swift Package Manager** for all dependencies. No CocoaPods.
- **Commit-ready code only.** Every file you write should be production-quality, properly commented, and free of TODO placeholders before moving to the next milestone.
- **Ask before pushing an iOS visual/Today-tab change to watchOS too.** The watch app previously drifted out of sync with iOS (old mascot art, old splash) because updates weren't deliberately mirrored. Don't assume either way — ask.

---

## 3. Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| UI | SwiftUI | iOS 17+ features permitted |
| Data (local) | CoreData | Plain `NSPersistentContainer`. **Not** CloudKit-synced — see Cloud sync row below. |
| Cloud sync & auth | **Supabase** (Postgres + Auth) | `SupabaseSyncManager` pushes/pulls medications, schedules, dose logs, settings, and disclaimer acceptance. Not gated behind Pro — any signed-in account gets sync; caregiver *sharing* (viewing another account) is the Pro capability, not sync itself. |
| Notifications | UNUserNotificationCenter | Reminder body text drawn from `NotificationCopy` (see §6) |
| OCR / document scanning | Vision + VisionKit | Medication box scanner — see §6b |
| Widgets | WidgetKit | Interactive widgets (iOS 17+) |
| Watch | WatchKit + SwiftUI | watchOS 10+ companion, visually mirrors iOS (see §8) |
| Subscriptions | StoreKit 2 | Native Swift async/await API |
| Charts | Swift Charts | Adherence visualisation |
| Export | UIActivityViewController | CSV + PDF |
| PDF generation | PDFKit | Doctor reports |

**No third-party dependencies for core functionality** beyond the Supabase Swift SDK and Google Sign-In (both via SPM). If another package is genuinely needed, use SPM and document the reason in a comment.

---

## 4. CoreData Schema

`DoseTrack.xcdatamodeld` (local-only store; sync to Supabase is handled separately by `SupabaseSyncManager`, not CloudKit).

### Entity: Medication

| Attribute | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `name` | String | e.g. "Metformin" |
| `dosage` | String | Per-unit strength, e.g. "500mg" (NOT the total per-dose amount — see `totalDosesPerDay`) |
| `unit` | String | Form factor: "tablet", "capsule", "pill", "ml", "injection", "inhaler", "spray", "patch", "drop", "sachet", "suppository", "lozenge", "supplement", "contraceptive" |
| `colorHex` | String | Hex string for UI colour coding (24-colour palette, see §13) |
| `photoData` | Binary Data | Optional bottle photo, external storage |
| `escriptData` | Binary Data | Optional Australian E-Script QR code image, external storage |
| `notes` | String | Optional free text |
| `isActive` | Boolean | Soft delete / suspend support |
| `currentCount` | Integer32 | Current pill/dose count for refill tracking |
| `refillThreshold` | Integer32 | Alert when count drops below this |
| `totalDosesPerDay` | Integer32 | quantity-per-dose × enabled schedule count — the actual daily consumption rate |
| `sortOrder` | Integer32 | User-defined sort |
| `createdAt` / `updatedAt` | Date | `updatedAt` also doubles as the "out of stock since" marker (see `Medication.isOutOfStockOverADay`) |

**Relationships:** `schedules` → Schedule (one-to-many, cascade delete), `doseLogs` → DoseLog (one-to-many, cascade delete)

### Entity: Schedule

| Attribute | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `hour` / `minute` | Integer16 | 0–23 / 0–59 |
| `daysOfWeek` | Transformable | `[Int]` — 1=Sun through 7=Sat. Empty = every day |
| `frequency` | String | "daily", "weekly", "custom", "as_needed" |
| `intervalDays` | Integer16 | For "every N days" / contraceptive schedules |
| `isEnabled` | Boolean | |
| `notificationIds` | Transformable | `[String]` — pending `UNNotificationRequest` identifiers |
| `routineLabel` | String? | Set when this schedule was linked to a Daily Routine Time (e.g. "Bedtime", "Wake Up") instead of a manually-picked clock time. When set, Today shows the routine name instead of a time, since the actual fire time follows wherever that routine is set in Settings. Cleared if the time is later hand-edited. |

**Relationships:** `medication` → Medication (many-to-one)

### Entity: DoseLog

| Attribute | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `scheduledAt` | Date | When the dose was due |
| `loggedAt` | Date | When user confirmed/skipped |
| `status` | String | "taken", "skipped", "missed" |
| `notes` | String | Optional user note |

**Relationships:** `medication` → Medication (many-to-one)

---

## 5. Subscription & Paywall (StoreKit 2)

### Products

| Product ID | Type | Price |
|---|---|---|
| `com.robbrown.dosetrack.pro.monthly` | Auto-renewable subscription | $3.99/mo (7-day free trial) |
| `com.robbrown.dosetrack.pro.annual` | Auto-renewable subscription | $29.99/yr ("Best Value — Save 37%") |

Local dev config: `DoseTrack/Resources/Products.storekit`.

### SubscriptionManager (`Services/SubscriptionManager.swift`)

`@MainActor`, async/await, `Product`/`Transaction` APIs. Caches entitlement in `UserDefaults` for offline access. Listens to `Transaction.updates`. Key surface: `isProSubscriber: Bool` (published), `purchase(_:)`, `restorePurchases()`.

### Free Tier Limits (Pro unlocks)

- Maximum 5 medications
- Caring for someone else's medications (caregiver mode — inviting a caregiver to watch *your* meds is free; being able to manage *someone else's* is Pro)
- PDF adherence reports (CSV export is always free)
- Choosing an alternate app icon (see §7b)

**All Pro features remain visible to free users** — dimmed with a lock badge (`GhostedProRow` pattern in `SettingsView.swift`) rather than hidden, so the upgrade path is discoverable. Tapping a ghosted row still opens the paywall.

### Paywall Trigger Points

1. User tries to add medication #6
2. User taps "Care for Someone" in Settings
3. User taps "Adherence Report (PDF)" in History
4. User taps "App Icon" in Settings (Preferences)

**Paywall design:** Native SwiftUI sheet (`Views/Paywall/PaywallView.swift`). Gradient hero with the Milli mascot, feature list, both monthly/annual pricing cards, "Best Value — Save 37%" badge on annual, restore purchases button, honest "coming soon" fallback state if StoreKit products aren't configured yet.

---

## 6. Notification Architecture

> **Critical:** This is the app's primary value proposition. Get this right before anything else.

### Setup (`Services/NotificationManager.swift`)

Authorization (`.alert`, `.sound`, `.badge`) is requested at two points, so every path is covered: onboarding's Notifications page, AND a safety-net check when the main app first appears (`RootView`) if the status is still `.notDetermined` — this catches Apple/Google sign-in, which skips onboarding entirely. Requesting when already-determined is a no-op, so nobody is double-prompted. `.criticalAlert` is deliberately NOT requested — no Apple entitlement for it.

### Notification Categories & Actions

Category `"MEDICATION_DUE"` with actions: `TAKE_DOSE` ("Taken ✓"), `SKIP_DOSE` ("Skip"), `SNOOZE_30` ("Snooze 30 min") — all `foreground: false`, handled in `AppDelegate` without opening the app.

### Scheduling Logic (`Services/NotificationScheduler.swift`)

- `UNCalendarNotificationTrigger` only — never `UNTimeIntervalNotificationTrigger` (doesn't survive restarts)
- Schedules up to 64 days ahead (iOS's 64-pending-notification limit); refreshed on each app open
- Cancels + reschedules a medication's notifications on add/edit/delete
- A dose logged (taken or skipped) cancels its own pending reminder

### Reminder copy (`Services/NotificationCopy.swift`)

**The notification body never shows dose amount or pill count** — just names the medication ("Don't forget to take your Metformin."). The patient already knows their own dose; the reminder's only job is to prompt.

Body text is drawn randomly from a large pool so reminders feel alive, not robotic:
- **117 general lines** — always in the pool
- **22 Wake-Up-window lines** + **22 Bedtime-window lines** — added to the pool when the schedule's hour falls within ±2h of the user's actual Settings → Daily Routine Times (not a fixed clock window)
- **8 medication-form pools** (tablet, capsule, pill, spray, inhaler, injection, patch, drop/liquid — 8–10 lines each) — added when the medication's `unit` matches

Every draw pulls from the *combined* pool (general + whichever gated pools apply), so a bedtime inhaler dose can still land a plain general line — sub-pools add variety, they don't take over. Implementation note: the per-piece animation (splash confetti, see §7a) uses the same "Animatable modifier, not a raw value fed into `.offset`/`.opacity`" pattern for a reason — see the comment in `RootView.swift`'s `ConfettiEffect`.

### watchOS Notification Mirroring

iOS notifications mirror to the Watch automatically; `DoseTrackWatch Watch App/NotificationController.swift` shows the medication + Taken/Skip/Snooze buttons. The same notification categories are registered on the watch too — automatic mirroring alone doesn't produce action buttons.

---

## 6b. Medication Box Scanner (Vision + VisionKit)

`Views/Medications/MedicationScannerView.swift`, backed by `Services/MedicationTextRecognizer.swift` and `Services/MedicationParser.swift`.

- **Capture:** `VNDocumentCameraViewController` (the same edge-detecting, deskewing, contrast-boosting scanner as Notes/Files) is the primary capture path; falls back to a plain photo picker where unsupported (Simulator).
- **OCR:** `MedicationTextRecognizer` runs `VNRecognizeTextRequest` with the image's actual `CGImagePropertyOrientation` — critical, since `UIImage.cgImage` is the raw sensor buffer with orientation NOT applied, so a naive request reads portrait photos rotated 90°. Also sorts results into reading order (Vision doesn't guarantee it).
- **Parsing:** `MedicationParser` picks the medication name by **text height** (the brand name is almost always the largest text on a box) with a casing/order fallback; extracts strength (`"500 mg"`, `"250mg/5mL"`, micrograms, etc.), pack count (`"30 Tablets"`, `"100's"`), and form. If Vision found text but the parser can't confidently pick a name, the user is shown the raw detected lines to tap the correct one themselves — never a wrong guess.
- Covered by real end-to-end tests that render a synthetic box image and run the *actual* Vision pipeline (`DoseTrackTests/MedicationTextRecognizerTests.swift`), including a portrait-capture regression guard.

---

## 7. WidgetKit — Home Screen & Lock Screen Widgets

> **Requires iOS 17+ for interactive widgets (mark-as-taken from home screen).**

- **Small widget** — next upcoming dose + countdown
- **Medium widget** — outstanding doses only, interactive checkboxes
- **`.systemLarge`** — more content than Medium (WidgetKit cannot support scrolling/dragging inside a widget at all, so Large is the substitute for "show more")
- **Lock screen widget** (rectangular) — next dose name + time
- **`MarkDoseTakenIntent`** (AppIntent, iOS 17+) writes the DoseLog to the shared App Group store and reloads the timeline

App Group: `group.com.robbrown.dosetrack` — shared CoreData store URL + shared `UserDefaults`.

---

## 8. Apple Watch Companion App

- Standalone WatchKit app target (`DoseTrackWatch Watch App`, embedded in the iOS app so it actually ships — see project.yml's `embed: true` comment)
- `WatchConnectivityManager` (iOS side) / `WatchConnectivityReceiver` (watch side) sync the day's medications; the watch sends dose confirmations back
- **Visually mirrors iOS deliberately**, not just functionally: the watch splash (`WatchRootView.swift`) uses the same light radial background + transparent Milli mascot + confetti-burst entrance as the iOS splash (scaled down), and Today (`TodayWatchView.swift`) uses the same transparent mascot art — kept in sync by convention, not by shared code (the watch target compiles independently). **Whenever an iOS visual/Today-tab change ships, ask whether it should go to watchOS too** — this drifted out of sync once already.
- Watch complications were explicitly deferred (evaluated, decided not worth the complexity for now) — do not build without reopening that decision.

---

## 9. Screen Architecture & Navigation

```
TabView (bottom tabs)
├── Tab 1: Today          (house icon)
├── Tab 2: Medications    (pill icon)
├── Tab 3: Restock        (cart icon)
├── Tab 4: History        (calendar icon)
└── Tab 5: Settings       (gear icon)
```

### Tab 1: Today Screen

- Header card: greeting + date + adherence ring ("5 of 11 doses taken") — turns green with a celebratory Milli mascot when everything's taken for the day
- Due/Past and Upcoming sections; each row shows colour-coded icon + name + dose + **either a clock time or the linked routine name** ("Bedtime" instead of "22:30" when the schedule was linked to a Daily Routine Time) + status chip
- Tap row → Mark Taken / Skip / Snooze sheet
- Expandable Alerts panel (refill warnings, etc.)

### Tab 2: Medications Screen

- List of active medications; colour-coded tile + name + dose + next due + refill warning if low
- **Out-of-stock nudge banner** at the top of the list for any medication that's sat at 0 supply for 24h+ — "Remove it or update your supply?" with both actions inline, dismissible per session
- FAB (+) to add — checks free tier limit first
- "Scan Medication Box" shortcut on the add form (see §6b)
- Swipe: Edit / Delete (soft delete)

### Tab 3: Restock Screen

- Supply-focused view of all medications, urgency-coloured (red/orange/yellow/green) by days-of-supply remaining
- E-Script QR code display for pharmacy pickup

### Tab 4: History Screen

- Week/Month/Custom range toggle, Swift Charts adherence bar chart, per-medication breakdown, calendar view
- Export: CSV (always free) | PDF adherence report (Pro, ghosted for free users — see §5)

### Tab 5: Settings Screen

- **Profile** — avatar (Milli or one of 9 character options, or a custom photo), name, DoseTrack Pro badge
- **Subscription** — plan status, upgrade/restore
- **Preferences** — App Preferences, Daily Routine Times (Wake Up / meals / Bedtime — feeds the notification-copy time gating and routine-linked schedules), Colour Coding, **App Icon** (Pro, ghosted for free — see §7b)
- **Caregiving** — Invite a Caregiver (free), Care for Someone (Pro, ghosted for free)
- **Notifications** — permission status, test notification button
- **Data & Privacy** — Privacy & Disclaimer (in-app summary page), Privacy Policy (external link — see §11b)
- **About** — version, delete all data (strong confirmation)

---

## 7b. Pro Alternate App Icons

`Services/AppIconManager.swift` + `Views/Settings/AppIconPickerView.swift`. Three colour variants (Midnight/dark, Mint, Lavender) generated from the same mascot art as the default icon, set via `UIApplication.shared.setAlternateIconName`. Icon files are loose PNGs under `DoseTrack/Resources/AlternateIcons/` (NOT in the `Assets.xcassets` `AppIcon.appiconset` — alternate icons must be plain bundle files), declared in `Info.plist`'s `CFBundleIcons.CFBundleAlternateIcons`. Settings row is Pro-gated via the ghosted-row pattern.

---

## 10. Onboarding & Account Flow

Actual order for a brand-new user:

1. **Splash** — animated, cold-launch only (see §13's design-language notes)
2. **Auth screen** — sign up / sign in / continue as guest
3. **If a NEW account was just created (never previously accepted): Medical Disclaimer & Terms** (§11a) — full-screen, must check the consent box and tap "I Agree" to proceed; "Decline & Sign Out" is the only other option. Shown once per identity, ever — recorded to the Supabase profile so it survives reinstalls, cached locally so it's instant on repeat launches. An existing account that happens to have never accepted (e.g. pre-dates this feature) also sees it once, then never again.
4. **3-page onboarding** (first-launch only, `hasCompletedOnboarding` in UserDefaults): Welcome → Notifications permission (requested here) → Add first medication (skippable)
5. Main app

**Guaranteed invariant:** every account-creation path (email, Apple, Google, guest) gets the notification permission prompt before they can reach the medication list — Apple/Google sign-in skip the 3-page onboarding entirely, so `RootView` has its own safety-net request (see §6).

---

## 11. Data Export

### CSV Export (Free, always)

`Services/ExportManager.swift` — `Date, Medication, Dose, Status, Time Taken, Notes`, shared via `UIActivityViewController`.

### PDF Doctor Report (Pro)

`Services/ReportGenerator.swift` (PDFKit) — patient name, date range, per-medication adherence table, header "Medication Adherence Report — Generated by DoseTrack", footer disclaimer: *"This report is a reminder tool record only and does not constitute medical advice."*

---

## 11a. Legal — Medical Disclaimer & Terms of Use

Shown once per account (§10) via `Views/Legal/DisclaimerView.swift` (`DisclaimerConsentView`) and summarized for reference any time in Settings → Data & Privacy → Privacy & Disclaimer (`SettingsView.swift`'s `DisclaimerView`, a shorter in-app summary — the two are named similarly but are different screens).

**Full text of the one-time acceptance screen** (source of truth: `DisclaimerContent` in `DoseTrack/Views/Legal/DisclaimerView.swift`):

> Please read this agreement carefully before using DoseTrack. It explains what DoseTrack is, what it is not, and the limits of our responsibility. You must accept these terms to use the app.
>
> **Not medical advice.** DoseTrack does not provide medical or pharmaceutical advice. It is a medication reminder tool only, and is only as accurate as the information you enter. Information shown in the app is for scheduling purposes only and must never replace advice given by a qualified medical practitioner. Always seek advice from a qualified medical practitioner before taking, changing, or stopping any medication.
>
> **Your responsibility.** You are solely responsible for entering all medication information and for verifying that everything you enter is correct. DoseTrack assumes no responsibility for errors in data entry, misinterpretation of medical instructions, or the consequences of taking the wrong medication or dosage.
>
> **Reminders may fail.** DoseTrack is a software application that relies on third-party hardware, operating systems, and networks, all of which are subject to failure. We do not guarantee that push notifications, alarms, or reminders will be delivered accurately, on time, or at all. You agree to use DoseTrack strictly as a supplementary backup reminder — never as your sole method for managing critical, life-sustaining, or time-sensitive medications.
>
> **In an emergency.** In the event of a medical emergency, a missed dose of a critical medication, an accidental overdose, or an adverse drug interaction, contact your local emergency services or a poison control centre immediately. Do not rely on DoseTrack for emergency assistance or instructions.
>
> **Limitation of liability.** DoseTrack will not be liable for the mismanagement of medication or for inaccurate inputs. To the maximum extent permitted by applicable law, in no event shall Neurotrocity, or its directors, employees, partners, agents, suppliers, or affiliates, be liable for any direct, indirect, incidental, special, consequential, punitive, or exemplary damages arising from your use of, or inability to use, DoseTrack.
>
> **Your agreement.** By tapping "I Agree" (or by checking the consent box or using DoseTrack), you acknowledge that you have read this agreement, understand it, and agree to be bound by its terms and conditions. You understand that you are waiving certain legal rights by agreeing to these terms.

**Acceptance is recorded** to the signed-in account's Supabase profile (`user_settings.disclaimer_accepted_at`, via `Services/DisclaimerManager.swift` + `SupabaseSyncManager`), and cached locally per-identity. Guests (no server profile) accept locally only. Requires the `20260710_add_disclaimer_accepted_at.sql` migration to be applied in Supabase for server-side persistence — the app degrades gracefully without it (local-only, not lost, just not synced).

## 11b. Legal — Privacy Policy

**Not stored in this repository.** Hosted externally at `https://4032332.github.io/dosetrack/privacy.html` (see `Constants.ExternalLinks.privacyPolicy`), linked from Settings → Data & Privacy. If you need the actual privacy policy text (e.g. to reproduce or summarize it on a marketing website), fetch that URL directly — do not assume or fabricate its contents.

---

## 12. Build Phases & Execution Order (historical)

This section documents how the app was originally built — Phases 1–7 are complete. **Do not re-run these phases**; for new work, add an entry to §12b instead of editing this list.

### Phase 1 — Project Setup & Data Layer ✅
Xcode project, App Group entitlement, CoreData model, `PersistenceController`, CoreData CRUD tests, `Products.storekit`, `SubscriptionManager`, this file.

### Phase 2 — Core UI ✅
`TabView` shell, Today/Medications/Add-Edit/Detail screens, UI tests.

### Phase 3 — Notifications Engine ✅
`NotificationManager`, `NotificationScheduler`, action handling, background refresh, scheduling tests. (Later substantially reworked — see §6 and §12b.)

### Phase 4 — History & Adherence ✅
Swift Charts bar chart, calendar view, adherence calculation, `ExportManager` (CSV), `ReportGenerator` (PDF, Pro-gated).

### Phase 5 — Widgets ✅
WidgetKit extension, shared App Group, Small/Medium/Large widgets, `MarkDoseTakenIntent`, timeline tests.

### Phase 6 — Apple Watch ✅
WatchKit app target, `WatchConnectivityManager`, watch Today screen, watch notification interface. (Complications deliberately deferred — see §8.)

### Phase 7 — Polish & Submission Prep ✅
Haptics, Dynamic Type, Dark Mode, accessibility labels, `PrivacyInfo.xcprivacy`, `Info.plist` usage descriptions, test suite, App Store screenshots.

## 12b. Post-Launch Feature Log (chronological, most recent first)

Kept brief — this is a log of *what* shipped and *why it mattered*, not a changelog of every commit. See git log for full detail.

- **Medical disclaimer/terms acceptance** (one-time, per-account, Supabase-recorded) — legal requirement before the app could responsibly ship. See §11a.
- **Notification-permission guarantee before medications can be added**, on every sign-up path — closed a gap where Apple/Google sign-in skipped the onboarding page that requested it.
- **Medication scanner rewrite** — orientation-aware OCR, VisionKit document scanner, height-based name detection. The scanner previously failed on almost all real (portrait) photos; root cause was a missing image-orientation parameter to Vision.
- **Notification copy overhaul** — 233 lines across 12 gated pools, replacing a single fixed "Time to take {dosage}" string; also removed dose/pill-count from all reminder text per user request (the patient already knows their dose).
- **Inhaler medication type** added to the form-factor picker.
- **"Change Schedule Type" fix** — was silently a no-op due to two unstyled buttons in one Form row eating each other's taps (a SwiftUI Form gotcha, not a logic bug).
- **New app icon (iOS + watchOS) and watch-app visual parity** — the watch app had drifted onto old mascot art and an unrelated splash animation; brought back in sync with iOS deliberately (see the new operating instruction in §2 about asking before future watch pushes).
- **Pro alternate app icons** (§7b), **ghosted Pro rows** in the free tier (§5), **routine-linked schedule labels** on Today (§4/§9), **out-of-stock nudge banner** on Medications (§9).
- **Splash screen redesign** — confetti-burst entrance animation, `Animatable` `ViewModifier`-driven (not a raw progress value fed into `.offset`/`.opacity`, which SwiftUI would animate only the end-to-end values of and skip the visible middle of the burst entirely).
- **Mascot art transparency fix** — the character art shipped with a baked-in white square background; anywhere it sat on a non-white surface (celebration cards, splash gradient, dark mode) showed a visible box. Fixed at the asset level with a border flood-fill knockout, not by working around it per-screen.

---

## 13. Design Language & Brand

*(Read this section closely if building marketing materials, a website, or any new UI — it's the single source of truth for "what DoseTrack looks and feels like.")*

### Mascot: Milli

DoseTrack's character is **Milli** — a cheerful, rounded pill bottle (pink/blush body, orange screw-cap lid, simple happy face, two little legs, arms thrown up in a "yay!" pose) with a small burst of colourful pills/capsules arcing around it. Milli appears:
- On the launch splash screen
- As the default profile avatar option (alongside 9 alternative character avatars: Doctor Bear, Nurse Bot, Potion Wizard, Pill Hero, Professor Owl, Nurse Cat, Dr. Fox, Space Medic, Medicine Dragon)
- On the Today screen's "all done" celebration state
- On the paywall hero
- On the app icon (flattened onto an opaque brand-blue gradient background — app icons can't be transparent)
- On the watch app (splash + Today), scaled down but otherwise the same treatment as iOS

**Technical note on the art:** the source mascot PNGs ship with a baked-in solid-white square background. Anywhere Milli is composited onto a non-white surface (a coloured card, a gradient, dark mode), the white must be knocked out to transparent first (border flood-fill, preserving interior highlights like the jar's shine) — do not just place the raw PNG on a coloured background, it will show a visible box.

### Colour Palette

| Role | Hex | Usage |
|---|---|---|
| Brand blue (primary) | `#5B8AF0` → `#3B5FCC` (gradient) | Splash, header cards, wordmark, app icon background, primary buttons |
| Success green | `#34C759` → `#2E9E68` (gradient) | "All done" celebration state, taken status |
| Alt success green | `#30A46C` | Adherence ring accents |
| Warning orange | system `.orange` | Restock alerts, refill warnings |
| Danger red | system `.red` | Missed doses, destructive actions |
| Medication colour-coding palette | 24 hues (see `Constants.MedicationColors.palette` in `Utilities/Constants.swift`) | User picks one per medication; used for row icons, tiles, calendar dots |
| Alt app icon colourways (Pro) | Midnight (`#1E2230`→`#0C0E16`), Mint (`#56C2A6`→`#2E9E82`), Lavender (`#A78BFA`→`#7C5CD6`) | See §7b |

### Typography

System font (SF Pro), leaning heavily on **rounded design** (`.system(..., design: .rounded)`) and **heavy/black weights** for the wordmark and hero numbers (e.g. the "5 of 11" dose count on Today). Body text is standard SF Pro at normal weights. Nothing custom/licensed — this is reproducible with system fonts alone.

### Motion

- **Splash entrance:** radial pale-blue-to-white background, Milli pops in with a spring overshoot (not a flat fade), a small settling rotation, then a **confetti burst** — ~40 brand-coloured capsule/dot shapes launch outward and upward from behind the mascot, arc under simulated gravity, spin, and fade, timed to mostly clear before the splash holds. Wordmark pops in with its own small overshoot, a blue underline draws in, tagline fades in last. Total sequence ≈1.8s. The watch splash is the same choreography, scaled down.
- **"All done" celebration:** header card shifts to the green gradient, Milli appears in-flow (not floating/boxed) on the trailing edge.
- General UI motion is otherwise restrained — spring-based transitions, no gratuitous animation elsewhere.

### Tone of voice

Warm, encouraging, lightly playful — never clinical or alarming (this is a deliberate contrast with typical "medical app" design language). The notification copy pool (§6) is the clearest expression of this: puns, gentle humour, and variety, while staying respectful of a genuinely serious use case (the medical disclaimer, §11a, is the serious/legal counterweight — the app is playful in tone but not flippant about safety).

---

## 14. Key Technical Decisions & Rationale

| Decision | Rationale |
|---|---|
| iOS 17+ minimum | Required for interactive WidgetKit buttons (mark-as-taken from home screen). |
| CoreData not SwiftData | SwiftData's sync story was still maturing when this was built; CoreData is proven and stable. |
| Supabase, not CloudKit, for sync | Cross-platform (an Android port exists as a sibling repo), works for caregiver-to-patient sharing across different Apple IDs (CloudKit private databases can't do that), and gives a real Postgres backend for future server-side features. |
| Local-first, account optional | Core brand promise. Data never leaves the device without explicit user action (signing in). Key trust differentiator from Medisafe. |
| StoreKit 2 | Native async/await API. No RevenueCat or third-party dependency needed for a two-product subscription setup this simple. |
| UNCalendarNotificationTrigger | Survives device restarts and timezone changes. Never use time interval triggers for medication reminders. |
| VNDocumentCameraViewController over a raw camera photo | Auto edge-detection, perspective correction, and contrast enhancement — dramatically better OCR input than a raw glossy-box snapshot. |
| Swift Charts not third-party | Native, zero-dependency, sufficient for adherence bar/line charts at this scope. |
| PDFKit not HTML-to-PDF | Native framework, no WebKit dependency, appropriate for structured tabular reports. |
| Randomized, dose-free notification copy | The patient already knows their own dose; showing it added no value and cluttered the reminder. A single fixed body string also felt robotic on a reminder someone sees daily for months. |
| Pro features visible-but-locked, not hidden | A hidden feature can't drive an upgrade. Showing it dimmed with a lock badge does. |

---

## 15. Critical Rules — Never Violate These

1. **Never store medication data on a server without explicit user opt-in.** Guests and users who don't sign in stay 100% local.
2. **Never put a hard paywall on core reminder functionality.** Unlimited medications is Pro. Reminders always work on free tier.
3. **Never use `UNTimeIntervalNotificationTrigger` for recurring medication reminders.** It doesn't survive restarts.
4. **Never show a paywall on first app open.** The user must experience the app first.
5. **Never delete a medication permanently without a soft-delete confirmation step.** Use `isActive = false` first, then offer permanent delete.
6. **The medical disclaimer & terms acceptance (§11a) is mandatory for every new account and must be recorded**, not just displayed. Do not weaken this to a dismissible banner or optional screen.
7. **Data export must always be free.** Never gate CSV export behind Pro. Users own their data.
8. **The refill countdown must work on the free tier.** It is a safety feature, not a premium feature.
9. **Never show dose amount, strength, or pill count in a notification body.** Medication name only — see §6.
10. **Never hide a Pro feature from a free user; ghost it instead** (dimmed + lock badge, still tappable → paywall). See §5.
11. **Ask before assuming a watch-app change is (or isn't) wanted** when making an iOS visual or Today-tab change. See §2/§8.

---

## 16. File Structure

Reflects the actual repo layout — not exhaustive, but every directory and the notable files within it.

```
dosetrack-ios/
├── CLAUDE.md                          ← This file
├── DoseTrack.xcodeproj                ← Generated by `xcodegen generate` from project.yml — do not hand-edit
├── project.yml                        ← Source of truth for the Xcode project
├── supabase/
│   └── migrations/                    ← SQL migrations to apply manually in the Supabase dashboard
├── design-assets/                     ← Source mascot art (not part of the Xcode project)
├── DoseTrack/
│   ├── App/
│   │   ├── DoseTrackApp.swift
│   │   ├── AppDelegate.swift          ← Notification delegate
│   │   ├── SceneDelegate.swift        ← Also applies the appearance override
│   │   ├── RootView.swift             ← Splash, auth gate, disclaimer gate, onboarding gate
│   │   ├── MainTabView.swift          ← The 5-tab shell
│   │   └── PersistenceController.swift
│   ├── Models/
│   │   ├── DoseTrack.xcdatamodeld
│   │   ├── Medication+Extensions.swift
│   │   ├── Schedule+Extensions.swift
│   │   ├── DoseLog+Extensions.swift
│   │   └── MealTimes.swift            ← Daily Routine Times (Wake Up, meals, Bedtime)
│   ├── Services/
│   │   ├── NotificationManager.swift
│   │   ├── NotificationScheduler.swift
│   │   ├── NotificationCopy.swift     ← The 233-line randomized reminder pool
│   │   ├── MedicationTextRecognizer.swift  ← Orientation-aware Vision OCR
│   │   ├── MedicationParser.swift     ← OCR-lines → structured medication draft
│   │   ├── SubscriptionManager.swift
│   │   ├── AppIconManager.swift       ← Pro alternate app icons
│   │   ├── DisclaimerManager.swift    ← One-time acceptance gating
│   │   ├── SupabaseSyncManager.swift  ← All Supabase push/pull
│   │   ├── AuthManager.swift
│   │   ├── ExportManager.swift
│   │   ├── ReportGenerator.swift
│   │   ├── SupplyMath.swift           ← Shared refill/quantity arithmetic (also compiled into the widget target)
│   │   └── WatchConnectivityManager.swift
│   ├── ViewModels/
│   │   ├── TodayViewModel.swift
│   │   ├── MedicationsViewModel.swift
│   │   ├── AddEditMedicationViewModel.swift
│   │   └── ...
│   ├── Views/
│   │   ├── Today/
│   │   ├── Medications/               ← Includes MedicationScannerView.swift, GuidedScheduleView.swift
│   │   ├── Restock/
│   │   ├── History/
│   │   ├── Settings/                  ← Includes AppIconPickerView.swift, AvatarPickerView.swift
│   │   ├── Onboarding/
│   │   ├── Auth/
│   │   ├── Legal/                     ← DisclaimerView.swift (DisclaimerConsentView, the one-time gate)
│   │   └── Paywall/
│   ├── Utilities/
│   │   ├── ColorExtensions.swift
│   │   ├── DateExtensions.swift
│   │   └── Constants.swift
│   └── Resources/
│       ├── Assets.xcassets            ← Includes SplashHero/AllDone/EmptyState (transparent mascot art)
│       ├── AlternateIcons/            ← Loose PNGs for Pro alt app icons (NOT in Assets.xcassets)
│       ├── Info.plist
│       ├── DoseTrack.entitlements
│       ├── Secrets.swift              ← Gitignored, see §1
│       └── Products.storekit
├── DoseTrackWidgets/
├── DoseTrackWatch Watch App/           ← Embedded in the iOS app (embed: true in project.yml)
│   ├── DoseTrackWatchApp.swift
│   ├── WatchRootView.swift             ← Splash (mirrors iOS style)
│   ├── TodayWatchView.swift
│   ├── NotificationController.swift
│   └── WatchConnectivityReceiver.swift
└── DoseTrackTests/
    ├── MedicationTextRecognizerTests.swift  ← Real end-to-end OCR tests, not mocked
    ├── MedicationScannerParserTests.swift
    ├── NotificationCopyTests.swift
    ├── NotificationSchedulerTests.swift
    ├── DisclaimerManagerTests.swift
    └── ...
```

---

## 17. App Store Submission Checklist

- [ ] `PrivacyInfo.xcprivacy` manifest complete — declare data types collected
- [ ] Privacy policy URL live and linked in App Store Connect (see §11b)
- [ ] Both pending Supabase migrations applied (`supabase/migrations/*.sql`) — disclaimer acceptance and schedule routine labels won't persist server-side without them
- [ ] All `Info.plist` usage descriptions present (camera, photo library)
- [ ] Medical disclaimer acceptance flow tested end-to-end for a brand-new account (§11a)
- [ ] Screenshots generated for required device sizes
- [ ] App preview video optional but recommended
- [ ] Age rating: 4+ (no mature content)
- [ ] Review notes explain the medication reminder use case
- [ ] TestFlight build tested on a physical device (in particular: the medication scanner's real-world camera behaviour, and Apple/Google sign-in's notification-permission path)
- [ ] Subscription terms URL linked in App Store Connect

---

*Last updated: 2026-07-11 (build 21). Built by Rob Brown using Claude Code.*
