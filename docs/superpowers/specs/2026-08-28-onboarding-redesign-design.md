# Onboarding Redesign — Design

**Date:** 2026-08-28
**Status:** Approved, ready for implementation planning

---

## Problem

The first thing a new user sees is an account creation screen. They have felt no
value from the app yet, and they are asked to hand over an email address to a
medication tracker they have never used. Two costs follow:

1. **Drop-off at the wall.** People bounce before seeing anything.
2. **Accounts asked at the worst moment.** A cold sign-up wall converts worse
   than a warm "back up the medications you just entered" prompt. We want *more*
   accounts, not fewer — the ask is in the wrong place, not wrong to make.

Local-only use already works today (`guestMode` + "Continue without an
account"), and guests get the full app with local data. **This redesign adds no
new capability.** It changes sequencing and framing, which makes it a smaller and
safer change than it first appears.

## Goals

- No account required, or requested, before the user has experienced the app.
- A new user reaches a populated Today screen with their own medication in it.
- The account ask lands after there is something worth protecting.
- Existing users are completely unaffected.

## Non-goals

- Coach marks / spotlight overlays (see Decision 3).
- A gender or pronoun field (see Decision 2).
- Any change to adherence scoring, notification copy, the review prompt, or the
  subscription paywall's contents.
- Re-fixing the guest-mode blank-screen bug. It was the stated prerequisite; it
  was diagnosed and fixed in 70bc76d before this work begins (see Risks).

---

## The flow

```
Splash
 1. Welcome / Meet Milli
 2. Name + avatar
 3. Medical disclaimer            <- hard gate; consent before medication data
 4. Add first medication          <- scanner offered
 5. Reminders (soft prompt -> iOS dialog only on yes)
 6. Narrated tour: Today -> Medications -> Restock
 7. Add another? -> loops to 4 only, or continue
```

The step 7 loop returns to the add-medication form alone. Steps 5 and 6 do not
repeat — the reminder permission is asked once, and the tour is shown once.

```
 8. Do you take birth control?    -> Yes reveals the existing tracker
 9. Create an account? -> or Continue without
10. App
```

Steps 4 onward are skippable at any point, with the skip affordance always
visible and requiring no confirmation. Step 3 is the only hard gate.

---

## Decisions and rationale

Each of these was considered against alternatives; the rejected options are
recorded so they are not silently revisited.

### Decision 1 — Disclaimer sits at step 3, after the warm intro

The medical disclaimer is gated on *identity* today (recorded per-account to
`user_settings.disclaimer_accepted_at`). With no account until step 9, it has
nothing to hang on, so it is accepted **locally first** and recorded to the
account if and when one is created. Guests already work exactly this way, so
`DisclaimerManager` needs no new mechanism.

Placement was the real question:

- **Rejected — immediately after splash.** Legally cleanest, but it replaces one
  wall with another: the first screen becomes a page of legal text, which is
  arguably worse than a sign-up screen and recreates the problem being solved.
- **Rejected — inline checkbox on the add-medication form.** Lowest friction, but
  a checkbox under a form is a materially weaker evidentiary record than a
  dedicated accept screen, and Critical Rule 6 forbids weakening this gate.
- **Chosen — after welcome and profile, before the first medication.** Consent
  still precedes any medication data (the moment the liability exists), but the
  user arrives warmed up, so it reads as context rather than a barrier.

Critical Rule 6 is preserved: acceptance remains mandatory and recorded, not a
dismissible banner.

### Decision 2 — No gender field; ask about birth control instead

Gender was originally wanted to surface the contraceptive tracker, which already
exists (`ContraceptiveTrackerView`, plus the `contraceptiveDue` alert on Today)
but is only discoverable by configuring it (`MedicationsView:49` hides the card
until `contraceptiveMethod` is set). The goal is therefore **discoverability**,
and gender is the wrong instrument for it:

- Hormonal contraception is frequently prescribed for endometriosis, PCOS, acne
  and menstrual regulation. Gender-gating hides the feature from many people
  wrongly and from nobody usefully.
- **Caregiver mode exists.** A parent tracking a teenager's medications, or a
  partner managing someone else's, means the account holder's gender says
  nothing about whose medications are in the app. This is decisive.
- It is a one-way door: someone answering "male" loses the feature permanently
  with no idea it existed.
- An identity question early in onboarding reads as more intrusive than a
  functional one, working against the drop-off goal.

**Chosen:** ask the function, not the identity — *"Do you take birth control?"*
(Yes / No / Not sure yet) at step 8. Anyone can answer truthfully, and it is a
preference flippable in Settings later. No new schema, no migration, no
`PrivacyInfo.xcprivacy` change.

The existing Settings entry point remains the way in for anyone who answers No
and later changes their mind.

### Decision 3 — Narrated tour, not coach marks

- **Rejected — spotlight overlay anchored to UI elements.** Most impressive, but
  anchored overlays must survive Dynamic Type, five device sizes, dark mode and
  the compact-rows default. High ongoing fragility for a screen seen once.
- **Rejected — static illustrated previews inside onboarding.** Cheapest, but it
  is a brochure: the user's own medication is not in it, which loses the entire
  reason for doing this.
- **Chosen — real screens narrated by a persistent card.** The real
  `MainTabView`, real data, tabs switching programmatically, with a bottom card
  explaining what is on screen and a Next button. Keeps the full "that's *my*
  medication" payoff while eliminating the geometry that generates bugs.

This is not a dead end: if coach marks later prove worthwhile, this structure is
where they would be added.

### Decision 4 — Soft pre-prompt for notifications

iOS shows the system notification prompt **once, ever**. A decline is permanent
and only reversible through iOS Settings. Today it is requested on onboarding
page 2, cold, before the user has a single medication — spending the one-shot
request at the moment of least motivation.

- **Rejected — keep it early.** Simple, but permanently loses users who decline
  for lack of anything concrete to accept.
- **Rejected — real dialog immediately after the first medication.** Better
  timing, but a decline is still permanent.
- **Chosen — soft pre-prompt, then the real dialog.** Ask in-app first ("Want
  reminders for Metformin?" — Yes / Not now). Only Yes triggers the iOS dialog.
  "Not now" spends nothing and can be asked again later.

Because every user now walks the same linear path, the Apple/Google sign-in gap
that `RootView`'s safety-net request was patching disappears on its own. **Keep
the safety net regardless** as belt-and-braces; it simply stops being
load-bearing.

### Decision 5 — Guest to account: ask, with merge as the default

`AuthManager.signOut()` calls `PersistenceController.wipeLocalStore()`. That is
correct for real sign-outs (it stops one person's medications leaking into the
next account), but under this redesign *every* user starts local with real
medications, so the guest-to-account path stops being an edge case.

| Situation | Behaviour |
|---|---|
| New account created | Keep local data, push it up |
| Signs into an account with **no** data | Keep local data, push it up |
| Signs into an account with **existing** data | Show merge choice |

For the ambiguous third case:

- **Rejected — silent merge.** Never loses data, but leaves near-duplicates
  ("Metformin" vs "Metformin 500mg") with no explanation of where they came from.
- **Rejected — remote wins, local discarded.** Cleanest result, but silently
  deletes medications the user just typed in. Unacceptable for a medical app and
  a direct violation of Critical Rule 5.
- **Chosen — ask, with Merge pre-selected.** A one-off screen: *"This account
  already has medications. Keep both, or use your account's list?"* Tapping
  through without reading yields the non-destructive outcome.

`wipeLocalStore()` must **not** fire on the guest-to-account path. This is the
specific regression to guard with a test.

### Decision 6 — One re-ask, then only at the paywall

Declining at step 9 is respected. One reminder roughly two weeks later, framed
on what is now at stake ("You're tracking 5 medications — back them up?"). A
second decline silences it permanently, except on the Plus upgrade path, where a
single honest note appears.

**Copy constraint:** the subscription itself is tied to the user's Apple ID and
restores via Restore Purchases without an account. Only *medication data* is at
risk. Copy must say "your medications aren't backed up" and must never imply
Plus itself would be lost.

---

## Architecture

The substantive change. `RootView` currently gates on auth first:

```
!canProceed            -> AuthView
disclaimer == .required-> DisclaimerConsentView
!hasCompletedOnboarding-> OnboardingView
else                   -> ActiveSessionView
```

Auth is the first gate and everything hangs off it. It becomes:

```
!hasCompletedOnboarding-> OnboardingFlow   (owns welcome, profile, disclaimer,
                                            first medication, reminders, tour,
                                            birth control, account offer)
else                   -> ActiveSessionView
```

**Auth stops being a gate and becomes a destination** — reached from step 9, from
Settings, and from the Plus upgrade path. This inversion is where regressions
will concentrate.

Consequences:

- **Every new user is a local user first.** `localGuestId()` becomes the default
  identity rather than a fallback. `ActiveAccountContext` must resolve for a
  local user before any account exists — the machinery for this already exists
  for guests.
- **`DisclaimerManager`** records acceptance against the local guest id, then the
  acceptance is pushed to the server profile when an account is created.
- **Existing users are untouched.** `hasCompletedOnboarding == true` routes
  straight to the app, whether signed in or guest, exactly as today.

### Component boundaries

- `OnboardingFlow` — owns step sequencing and skip handling only. Knows nothing
  about how any individual step does its work.
- `OnboardingTourView` — the narration card and tab-driving for step 6. Drives
  the real `MainTabView`; contains no duplicated UI.
- `AccountOfferView` — step 9, and reused for the two-week re-ask.
- `AccountMergeView` — the Decision 5 choice screen. Reachable from any sign-in
  with local data present, not just from onboarding.
- `AccountPromptScheduler` — owns the Decision 6 state machine (declined once /
  declined twice / never ask again). Small, pure, unit-testable, mirroring
  `ReviewPromptManager`'s shape.

Existing views (`AddEditMedicationView`, `DisclaimerConsentView`,
`ContraceptiveTrackerView`) are **reused, not reimplemented**. If the onboarding
flow needs a variant presentation, it is a parameter on the existing view, not a
copy.

---

## Testing

- **Gate ordering:** new user, existing user with `hasCompletedOnboarding`,
  existing signed-in user, existing guest. Each reaches the correct first screen.
- **Merge, all three cases**, including an explicit assertion that
  `wipeLocalStore()` does **not** run on the guest-to-account upgrade.
- **Disclaimer:** accepted locally by a local user; synced to the server profile
  on later account creation; never shown twice.
- **Skip:** skipping at every individual step leaves a consistent, usable state
  and correctly sets `hasCompletedOnboarding`.
- **`AccountPromptScheduler`:** first decline schedules the re-ask; second
  decline silences permanently; the paywall path is unaffected by both.
- **Notification soft prompt:** "Not now" does not call the system API, so the
  one-shot request is preserved.

---

## Risks

**The area is known-fragile.** This touches the auth gate, the disclaimer gate,
onboarding, and the guest fallback — the same machinery behind the build 28
account-switch data loss.

**The prerequisite is cleared.** The blank-screen bug in exactly this machinery
was diagnosed and fixed in 70bc76d: `continueAsGuest()` posted
`.guestModeActivated` in the same tick as its UserDefaults write, and RootView's
synchronous handler read SwiftUI's stale `@AppStorage` mirror, cleared
`activeAccount`, and left no branch to render. `GuestMode` now owns the key and
provides an authoritative read, and `ActiveAccountDecision` makes the rule a
tested pure function. Building the inverted gate order on top of that is now
safe — it was not before.

**One known defect remains in the same file, deliberately unfixed.**
`AuthManager.signOut()` sets `session = nil` *after* awaiting
`client.auth.signOut()`, and the Supabase SDK POSTs to `/logout` before
returning. Offline, sign-out will appear to do nothing. It is latent today
because every guest takes the local path, but this redesign makes real-account
sign-out common. Fix it before or alongside implementation, as its own change.

**Data loss is the failure mode that matters.** Every other bug here is cosmetic;
losing a user's entered medications is not. The merge tests are the highest-value
tests in this spec.

---

## Visual refresh (added 2026-08-29)

### The audit

Two generations of mascot art coexist. The older generation is confined entirely
to the screens this redesign already replaces:

| Asset | Size | Generation | Used by |
|---|---|---|---|
| `SplashHero` | 588K | Current Milli | Splash, paywall, medications empty state, avatar picker, onboarding p1 |
| `AllDone` | 592K | Current Milli | Today "all done" |
| `EmptyState` | 320K | Current Milli | Today empty |
| `WatchHero` | — | Current | Watch splash + Today |
| `OnboardingWelcome` | 120K | **Old flat** | `AuthView:36`, `OnboardingView:339` |
| `OnboardingNotification` | 88K | **Old flat** | `OnboardingView:176` |
| `OnboardingAllDone` | 96K | **Old flat** | **Nothing — dead asset** |

The file sizes are the tell: the old assets are roughly a fifth the weight,
because they are the earlier flat illustrations rather than the rendered mascot.
`AuthView.swift:27` carries a comment noting `OnboardingWelcome` has *"an opaque
white background baked in"* — precisely the defect CLAUDE.md §12b records as
fixed at the asset level for the current generation. That fix never reached these
three files.

Today, Medications, Restock, History, the paywall, the splash and the watch are
all already on current-generation art.

### Scope

Because every screen carrying old art is a screen this redesign rebuilds, the
visual refresh is **not additional scope** — it is the same scope done properly:

- Replace `OnboardingWelcome` and `OnboardingNotification` with current-generation
  art at the point their screens are rebuilt.
- **Delete `OnboardingAllDone`.** It is referenced nowhere.
- Retire the white-background workaround in `AuthView` along with the asset that
  requires it.
- Audit the rebuilt screens against §13's design language (rounded system font,
  brand-blue gradient, spring motion) rather than reproducing existing layout.

### App icon

A new icon in the anime Milli style, drawn from `design-assets/milli-anime-ads/`.

**Chosen (2026-08-29): candidate 04 — anime Milli, arms wide, brand-blue gradient.**
Source cutout and 1024px master in `design-assets/icon-2.0/`. It fills the square
better than the arms-raised poses (which leave empty corners and so read smaller),
and its large eyes stay legible at 60px where finer features collapse. Brand blue
is retained, so the icon still reads as DoseTrack.

Two constraints that must shape the work rather than be discovered late:

- **It has to survive 60x60.** The anime art is detailed, and detail that reads
  well in a marketing render turns to mush at icon size. Candidates must be
  reviewed at true icon dimensions on a real home screen, not as large previews.
- **Changing the icon has a real user cost.** People locate the app by its icon;
  existing users will hunt for it once. That is usually worth paying at a major
  version, but it is a cost, not free.

The three Pro alternate icons (§7b: Midnight, Mint, Lavender) are generated from
the same source art and must be regenerated to match, or they will visibly belong
to the previous generation. Midnight and Mint drafts are already in
`design-assets/icon-2.0/`; Lavender still needs generating.

**Known issue in every current draft:** the capsules inside the jar mush together
at 60px. The production icon needs that interior simplified — fewer, larger
capsules. This is an art edit, not a redesign, and it must happen before ship.

### Version

**2.0**, not 1.2 — pending confirmation.

The first-run experience is inverted, a guided tour is added, and the icon
changes. 1.2 reads as a maintenance bump and wastes the "What's New" moment,
which matters given that impressions (not conversion) are the current growth
bottleneck. 2.0 gives a genuine relaunch beat for the store listing.
