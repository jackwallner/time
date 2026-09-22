# Shoes On, Project Guide

"Leave on time" routine coach for time blindness. The user sets when they walk
out the door and the steps before it; the app works backward, learns how long
each step really takes them, and coaches the run step by step on the phone,
the Lock Screen and Apple Watch. XcodeGen project/scheme `ShoesOn`, sim lease
owner `time`.

## Product

The tailoring is the product. Three things are learned, each blended with a
prior so one odd morning cannot swing the plan (`Shared/Engine/Calibration.swift`):

1. **Pace**: real time over guessed time across recent steps, seeded by the
   onboarding answer "when getting ready feels like an hour, it takes..."
   (1.0, 1.25, 1.5 or 2.0x). Applies to steps that have never been timed.
2. **Each step's own time**: 70th percentile of its last 8 timings, blended
   with the paced guess. Slow-side on purpose: the mean is late half the time.
3. **Start delay**: how long after the get-ready alert they actually start.
   Becomes a head start (max 20 min) that moves the alert earlier.

The guess is never overwritten. The gap between guess and real time is what
the home screen, the reveal page and the summary show.

## Tech stack and identifiers

- Swift 6, SwiftUI, ActivityKit (Live Activity with an interactive Done
  button), App Intents, UserNotifications (Time Sensitive), WatchConnectivity.
  No HealthKit, no backend, no account.
- iOS 17+, watchOS 10+.
- App `com.jackwallner.time`, Live Activity widget `.widget`, Watch `.watch`,
  tests `.tests`, UI tests `.uitests`. App Group `group.com.jackwallner.time`.
- App Store Connect app `6814953557`, name "Shoes On: Time Blindness Coach".
- RevenueCat project `proj457863e6`, app `app06b21534c0`, entitlement lookup
  key `pro`, offering `default` with `$rc_lifetime`. Public key is in
  `StoreService.swift`; no secret key is stored anywhere.

## Architecture

- `Shared/Engine/`: pure and tested. `Calibration`, `Planner` (backward
  layout), `ActiveRun` (a run in progress, status and projection),
  `RunSnapshot` (what the Live Activity and Watch get), `NotificationPlan`
  (every alert, decided in one pure function).
- `Shared/Services/RoutineStore.swift`: the single door. All state is one JSON
  file in the App Group. Every mutation persists, then `propagate()` fans out
  to notifications, the Live Activity and the Watch. Never write state
  anywhere else.
- `Shared/LiveActivity/RunIntents.swift`: `CompleteStepIntent` compiles into
  the widget with an empty body (`WIDGET_EXTENSION` flag) and into the app
  with the real one; a `LiveActivityIntent` runs in the app process.
- Watch: the phone owns runs. `WatchSyncService` sends a `WatchPayload`
  through the application context; the Watch sends `WatchCommand`s back
  (`sendMessage`, falling back to `transferUserInfo`).
- UI: `ShoesOn/Views/`. Onboarding (6 pages) → Home (next departure, the real
  plan, how it's going) → RunView (step, clock, status, Done) → summary.

## Access model

Free forever: one routine with every alert, the Live Activity and all the
learning. **Shoes On Pro** ($14.99 lifetime, non-consumable
`com.jackwallner.time.pro.lifetime`, no subscriptions): more than one routine,
and the Apple Watch app. Never move learning or alerts behind Pro.

## Rules that hold everywhere

- No em or en dashes in any copy. `NotificationPlanTests.testCopyHasNoDashes`
  guards the alert copy.
- Notifications are a rolling ~10-day window of one-shot requests (iOS keeps
  64). `store.propagate()` on every foreground rebuilds it.
- Not a medical app: never claim it treats or manages ADHD.
- Simulator never configures RevenueCat; `StoreService` hydrates the product
  from StoreKit Testing or a fixture instead.

## Deep notes (load on demand)

| File | Covers | Read when |
|---|---|---|
| `.claude/rules/store-and-release.md` | ASC/RC setup commands, screenshots, launch args | Touching store, scripts, fastlane, screenshot fixtures |

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
