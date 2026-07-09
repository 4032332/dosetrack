# DoseTrack Pre-Launch Review & Monetization Plan

**Date:** 2026-07-09
**Author:** Full-app review (code, functionality, backend, UI)
**Goal:** Fix all outstanding defects, sharpen what's already strong, and stand up real in-app payments plus a way for beta testers to exercise Pro features.

---

## PART A — REVIEW FINDINGS

### ✅ Positives (what's working well)

**Architecture & code health**
- Clean MVVM separation; ViewModels are unit-tested (115 tests, all green).
- Single write path for dose logging (`DoseLoggingService`) shared by Today screen, notification actions, and the app — consistent side effects (supply decrement, sync, widget reload).
- Timestamp-based ("newer wins") sync merge with proper `updatedAt` columns — robust against clobbering.
- Backend is healthy: RLS enabled on all sensitive tables, only 2 low-severity WARN lints remain (both deliberately deferred). APNs push edge function live and cron-verified.
- Local-first design honored — app fully usable with no account (guest mode).

**UI & product**
- The Today gradient header, adherence ring, and confetti celebration are genuinely polished and on-brand.
- Restock tab's color-coded urgency (red/orange/yellow/green) is a real differentiator competitors lack.
- History adherence chart + per-medication breakdown is a strong "proof it works" screen.
- Milli mascot gives the app a warm, distinctive identity.
- Guided schedule builder (question-flow) is a thoughtful UX for a genuinely fiddly task.
- Caregiver sharing is a meaningful, well-scoped feature beyond the original spec.

### ❌ Negatives (defects, grouped by severity)

**P0 — Correctness bugs (user sees wrong information)**
1. **Upcoming doses display a green "✓ Taken" chip.** `TodayViewModel.buildTodayEntries()` sets `displayStatus = .taken` for future/un-logged doses "so it stands out as upcoming," but `DoseRowView` renders that as a green "Taken" chip. Result: doses the user has NOT taken show as taken (visible in earlier screenshots — 20:00/21:00 rows). Misleading for a medication-adherence app. Needs a distinct "Upcoming" state.
2. **Widget "mark taken" is a data-integrity hole.** `MarkDoseTakenIntent.perform()` writes a DoseLog but (a) does not decrement supply, (b) does not stamp `updatedAt`, and (c) does not push to Supabase. Because the sync merge is "newer wins" on `updatedAt`, a widget-logged dose can be silently reverted on the next foreground pull, and never syncs to other devices. Must route through the same logic as `DoseLoggingService`.

**P1 — Broken / non-functional features**
3. **CSV & PDF export share raw `Data` + a filename string**, not a file URL (`ActivityView(activityItems: [item.data, item.filename])`). iOS names the shared file generically and treats the filename as separate text. Export is a core free-tier promise and an App Store review checkpoint — must write to a temp file URL and share that.
4. **"Rate DoseTrack" opens `https://apps.apple.com/`** — the App Store home page, not the app. Should use `SKStoreReviewController.requestReview` for in-app prompts and/or the real `…?action=write-review` deep link once the App Store ID exists.
5. **Medication reorder doesn't sync.** `MedicationsViewModel.moveItems` saves `sortOrder` locally but never pushes to Supabase, so order silently resets on other devices / next pull.

**P2 — Polish, consistency, missing planned elements**
6. **No in-app link to the hosted privacy policy** (now live at the GitHub Pages URL). Good practice and reduces review friction.
7. **No medication-name autocomplete** in the Add form — CLAUDE.md planned "autocomplete suggestions — common medication names." Nice-to-have, improves data quality.
8. **Silent `try? context.save()`** scattered in `MedicationsViewModel` (reorder, soft-delete) instead of the project's own `saveOrReport()` helper — inconsistent error visibility.
9. `Constants.ExternalLinks.appStoreFallback` is still a placeholder URL.

**Backend housekeeping (low, deferred by prior decision — not launch-blocking)**
10. `pg_net` extension in `public` schema (WARN).
11. Leaked-password protection disabled (WARN, Auth dashboard toggle).

---

## PART B — THE PLAN

> **For agentic workers:** use superpowers:subagent-driven-development or executing-plans. Steps use checkbox syntax.

