---
paths: ["android/**"]
---

# Shoes On on Android

Native Kotlin/Compose port in `android/`. The iOS app is the spec: same copy,
engine, alerts, flows, products and paid boundary. Shared conventions live in
the `android-dev` skill.

## Identity
- Package and namespace `com.jackwallner.time` (permanent once uploaded).
  Listing name `Shoes On: Time Blindness Coach`, launcher label `Shoes On`.
- `versionName` tracks iOS `MARKETING_VERSION`; `versionCode` goes up on every upload.
- RevenueCat entitlement `pro`, offering `default`, packages `$rc_annual` /
  `$rc_monthly`; Play subscriptions use the iOS product IDs with base plans
  `yearly` / `monthly` and a 7-day new-customer trial offer.

## Layout
- `model/`: pure ports of `Shared/Engine` and `Shared/Models` (Calibration,
  Planner, ActiveRun, NotificationPlan, Format). Swift `rounded()` is half away
  from zero: use `roundHalfAway`, never Kotlin `round`.
- `data/RoutineStore.kt` is the single door, as on iOS. Every mutation
  persists `filesDir/shoeson-state.json` and calls `AppGraph.propagate()`
  (AlarmManager alerts + the ongoing run notification).
- `data/Alerts.kt`: AlarmManager stands in for pending UNNotification
  requests. Exact alarms when granted, else a one-minute window. Get-ready
  alerts carry Start now / Skip this time; step nudges carry Done. The ongoing
  "Routine in progress" notification (countdown chronometer, Done) replaces the
  Live Activity.
- Launcher shortcut "Start getting ready" (`res/xml/shortcuts.xml`) replaces
  the iOS Control Center control.
- `data/NextStartWidget.kt` + `model/WidgetPhase.kt`: the free "Next start"
  home screen widget (iOS `NextDepartureWidget` small family). RemoteViews,
  no Glance. The last-hour countdown is a launcher-drawn `Chronometer`, so the
  app never wakes to tick it. `propagate()` redraws it, and a non-wakeup RTC
  alarm redraws at each phase change and midnight. The headline auto-sizes
  (16 to 34sp) like iOS `minimumScaleFactor(0.5)`.

## Intentional differences from iOS
- No Wear OS app, Lock Screen widget or Live Activity. Pro on Android is
  "every routine" only; the paywall does not mention a watch (decision pending, see
  `project-docs/android/play-release-prep.md`).
- Play review card is called straight after an on-time summary (same 3 on-time
  / 90-day tracker), no question first. Settings has separate Rate (Play
  listing) and Send feedback rows.
- Terms link to `docs/terms.html`, not Apple's EULA. Paywall disclosure names
  Google Play renewal and cancellation.
- "Remove animations" (animator scale 0) holds the run screen's glow still.

## Build and test (jmbp or jmbp2, never the Air)
- From the Air, run the Gradle tasks below with `fm-gradle <tasks>` from
  `android/` (it runs them on jmbp); the full command lines here are for work
  directly on a fleet host.
- `JAVA_HOME=~/jdks/temurin-17/Contents/Home ./gradlew --no-daemon
  "-Dorg.gradle.jvmargs=-Xmx2g -XX:TieredStopAtLevel=1" --max-workers=2 <tasks>`
  in `android/`. On jmbp2 the C2 JIT crashed the Gradle JVM once
  (`Matcher::find_shared`); `TieredStopAtLevel=1` avoids it.
- `testDebugUnitTest` (88 tests: every iOS Planner, Run, NotificationPlan,
  Store, DayChange and PaywallFunnel test one for one, plus Format, codec,
  reviewer access, WidgetPhase), `assembleDebug lintDebug`, then
  `ANDROID_SERIAL=emulator-5554 ./gradlew connectedDebugAndroidTest`
  (`ShoesOnFlowTests`, 11). The connected run uninstalls the app and leaves
  `animator_duration_scale` at 0; set it back to 1 before screenshots.
- jmbp2 AVD `agent-emu-1` (API 36, x86_64): `emulator -avd agent-emu-1 -port
  5554 -no-window -no-audio -no-boot-anim -no-metrics -no-snapshot-save`; wait
  for `sys.boot_completed` = 1; stop with `adb -s emulator-5554 emu kill`.
  System UI may ANR right after boot (tap Wait). It renders with SwiftShader at
  about 10 fps, so tests stretch `AppClock.runTickMillis` to 30 s or Compose
  never idles; motion review belongs on jmbp or the Air.
- On a cold boot jmbp2's system server can restart mid-run: Gradle then
  reports BUILD SUCCESSFUL with `tests="0"`. Always check the XML count and
  rerun. Use `-Xmx1500m --max-workers=1` there and one task per invocation;
  a combined assemble + androidTest + lint run was SIGKILLed (exit 137).
- Placing the widget by adb: long-press empty home, Widgets, type "Shoes" one
  letter at a time (fast `input text` drops letters), tap the result, tap the
  preview, then Add. Escape closes the picker.
- Debug launch extras (`src/debug/.../DebugLaunchOptions.kt`, release no-op):
  `reset`, `seed`, `screen` run|leaving|summary, `seedDayChanges`,
  `onboardingPage` N, `paywall` yearly|monthly, `demoPro`, `free`,
  `fixedNow` HH:mm, `appearance` light|dark. Example:
  `adb shell am start -n com.jackwallner.time/.MainActivity --ez seed true --es screen run`.

## Keys and boundaries
- `android/local.properties` (ignored): `REVENUECAT_TEST_KEY` (debug only),
  `REVENUECAT_PLAY_KEY` and upload keystore entries (release, Air only),
  `PLAY_REVIEW_CODE_SHA256` (optional reviewer access).
- `StoreService` refuses a `goog_` key in debug and anything else in release.
  Debug with no key shows fixture plans with purchases off. The `qa` build type
  is release code with no key.

## Store assets
- `android/play-assets/` holds the listing copy, icon, feature graphic and
  five screenshots in the `play_stage.py` layout; its README records how each
  was made. Play accepts 2:1 at most, so captures are 1080 x 2160 (`wm size`,
  or the native 2400 cropped). Turn heads-up notifications off first: the
  seed schedules real alerts that pop over the app.

## Play Console state (2026-10-20)
- Not on Play. No app record, upload, products or RevenueCat Play app.
  Release prep and the remaining steps: `project-docs/android/play-release-prep.md`.
