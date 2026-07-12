# DoseTrack — App Store Connect Submission Package

> Paste-ready copy and configuration for submitting DoseTrack to the App Store.
> Ground truth pulled from `CLAUDE.md`, `project.yml`, `Products.storekit`, `Info.plist`,
> `PrivacyInfo.xcprivacy`, and the hosted privacy policy (fetched 2026-07-13).
>
> **Version:** `1.0.0` (MARKETING_VERSION) · **Build:** `23` (CURRENT_PROJECT_VERSION)
> **Bundle ID:** `com.robbrown.dosetrack` · **Team:** `9VY7RCG6Y4` · **Min iOS:** 17.0
> **Devices:** iPhone only (`TARGETED_DEVICE_FAMILY = 1`) + watchOS 10 companion (embedded)
> **Encryption:** `ITSAppUsesNonExemptEncryption = false` (no export-compliance docs needed)

Anything only the developer can supply is marked `⟨TODO: …⟩`.

---

## 1. App Information

| Field | Value | Notes |
|---|---|---|
| **App Name** | `DoseTrack` | 9/30 chars. Fits. |
| **Subtitle** | `Never miss a dose.` | 18/30 chars. The brand tagline. Alt (28 chars): `Medication reminders that work` |
| **Primary Category** | Health & Fitness | Per §1. |
| **Secondary Category** | Medical | Suggested — reinforces discoverability for "medication tracker". (Optional; can be left blank.) |
| **Content Rights** | Does **not** contain, show, or access third-party content | No licensed/third-party content in the app. |
| **Bundle ID** | `com.robbrown.dosetrack` | |
| **SKU** | `⟨TODO: developer choice, e.g. DOSETRACK-001⟩` | Any unique internal string. |
| **Primary Language** | English (U.S.) | |
| **Age Rating** | **4+** | See questionnaire below. |

### Age Rating Questionnaire (target: 4+)

Answer **None / No** to every content-frequency question. The medically-relevant ones:

| Question | Answer | Justification |
|---|---|---|
| Medical/Treatment Information | **No** | DoseTrack is a **reminder/scheduling tool only**. It provides no diagnoses, dosing advice, drug-interaction warnings, or treatment recommendations. The medical disclaimer (§11a) explicitly states it is *not medical advice*. Apple treats reference apps that *dispense* medical info differently; a passive reminder that stores user-entered data does not trigger a raised rating. |
| Unrestricted Web Access | **No** | Only a static privacy-policy link opens externally; no in-app browser. |
| Gambling / Contests | **No** | — |
| Violence / Sexual / Profanity / Horror / Alcohol-Tobacco-Drugs | **No** | "Drugs" here means *depiction/encouragement of recreational drug use*, which the app does not contain. Tracking one's own prescribed medication is not this category. |
| Made for Kids | **No** | General audience, not a Kids-category app. |

Expected result: **4+**.

---

## 2. Store Listing Copy

### Promotional Text (max 170 chars)

> Switching from Medisafe? DoseTrack keeps 5 medications free forever — reliable reminders, your data on your device, and an honest upgrade path. No forced subscription.

*(163/170 chars. Editable any time without a new build.)*

### Description (max 4000 chars)

```
Never miss a dose.

When Medisafe moved its free users to a mandatory paid subscription, millions of people lost the simple medication reminder they relied on every day. DoseTrack is the clean, trustworthy replacement — built to do the one thing a medication tracker must do: remind you, reliably, every time.

DoseTrack wins on three things other trackers get wrong.

RELIABLE REMINDERS
Reminders that actually fire — on your iPhone and on your Apple Watch. Take, Skip, or Snooze right from the notification without opening the app. Reminder wording is warm and varied, never robotic, and never shows your dose or pill count on the lock screen (you already know your own dose).

YOUR DATA STAYS YOURS
DoseTrack is local-first. No account is required, and your medication data never leaves your device unless you choose to sign in. Signing in adds cross-device sync and caregiver sharing — but nothing is forced, and you can export all your data at any time.

AN HONEST FREE TIER
Track up to 5 medications free, forever. The refill countdown, CSV export, notifications, history, and widgets are all free. No paywall on the features that keep you safe.

WHAT YOU GET
• Flexible schedules — daily, weekly, every-N-days, as-needed, and routine-based times (Wake Up, meals, Bedtime)
• Home Screen and Lock Screen widgets — see your next dose and mark it taken without opening the app
• Apple Watch companion — reminders and one-tap logging on your wrist
• Medication box scanner — point your camera at the box and DoseTrack reads the name, strength, supply, and dose for you
• Refill tracking — know how many days of supply you have left before you run out
• Adherence history — a clear chart of what you've taken, with CSV export
• Colour-coded medications, bottle photos, and E-Script QR storage for pharmacy pickup

DOSETRACK PLUS
Upgrade to DoseTrack Plus for unlimited medications, PDF adherence reports for your doctor, caring for someone else's medications (caregiver mode), the medication box scanner beyond your free scans, and custom app icons. A 7-day free trial is included.

IMPORTANT
DoseTrack is a medication reminder tool only. It does not provide medical or pharmaceutical advice and is only as accurate as the information you enter. Always consult a qualified medical practitioner before taking, changing, or stopping any medication, and never rely on DoseTrack as your sole method for managing critical or time-sensitive medications. In an emergency, contact your local emergency services immediately.

Made with care by Neurotrocity.
```