**Architecture:** All fixes are localized to existing files; no schema changes except one additive Supabase check for subscription state (Part 4). Monetization is primarily App Store Connect configuration, not code — the StoreKit 2 client is already built.

**Tech Stack:** SwiftUI, StoreKit 2, CoreData, Supabase, XcodeGen, XCTest.

---

### Chunk 1: P0 correctness bugs

#### Task 1.1 — Distinct "Upcoming" state for future doses
**Files:** `DoseTrack/ViewModels/TodayViewModel.swift`, `DoseTrack/Views/Today/DoseRowView.swift`
- Add an `.upcoming` case to the display model (either a new `DoseDisplayState` enum or an `isUpcoming` flag on `DoseEntry`) rather than overloading `.taken`.
- `StatusChip` renders upcoming as a neutral/blue "Upcoming" pill (clock icon), not green "Taken."
- Update/extend `TodayViewModelTests` to assert an un-logged future dose is NOT reported as taken.
- Verify in simulator: upcoming rows no longer show green "Taken."

#### Task 1.2 — Route widget mark-taken through shared logic
**Files:** `DoseTrackWidgets/MarkDoseTakenIntent.swift`, `DoseTrackWidgets/WidgetDataProvider.swift`
- In `perform()`, stamp `updatedAt = Date()` on the DoseLog (and decrement medication `currentCount` + stamp its `updatedAt`, mirroring `DoseLoggingService.log`'s supply math).
- Enqueue a sync push: since the widget extension has no Supabase session, set a "pending push" marker in the shared App Group UserDefaults, and have the main app drain it on next foreground (`SupabaseSyncManager.pushUnsyncedLocalChanges` already exists — ensure it also covers widget-written logs via the `updatedAt` watermark).
- Add a unit test for the supply-decrement + `updatedAt` stamping helper.

### Chunk 2: P1 broken features

#### Task 2.1 — Export writes a real file URL
**Files:** `DoseTrack/Views/History/HistoryView.swift`, `DoseTrack/Services/ExportManager.swift`
- Add `ExportManager.writeTemporaryFile(data:filename:) -> URL` (writes to `FileManager.default.temporaryDirectory`).
- Change `ExportItem` to carry a `URL`; `ActivityView` shares `[url]`.
- Verify AirDrop/Save-to-Files produces a correctly-named `.csv` / `.pdf`.

#### Task 2.2 — Fix "Rate DoseTrack"
**Files:** `DoseTrack/Views/Settings/SettingsView.swift`, `DoseTrack/Utilities/Constants.swift`
- Use `SKStoreReviewController.requestReview(in:)` for the in-app rating prompt.
- Add a real review deep link constant (`itms-apps://…?action=write-review`) to open once the App Store ID is known; keep a safe fallback.

#### Task 2.3 — Sync medication reorder
**Files:** `DoseTrack/ViewModels/MedicationsViewModel.swift`
- After `moveItems` saves, stamp each moved med's `updatedAt` and push via `SupabaseSyncManager.pushMedication`.
- Replace `try? context.save()` with `context.saveOrReport()` here and in `confirmSoftDelete`.

### Chunk 3: P2 polish

#### Task 3.1 — In-app privacy policy link
**Files:** `DoseTrack/Views/Settings/SettingsView.swift`, `Constants.swift`
- Add "Privacy Policy" row in About/Data & Privacy opening the hosted GitHub Pages URL.

#### Task 3.2 — Medication-name autocomplete (optional, time-boxed)
**Files:** `DoseTrack/Views/Medications/AddEditMedicationView.swift`, new `Constants` list or bundled JSON of common medication names.
- Inline suggestion list under the name field (reuse the `CountryAutocompleteField` pattern from ProfileView).

#### Task 3.3 — Constants cleanup
- Replace `appStoreFallback` placeholder once the App Store URL exists.

---

### PART 3 (of user's request): PAYMENT FUNCTIONALITY IN APP STORE CONNECT

> Mostly configuration, not code — the StoreKit 2 client (`SubscriptionManager`, `PaywallView`) is already built and reads live products. Once products load, the "Pro pricing is coming soon" fallback disappears automatically.

**Hard prerequisite (blocks everything, do first):**
- [ ] **Sign the Paid Applications Agreement** in App Store Connect → Business → Agreements, Tax, and Banking. Add banking + tax info. Until this is *Active*, `Product.products(for:)` returns empty even in sandbox — this is the #1 reason paywalls look "broken."

**Create the products:**
- [ ] App Store Connect → your app → Subscriptions → create a **Subscription Group** (e.g. "DoseTrack Pro").
- [ ] Add **Pro Monthly** — product ID `com.robbrown.dosetrack.pro.monthly`, $3.99/mo. (Optionally attach a 7-day free trial as an Introductory Offer, matching the CLAUDE.md paywall copy.)
- [ ] Add **Pro Annual** — product ID `com.robbrown.dosetrack.pro.annual`, $29.99/yr, same group (higher tier = "Best Value").
- [ ] For each: localized display name + description, subscription duration, price.
- [ ] Provide the required **review screenshot** of the paywall and a **subscription review note**.
- [ ] Add **Terms of Use (EULA)** link + the existing **Privacy Policy** URL (App Information) — Apple requires both for auto-renewable subscriptions or the product gets rejected.

**Verify the client matches:**
- [ ] Confirm product IDs in `Constants.StoreKit` exactly match App Store Connect (they do today).
- [ ] Confirm `Products.storekit` local config matches for simulator testing.
- [ ] Add a "Manage Subscription" affordance: `.manageSubscriptionsSheet(isPresented:)` (StoreKit 2) or `showManageSubscriptions` from Settings → Subscription.
- [ ] Ensure "Restore Purchases" (already in PaywallView) is reachable from Settings too.

**Ship-readiness for subscriptions:**
- [ ] Decide: launch v1 WITH Pro, or launch free-only and add Pro in v1.1. (Recommendation: get the free app approved first if the agreement/banking will take time — Pro can be a fast follow. But if the agreement is already active, ship with it.)

---

### PART 4 (of user's request): BETA-TEST PRO FEATURES

Three layered options, cheapest first:

1. **TestFlight sandbox purchases (recommended, zero cost).**
   - TestFlight builds automatically use the StoreKit **sandbox** environment. Testers can "subscribe" to Pro Monthly/Annual for **free**, and sandbox subscriptions auto-renew on an accelerated clock (e.g. a month renews in minutes) then expire — perfect for exercising the full purchase → entitlement → expiry loop.
   - Requires the products to exist in App Store Connect first (Part 3), but does **not** require the Paid Apps Agreement to be fully active for *sandbox* in TestFlight in most cases — still, sign it early to avoid surprises.
   - Action: once products are created, tell testers "tap Upgrade → subscribe; it's free in TestFlight."

2. **`#if DEBUG` Pro override (already built, dev-only).**
   - `SubscriptionManager.debugForceProOverride` + the Settings "Debug" picker already let a developer flip Pro on/off in local/simulator DEBUG builds. Compiled out of Release/TestFlight automatically. Good for your own local testing, not for external testers.

3. **Offer Codes (optional, for polished external beta).**
   - Once products exist, generate **subscription Offer Codes** in App Store Connect and hand them to specific testers for free/discounted Pro in *production* — useful if you want a few non-TestFlight users on Pro.

**Recommendation:** Do Part 3 (create products) → use Option 1 (TestFlight sandbox) as the primary beta path. Keep Option 2 for your own dev loop.

---

## Execution order

1. **Chunk 1 (P0)** — correctness bugs, before any new archive.
2. **Chunk 2 (P1)** — broken features (export especially, it's an App Store checkpoint).
3. **Sign Paid Apps Agreement** (Part 3 prerequisite) in parallel — it can take time to activate.
4. **Create subscription products** (Part 3).
5. **Chunk 3 (P2)** — polish.
6. Archive → TestFlight → testers exercise Pro via sandbox (Part 4).
7. Backend WARN lints (10, 11) — optional, any time.

## Notes on strengths to amplify (user request #2)
- **Restock urgency + Watch glanceability** are the two most differentiated things — feature them first in the App Store screenshot order and description copy.
- **Local-first / no-account-required** is the core trust story vs. Medisafe's forced subscription — lead the App Store description with it.
- **Milli** — consider a short App Preview video of Milli reacting to "all doses taken" (confetti) for the listing.
