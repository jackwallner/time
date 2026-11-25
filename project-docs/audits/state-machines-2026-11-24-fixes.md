# Fixes for the 2026-11-24 state machine audit

Fixes for every claim in `state-machines-2026-11-24.md` that survived the
skeptical review, in ranked order.

**Summary: 2 proved claims. 2 fixed, 0 held, 0 skipped.** One code-path item
(CP1) is held for Jack.

## Claims

| ID | Outcome | Commit | Regression test (`ShoesOnTests/StateMachineRegressionTests.swift`) | What changed |
|---|---|---|---|---|
| B1 | Fixed | `fix: a skipped or moved day stays on its day after a flight west` | `testASkipStaysOnItsDayAfterFlyingWest` (the repro), `testAOneOffTimeStaysOnItsDayAfterFlyingWestAndShowsThere`, `testPruningAfterFlyingWestKeepsTodaysChange`; controls `testASkipStaysOnItsDayInOneTimeZone`, `testASkipStaysOnItsDayAfterFlyingEast`; upgrade `testAChangeSavedBeforeTimeZonesWereKeptStillApplies` | `DayChange` keeps the time zone it was set in (optional, so 1.0.3 files decode) and `start(in:)` reads its calendar day there. `change(on:)`, `setChange`, `pruneChanges`, `upcomingChanges` and the store's foreground prune all match on that day. A change saved before this reads in the current zone, exactly as it did. |
| B2 | Fixed | `fix: saving a routine keeps a day skipped while the editor was open` | `testSavingTheEditorKeepsASkipMadeWhileItWasOpen` (the repro); controls `testSavingTheEditorKeepsAnEarlierSkip`, `testSavingTheEditorDoesNotBringBackAnUndoneSkip` | `RoutineStore.save` keeps the stored `changes` when it replaces an existing routine. The editor never edits one-off days; every change to them goes through `setChange`. |

Both regression tests failed on the starting commit (repro run
`time@20261125-090750-c093-claude-mbpro8d40-1125-091355-27507`) and should pass with
the fixes once the full suite runs (it did not start on GitHub in this
session; see `rollout-2026-11-24.md`).

## Held for Jack

- **CP1, an Ask to Buy trial approved later never gets its day-5 reminder.**
  Not proved (no `CustomerInfo` seam). The fix would schedule the reminder
  from the entitlement itself (an active `pro` in its trial period that will
  renew, with no reminder stored, scheduled two days before its expiration at
  10 AM) whenever customer info arrives. That changes when the trial reminder
  is scheduled, which is part of the trial flow. Recommendation: yes, since it
  also covers a trial restored on a new phone; it needs a decision on whether
  a reminder may be scheduled for a trial started elsewhere.

## Skipped

None.
