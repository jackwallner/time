# State machine audit, 2026-11-24

Scope: the Shoes On iOS app, its Live Activity and Lock Screen intents, the
Next-start widget and the Watch app's command path. Android is out of scope.
Audited from `1a18cfb` (the fleet snapshot of `d095a7a`). No app code was
changed for the audit.

**Summary: 2 bugs proved by failing test (B1, B2), 1 code path only (not
proved, not counted), 5 product calls (not counted).** Both bugs survived the
skeptical review below.

Evidence run: `gh-sim test --scheme ShoesOn --only ShoesOnTests/StateMachineRepro`
on the starting code with only the repro file added, run
`time@20261125-090750-c093-claude-mbpro8d40-1125-091355-27507`
(GitHub Actions 45662548502). Result: 5 tests, 3 passed (the controls), 2 failed (the claims); Xcode 27.1, iPhone 17, iOS 27.2. The suite is
`state-machines-2026-11-24-repro.swift` beside this file; copy it into
`ShoesOnTests/` to run it.

Seams used: `RoutineStore(fileURL:)` on a temporary file, and the
`calendar:` parameter every `Routine` date function already takes. No seam
exists for a constructed RevenueCat `CustomerInfo`, so entitlement and
purchase-unlock items stay code path or product calls.

## Bugs ranked by impact