*(~2,300/4,000 chars — room to expand. The disclaimer line is required to keep parity with §11a and to satisfy App Review for a health app.)*

### Keywords (max 100 chars, comma-separated, no spaces)

```
medication,reminder,pill,tracker,medicine,dose,refill,adherence,prescription,drug,health,caregiver
```

*(99/100 chars. Don't repeat words already in the app name/subtitle — "DoseTrack" and "dose" note: "dose" retained as high-value; drop if you'd rather add another. Avoid trademarked names like "Medisafe" in keywords — Apple rejects competitor trademarks.)*

### What's New (release notes — first version)

```
Welcome to DoseTrack! This is our first release.

• Reliable medication reminders on iPhone and Apple Watch
• Up to 5 medications free, forever
• Local-first — your data stays on your device unless you sign in
• Home Screen and Lock Screen widgets
• Medication box scanner, refill tracking, and adherence history
• CSV export, always free

Thanks for trying DoseTrack. We'd love your feedback.
```

---

## 3. Monetization / Subscriptions (StoreKit 2)

**In-app branding:** the paid tier is "DoseTrack Plus" everywhere a human sees it — customer-facing
display names AND internal reference names all use "Plus". The only exception is the **Product ID**
strings (`com.robbrown.dosetrack.pro.monthly` / `...pro.annual`), which still contain "pro": product
IDs are permanent, never shown to users, and hard-coded in the app, so they are left unchanged.

### Subscription Group

| Field | Value |
|---|---|
| **Reference Name** (internal) | DoseTrack Plus |
| **Group localization — Display Name** (customer-facing) | `DoseTrack Plus` |
| Local StoreKit group id | `pro-subscription-group` |

### Product 1 — Monthly

| App Store Connect field | Value |
|---|---|
| **Product ID** | `com.robbrown.dosetrack.pro.monthly` |
| Reference Name (internal) | Plus Monthly |
| **Display Name** (customer-facing) | `DoseTrack Plus Monthly` |
| **Description** | `Full access to all DoseTrack Plus features.` |
| Duration | 1 Month |
| Price | **$3.99 USD** (Tier equivalent) |
| **Introductory Offer** | **Free trial, 1 week**, `weekly_free_trial`, 1 period — new subscribers only |

### Product 2 — Annual

| App Store Connect field | Value |
|---|---|
| **Product ID** | `com.robbrown.dosetrack.pro.annual` |
| Reference Name (internal) | Plus Annual |
| **Display Name** (customer-facing) | `DoseTrack Plus Annual` |
| **Description** | `Full access to all DoseTrack Plus features — save 37%.` |
| Duration | 1 Year |
| Price | **$29.99 USD** |
| Introductory Offer | **None** in `Products.storekit`. ⟨TODO: decide whether to add a trial in ASC — currently annual has no trial.⟩ |
| Marketing badge | "Best Value — Save 37%" (shown in-app on the paywall; not an ASC field) |

### Per-product ASC assets each subscription REQUIRES

- **Subscription Display Name** and **Description** (above) — localized (at least en-US).
- **Subscription Review Screenshot** (REQUIRED per product): a screenshot of the paywall
  (`PaywallView`) showing this product, its price, and duration. ⟨TODO: capture on device/simulator.⟩
