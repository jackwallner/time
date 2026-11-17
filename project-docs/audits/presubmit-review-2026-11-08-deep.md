# Pre-submit review, 1.0.2 (build 25), deep pass

Date: 2026-11-08. Branch `review/2026-11-08-time-deep`, from `origin/main` at `1710356`.

Scope: every user-reachable path on `origin/main` (purchase, restore, trial
copy, Pro gating, onboarding, persistence and decoding of saved state,
notifications, Live Activity, widgets and control, Watch sync, iPhone Duo
layout, localization, App Review strings), with the 1.0.1 to 1.0.2 diff
(`2a4a6e0..HEAD`, app sources only) read line by line. Live version: 1.0.1
(`MARKETING_VERSION` changed to 1.0.2 in `07abaef`).

No simulator or local `xcodebuild` was used. Unit tests ran on GitHub's Macs with `gh-sim`.

## Findings

| Severity | Where | What happens | Status |
|---|---|---|---|
| P1 | `Shared/Services/WatchSyncService.swift:56` (before the fix) | Watch Done and Skip carried no step identity, so the phone acted on whatever step was current when the command arrived. With the phone out of range, a Watch tap is queued with `transferUserInfo`. The Watch button re-enables after 4 s on the same step, so a second tap queues a second Done, and when the phone comes back both arrive and finish two steps. The same happens when `sendMessage` times out after the phone already acted (a cold background launch), because the error handler resends through `transferUserInfo`. 1.0.2 fixed this for the Live Activity and step alerts, not for the Watch. | Fixed: the Watch sends the `stepStartedAt` it showed, and the phone routes every Watch command through `RoutineStore.perform`, which ignores a Done, Skip or leave meant for a step that has already ended. Regression test `StoreTests.testAWatchTapSentTwiceMovesOnOneStep`. |
| P2 | `Shared/Services/RoutineStore.swift:280` | A Watch Done delivered late from the queue is timed at arrival, not at the tap, so a step can be recorded as longer than it really took. `latestTimedSeconds` limits the damage to the first hour. | Not fixed: the fix needs a tap timestamp in the Watch protocol, which is a feature change, not a definite break. |
| P2 | `ShoesOn/Views/PaywallView.swift:121`, `ShoesOn/Views/OnboardingView.swift:161`, `ShoesOn/Views/SettingsView.swift:166` | The trial length is hard-coded as 7 days in the copy while the plan card shows the product's own `trialLabel`. Correct today, since every territory has a one-week trial, but it would be wrong if the trial in App Store Connect changed. | Not fixed: correct for the live configuration, and changing it would change copy. |
| P2 | `Shared/Services/StoreService.swift:310` | Trial eligibility of `.unknown` (no receipt yet, or a slow StoreKit) reads as ineligible, so an eligible person can see "Subscribe" and still get the trial from Apple's sheet. This is conservative and keeps to guideline 3.1.2. | Not fixed: by design. |
| P2 | `ShoesOn/Views/RunView.swift:169` | "End without leaving" on a run started from the alert puts that departure's remaining "Not started yet?" nudges and leave alerts back, because no departure is recorded. This is arguably right (they have not left), but someone who ended the run because the day is off still gets nudged unless they also skip the day. | Not fixed: the intended behavior is unclear, so it is not definitely broken. |
| P2 | `Shared/Models/Routine.swift:79` | One-off day changes are stored as the start of the day in the time zone where they were made. After travel across time zones, `isDate(_:inSameDayAs:)` can put a change on the wrong day. | Not fixed: rare edge case. |

## Checked and clean

- Saved state: every field added after the first build is optional or decoded with a default (`Routine.changes`, `ActiveRun.isPractice`, `WatchPayload.upcoming`). The fields with synthesized defaults (`RunStep.skipped`, `PersistedState.pace`) were all present before any build reached users (`041f2ff`, 2026-09-26). No force unwraps on data, and every index is guarded.
- Purchases: the `default` offering falls back to `current`. Packages are filtered to yearly and monthly. Restore reports an error when no Pro subscription is found. Pending and cancelled purchases are handled. The paywall closes from its X, by itself once Pro is active, and onboarding offers "Get Started" without buying. Terms of Use (Apple EULA) and the Privacy Policy are linked on both paywalls and in Settings.
- Pro gating: `isPro` is cached in the App Group, so a cold launch never locks a paying user out of their extra routines' alerts. A change in Pro reruns `propagate()`, which brings back or drops those routines' alerts, widgets and Watch data. The Watch refuses commands without Pro.
- Trial reminder: it fires at 10 AM on day 5, is remembered across reschedules, and is cancelled when `willRenew` goes false.
- Notifications: alert IDs are deterministic, so nothing is scheduled twice. Reschedules run one at a time. The total stays under 64: 56 planned, at most 4 for the run in progress, and 1 trial reminder. Step alert Done is tied to its step.
- Release safety: `ScreenshotConfig` is constant false in Release, and the Debug Pro toggle is `#if DEBUG`. There are no health claims (Settings carries a "does not diagnose or treat" disclaimer), no other-platform links, and no hard-coded prices (they come from StoreKit).
- Widgets and Live Activity: every `timerInterval` range is guarded against an inverted range. The control and intents start nothing while a run is open.
- Localization: the app UI is English only (no string catalog), so there are no partial translations. Store copy for 50 locales is generated separately.
- Duo: `FoldSplit` only splits at a regular-width pane of 720 pt or more. The app is iPhone only and portrait.

## Tests

`gh-sim test --scheme ShoesOn --only ShoesOnTests`. Run id and result are in the commit that adds this report.