| ID | Bug | What the user sees | Promise | User route | Population and frequency | Evidence | file:line |
|---|---|---|---|---|---|---|---|
| B1 | A one-off day (skip or other time) moves to the day before after the phone changes to a time zone further west | Skip Wednesday in New York, fly to Los Angeles: Tuesday gets no alerts, Wednesday's alerts all fire, and the "Just this once" card says Tuesday. Same for a one-off leave time. | `Routine.swift:18-21`: "A one-off change to a single day ... Holidays, sick days and the early dentist appointment are where a fixed schedule fails; this is how the routine bends". Home menu copy "Skip \(day)" (`HomeView.swift:351`). AGENTS.md: "Just this once: skip a day or give it a one-off time". | Home, the `...` menu on the next departure, "Skip tomorrow" (or "Change another day", pick a day, Save). Travel west before that day. Open the app (or not: the alerts already scheduled are rebuilt on the next foreground with the wrong day). | Anyone who sets a one-off and then moves west before it: travel is a main reason to skip a day. Each such change lands on the wrong day; flying east is unaffected. | `testASkipStaysOnItsDayAfterFlyingWest` failed with "XCTAssertFalse failed - the skipped Wednesday must stay skipped in Los Angeles". Preconditions asserted first: Wednesday skipped and Tuesday departing in New York. Controls `testControlASkipStaysOnItsDayInOneTimeZone` and `testControlASkipStaysOnItsDayAfterFlyingEast` passed. | `Routine.swift:79-81` (`change(on:)` compares the stored New York midnight with a Los Angeles day), `:133-135`, `:146-153` |
| B2 | Saving the routine editor undoes a skip made while it was open | The user skips today from the get-ready banner's "Skip this time" (or the Lock Screen) while the editor sheet is up, then taps Save: today is back on, and "Not started yet?", "Leave in 10 minutes" and "Time to go" fire for a morning they skipped. | AGENTS.md: "Just this once: skip a day ... from Home or the 'Skip this time' notification action (`Routine.changes`)." `NotificationService.swift:211-213` saves the skip. | Home, the real plan's Edit (sheet open). A get-ready alert arrives; long-press the banner (or the Lock Screen copy), "Skip this time". Back in the editor, change anything, Save. | Rare: needs the editor open across a get-ready alert. Every time it happens the skip is lost silently. | `testSavingTheEditorKeepsASkipMadeWhileItWasOpen` failed with "XCTAssertNotNil failed - the skip must survive an unrelated edit". Preconditions: the skip is saved and the editor copy predates it. Control `testControlSavingTheEditorKeepsAnEarlierSkip` passed. | `RoutineStore.swift:205-214` (`save` writes the editor's whole copy, its `changes` included); editor copy `RoutineEditorView.swift:16-20` |

### Code path only (not proved, not counted)

- **CP1, an Ask to Buy trial approved later never gets its day-5 reminder.**
  `StoreService.purchase` schedules `scheduleTrialReminder` only when the
  purchase call itself returns Pro (`StoreService.swift`, the `if isPro`
  branch). An Ask to Buy request throws `paymentPendingError`; the later
  approval unlocks through the delegate's `update(customerInfo:)`, which never
  schedules the reminder. The trial page's timeline promises "Day 5: A
  reminder before your trial ends." No test seam builds a `CustomerInfo`, so
  this is not proved. Held for Jack (it changes when the trial reminder is
  scheduled, part of the trial flow).

## Product calls (not counted)

1. **Ending a real run with "End without leaving" keeps that morning's leave
   alerts.** The departure is still scheduled, so "Leave in 10 minutes" and
   "Time to go" can follow. Arguably right (they may still go), arguably noise.
2. **A practice run left open blocks the get-ready alert's start.** A
   practice run starts more than an hour before the alert, so it only collides
   when it is left open into the real start time (`startRunFromAlert` returns
   while any run is open). The app opens on the stale practice run and the
   user ends it by hand.
3. **A departure already made today does not cover a leave time edited
   later the same day.** Leaving at 8:15 then moving the routine (or today's
   one-off) to 9:00 schedules a second departure today.
4. **Many Pro routines shrink the alert window.** 56 scheduled requests across
   routines, each with up to five alerts, covers about 3 days with three daily
   routines instead of the ~10 AGENTS.md describes. Rebuilt on every foreground.
5. **A trial reminder can fire after a cancel made outside the app.** It is
   cancelled only on a customer-info update, so a user who cancels in Settings
   and never opens the app again still gets "renews ... unless you cancel".

## Machines

### 1. Setup

States: fresh (no routine, `hasCompletedSetup` false), routine saved on the
offer page (routine, not complete; `RootView.resumesAtOffer`), complete.
Invariant: a saved routine with setup unfinished resumes at the offer, never
page one. Pro landing on the offer finishes setup. Checked: OK.

### 2. Run

States: none, active (step i), leaving (every step done or skipped),
finished (`lastFinished`, the summary), plus the practice flag and the
in-memory undo (`StepUndo`).

| From | Event | To | Guard |
|---|---|---|---|
| none / finished | Start (Home, alert, Lock Screen control, Watch, Siri) | active 0 | no open run, routine not locked |
| active i | Done / Skip (app, Live Activity, step alert, Watch) | active i+1 or leaving | step identity (`stepStartedAt`), 0.6 s double tap |
| active i | catch-up drop | active i | step after current |
| any active | Undo within 5 s | the state before | run unchanged since |
| leaving | I'm out the door / Live Activity / Watch leave | finished | open run |
| active | End without leaving | none | |
| active | 3 h past leave, on foreground or next tap | none | |
| finished | Done, 12 h, next start | none | |

Invariants checked: a late or repeated Done never finishes the next step
(fixed earlier, `f83218b`); undo removes the timing it added; abandoned runs
record no departure; practice runs record no departure. OK.

### 3. Departures per day

Inputs: weekdays, `Routine.changes` (one per day), departures made (by exact
target), the active run. Derived: `nextPlan`, `upcomingDepartures`,
`NotificationPlan.scheduledAlerts`, the widget snapshot. Invariant: a day's
change applies to that calendar day wherever the phone is (broken, B1), and
survives every unrelated write (broken, B2).

### 4. Notifications

One pure plan (`NotificationPlan.alerts`) rebuilt on every store write and
every foreground; pending requests not in it are removed (the trial reminder
is kept). Get-ready, two nudges, leave soon, leave now per departure; wrap-up,
overrun and leave alerts for the run. Checked: alerts for a started, skipped,
made or locked departure are removed on the write that changes it; a later
permission grant is picked up on the next foreground; toggles reschedule at
once. OK apart from product calls 1 and 4.

### 5. Entitlement and purchase

`isPro` seeded from the cached flag, then RevenueCat customer info
(launch fetch and delegate). Without Pro only the first routine runs and
alerts, and the Watch is locked; nothing is deleted. Purchase: idle,
purchasing, then purchased, cancelled, pending (a purchase that returned
without the entitlement) or failed. Ask to Buy throws `paymentPendingError`
and shows "Couldn't start your trial", which Rollout A of the same run
addresses (not counted here). Trial reminder: scheduled on a trial purchase,
kept across reschedules, cancelled when the entitlement will not renew (CP1,
product call 5).

### 6. Review ask

1.0.3: after the third on-time departure, from the summary's Done button,
every 90 days. Replaced by Rollout S (see `rollout-2026-11-24.md`).

### 7. Live Activity, Watch, widget

All three mirror the store through `propagate()`. The Live Activity is
matched by leave time and routine name and ended when no run is open. The
Watch drops payloads older than the one it has (`sentAt`). The widget reloads
only when its snapshot changes. Checked: OK.

## Skeptical review (phase 2)

- **B1 survives.** The route is two taps in shipping UI plus a flight. The
  test uses the app's own `calendar:` parameters, which production fills with
  `Calendar.current`, whose zone follows the phone. The east control passing
  shows the harness is not simply mis-dating days.
- **B2 survives, rare.** `RoutineEditorView` keeps its own `@State` copy from
  when the sheet opened, and the notification's Skip action runs with the app
  in the foreground or background while the sheet stays up. The test drives
  the same store calls the sheet and the action make. Low reach, real loss.
- **CP1 stays code path only**: no headless way to deliver a
  `CustomerInfo` with an active trial.
- Dropped before writing: "a stale Live Activity stays on the Lock Screen
  after a run is abandoned" (AGENTS.md promises expiry only on foreground),
  and "notifications are added while permission is denied" (they are re-added
  on every foreground, so a later grant works).