- **Review Notes** per product (optional): "Paywall reached by adding a 6th medication, or the 4th medication-box scan."
- **Subscription Group Localization** display name = `DoseTrack Plus`.
- **App Store Promotion** artwork: optional (1024×1024) — skip for launch.

### Paywall / Guideline 3.1.2 compliance (auto-renewable subscriptions)

The paywall (`PaywallView`) and App Store listing must show, near the purchase controls:

- Title of the subscription (DoseTrack Plus) and length (1 month / 1 year).
- Price, and price per unit if relevant.
- A functional link to **Terms of Use (EULA)** — see §6.
- A functional link to the **Privacy Policy** — see §6.
- Text that the subscription auto-renews unless cancelled, that payment is charged to the
  Apple ID, and how to manage/cancel.

> ⚠️ **Verify in code before submitting:** confirm `PaywallView` renders the auto-renew
> disclosure text AND both the Terms of Use and Privacy Policy links. Missing these is the
> single most common auto-renewable-subscription rejection (Guideline 3.1.2).
> The Terms of Use / EULA link **must also be entered in App Store Connect** (App
> Information → and the subscription metadata), not only in-app.

---

## 4. App Privacy ("Nutrition Label")

Based on `PrivacyInfo.xcprivacy` + the hosted privacy policy. The model is **local-first**:
with no account, nothing leaves the device. Signing in (optional) syncs data to Supabase and
uses Apple/Google sign-in.

**Global answers:**
- **Do you or your third-party partners use data for tracking?** → **No** (`NSPrivacyTracking = false`; no ad/analytics SDKs; policy confirms no tracking).
- **Tracking domains:** none.

**Data types to declare** (all: *App Functionality* purpose; *not* used for tracking):

| Data Type | Collected? | Linked to identity? | Used for tracking? | Notes |
|---|---|---|---|---|
| **Health & Fitness** (medication names, dosages, schedules, dose history) | Yes | **No** | No | Manifest declares `HealthAndMedical`, `Linked = false`. Stored on-device; synced to Supabase only if the user signs in. Even when synced it's tied to an account the user created themselves — declared unlinked per the manifest's local-first framing. |
| **User ID** (Supabase account id) | Yes | **Yes** | No | Only when the user creates an optional account. Manifest `Linked = true`. |
| **Email Address** | Yes | Yes | No | Only on account creation (email or Apple/Google sign-in). Add this in ASC even though the manifest folds it under account info — ASC asks about contact info separately. Purpose: App Functionality (account, sync, caregiver sharing). |
| **Photos or Videos** (bottle / E-Script images) | Yes | **No** | No | Optional attachments. Manifest `Linked = false`. Stays on device unless synced. |
| **Name** (display name) | Yes | Yes | No | Optional profile field for account holders. If you prefer to minimize, this can be treated as part of account info; declare it if a display name is stored server-side. |

**Do NOT declare:** location, contacts, HealthKit, browsing history, search history,
purchases/financial info, diagnostics/analytics, advertising data — none are collected
(policy: no location, no contacts, no HealthKit, no analytics SDKs).

> Consistency check: these answers match the hosted privacy policy (collects medication data,
> photos, and account info only with an account; never sells; no tracking SDKs; third parties
> limited to Supabase, Apple, Google). Keep them aligned if the policy changes.

---

## 5. App Review Information

### Sign-In Required?

Answer **Yes, a demo account is provided** (so the reviewer can see sync/caregiver features),
**but note in Review Notes that the app is fully usable without any account** (local-first).

| Field | Value |
|---|---|
| **Demo Username** | `appstore@dosetrack.app` (the app requires an email login) |
| **Demo Password** | `AppStore` |

> ⟨TODO: confirm this test account is actually created in Supabase and that the medical
> disclaimer has been accepted on it (or that the reviewer is expected to accept it — see notes).⟩

### Review Notes (paste-ready)

```
DoseTrack is a medication REMINDER and scheduling tool (Health & Fitness). It does not provide
medical advice — a mandatory medical disclaimer must be accepted the first time an account is
created (Not medical advice / reminders may fail / your responsibility). This is by design.

NO ACCOUNT NEEDED: The app is local-first and fully functional as a guest — tap "Continue as
Guest" to add medications, set reminders, use widgets, and see history without signing in.
An account is only needed to demonstrate cross-device sync and caregiver sharing.

DEMO ACCOUNT (for sync/caregiver features): username appstore@dosetrack.app / password AppStore. (Created and verified in Supabase; medical disclaimer pre-accepted. The app is fully usable as a guest without signing in — the account is only needed for sync/caregiver features.)

CORE VALUE = NOTIFICATIONS: Please allow notifications when prompted during onboarding. To
test a reminder quickly, use Settings > Notifications > "Send Test Notification", or add a
medication with a schedule a minute or two ahead.

TRIGGERING THE PAYWALL (DoseTrack Plus, auto-renewable subscription with 7-day free trial):
  • Add a 6th medication (free tier is capped at 5), OR
  • Use the medication-box scanner a 4th time (3 free lifetime scans), OR
  • Tap "Care for Someone", the PDF adherence report, or "App Icon" in Settings.

The medication-box scanner uses the live camera (VisionKit DataScanner) and requires a
physical device — it does not run in the Simulator (a single-photo fallback is provided).

Sign in with Apple and Sign in with Google are both supported and skip the 3-page onboarding;
the notification permission is still requested on first main-screen appearance.
```

### Contact Information (for App Review)

| Field | Value |
|---|---|
| First / Last Name | ⟨TODO: developer name⟩ |
| Phone | ⟨TODO: contact phone⟩ |
| Email | `4032332@gmail.com` (matches privacy policy contact) |

---

## 6. URLs

| URL type | Value | Required? |
|---|---|---|
| **Privacy Policy URL** | `https://4032332.github.io/dosetrack/privacy.html` | **Required.** Live. Contact email + "last updated July 8, 2026" present. |
| **Terms of Use (EULA) URL** | ⟨TODO — see below⟩ | **Required for auto-renewable subscriptions.** |
| **Support URL** | ⟨TODO: required by App Store — e.g. a GitHub Pages support page or a mailto page⟩ | **Required.** Every app must have a support URL. |
| **Marketing URL** | ⟨TODO: optional⟩ | Optional. |

> ⚠️ **EULA / Terms of Use:** No Terms-of-Use URL was found in the repo. The in-app medical
> disclaimer text (§11a) is *terms of use for the medical use case* but is not a hosted EULA
> that App Store Connect can link. **Options:**
> 1. Use **Apple's Standard EULA** (default; nothing to host — just don't provide a custom one),
>    and rely on the in-app disclaimer + Apple's standard terms, **or**
> 2. **Host a custom EULA** (e.g. alongside the privacy policy at
>    `https://4032332.github.io/dosetrack/terms.html`) and link it both in-app on the paywall
>    and in App Store Connect. Recommended given the medical disclaimer content — fold §11a into it.
>
> Either way, the paywall must link *some* Terms of Use (Apple's standard EULA link is
> acceptable). ⟨TODO: pick option 1 or 2 and ensure the paywall link is wired up.⟩

---

## 7. Screenshots

**iPhone only** (`TARGETED_DEVICE_FAMILY = 1`, portrait-locked) — **no iPad screenshots needed.**

### Required iPhone sizes (App Store Connect, current requirements)

| Display size | Resolution (portrait) | Required? |
|---|---|---|
| **6.9"** (iPhone 16 Pro Max / 15 Pro Max class) | 1290 × 2796 | **Required** (current largest iPhone slot). |
| **6.7"/6.5"** | 1284 × 2778 or 1242 × 2688 | Apple now auto-scales from 6.9" for most cases, but supplying a 6.5" set (1242×2688) avoids any gaps. Recommended. |
| 5.5" (legacy) | 1242 × 2208 | Not required for iOS 17+ minimum. Skip. |

Minimum 3, up to 10 per size. Provide the same set at 6.9" (and optionally 6.5").

### watchOS screenshots

Because a watch app is embedded and ships, App Store Connect will expose an **Apple Watch**
screenshot slot. Provide at least one:
- **Apple Watch** — 410 × 502 (Series 9/45mm class) or the size ASC requests. ⟨TODO: capture watch Today + a reminder notification.⟩

### Suggested 5–6 screens + captions

| # | Screen | One-line caption |
|---|---|---|
| 1 | **Today** (with adherence ring) | "See every dose due today — and tick them off as you go." |
| 2 | **Medications** list | "All your medications, colour-coded, with refill warnings." |
| 3 | **Scanner** (live box scan) | "Scan the box — DoseTrack reads the name, strength, and dose." |
| 4 | **History / adherence chart** | "Track your adherence over time. Export anytime, free." |
| 5 | **Paywall (DoseTrack Plus)** | "Unlimited medications and more with Plus. 5 free, forever." |
| 6 | **Restock** (supply/E-Script) | "Know before you run out — with E-Script codes ready for pickup." |

> Use the "all done" green celebration state on the Today screenshot if possible — it's the
> most on-brand shot. Screenshot #5 (paywall) doubles as the required subscription review screenshot.

---

## 8. Pre-Submission Checklist

Consolidates CLAUDE.md §17 plus everything above. Check each before hitting **Submit for Review**.

### Build & config
- [ ] `MARKETING_VERSION 1.0.0`, build `23` (bump build if re-archiving).
- [ ] `ITSAppUsesNonExemptEncryption = false` set (it is) — no export docs needed.
- [ ] Archive includes the **watch app** and **widget extension** (both `embed: true`).
- [ ] **Strip dev-only features before archiving** — per project memory: debug Pro override and
      placeholder Secrets. ⟨TODO: confirm `Secrets.swift` holds real Supabase prod keys and any
      debug Pro/entitlement override is disabled.⟩
- [ ] `aps-environment` in entitlements is `development` in `project.yml` — **confirm the
      distribution build uses `production` APNs** (Xcode/automatic signing usually handles this
      for App Store archives, but verify push works from a TestFlight build). ⚠️

### Privacy & legal
- [ ] `PrivacyInfo.xcprivacy` present and complete (it is — Health, User ID, Photos declared).
- [ ] App Privacy answers in ASC filled to match §4 and the hosted policy.
- [ ] `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` present (they are).
- [ ] Privacy Policy URL live and entered in ASC.
- [ ] **Terms of Use / EULA** decided and linked (§6). ⚠️ currently unresolved.
- [ ] Support URL provided. ⚠️ currently `⟨TODO⟩`.
- [ ] Medical disclaimer acceptance flow tested end-to-end for a brand-new account (§11a).
- [ ] Both/all pending Supabase migrations applied (project memory says all 4 are live — confirm).

### Subscriptions
- [ ] Both products created in ASC with the exact Product IDs, display names "DoseTrack Plus
      Monthly/Annual", descriptions, and prices ($3.99 / $29.99).
- [ ] Monthly free-trial introductory offer (1 week) configured; decide on annual trial.
- [ ] Subscription **review screenshot** + localized description attached per product.
- [ ] Subscription group display name = "DoseTrack Plus".
- [ ] Paywall shows price/terms + Terms of Use + Privacy Policy links (Guideline 3.1.2). ⚠️
- [ ] "Agreements, Tax, and Banking" completed in ASC (paid apps can't be submitted otherwise). ⟨TODO⟩

### Assets & review
- [ ] Screenshots for 6.9" iPhone (and 6.5" recommended) + at least one Apple Watch.
- [x] Demo account `appstore@dosetrack.app` / `AppStore` created + verified in Supabase (confirmed email, disclaimer pre-accepted).
- [ ] Review notes (§5) pasted.
- [ ] App Review contact info filled (name/phone/email). ⟨TODO⟩
- [ ] Age rating questionnaire answered → 4+.

### Device testing (TestFlight, physical device)
- [ ] Medication-box scanner tested on real hardware (doesn't run in Simulator).
- [ ] Apple **and** Google sign-in tested, including the notification-permission path they take.
- [ ] Watch reminders + one-tap logging verified on a paired watch.
- [ ] A real notification fires on time (the core value prop).

---

## Risks flagged for App Review

1. **Missing Terms of Use / EULA URL** — required for auto-renewable subscriptions and must be
   linked on the paywall. Not present in the repo. Pick Apple's standard EULA or host a custom one.
2. **Missing Support URL** — every app must have one; not found in the repo.
3. **Paywall disclosure (Guideline 3.1.2)** — verify `PaywallView` shows auto-renew terms +
   both legal links, or expect a rejection.
4. **APNs environment** — entitlement is `development` in `project.yml`; confirm the App Store
   archive ships production push, or notifications (the core feature) fail for real users.
5. **Dev-only overrides** — project memory warns of a debug Pro override and placeholder secrets;
   ensure these are stripped so a reviewer doesn't get unintended Pro access or a broken backend.
6. **Demo account readiness** — DONE: `appstore@dosetrack.app` / `AppStore` created + verified in Supabase, with the
   medical disclaimer already handled, or the sync/caregiver features can't be reviewed.
```
