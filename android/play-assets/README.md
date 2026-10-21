# Google Play store assets

Laid out for `~/docs/android/tools/play_stage.py listing com.jackwallner.time android/play-assets --email ...`.

| File | What it is |
|---|---|
| `metadata/android/en-US/title.txt` | App name, the live App Store name (30 / 30) |
| `metadata/android/en-US/short_description.txt` | Short description (77 / 80) |
| `metadata/android/en-US/full_description.txt` | Full description, plain text (about 2,400 / 4,000) |
| `icon-512.png` | 512 x 512 app icon, RGB, no alpha |
| `feature-graphic.svg` | Editable source for the feature graphic |
| `feature-graphic.png` | 1024 x 500 RGB feature graphic, no alpha |
| `screenshots/01-*.png` to `05-*.png` | Five 1080 x 2160 (2:1) RGB phone screenshots |

## How they were made (2026-10-21)

**Metadata.** The Android listing copy from `listing/` (written from Android
behaviour: run notification instead of Live Activity, no Watch), moved into
the `metadata/android/en-US/` layout unchanged. No prices, no em or en dashes,
and it says it does not diagnose or treat ADHD or any other condition. Edit
these files directly; they are the source of truth.

**Icon.** The iOS app icon at 512 x 512, kept as it was.

**Feature graphic.** `feature-graphic.svg` uses the app icon's art: its
yellow-to-orange morning gradient (`#ffd54c` to `#ff9f2f`) and the mark (navy
`#2a1e6e` open dial and hub, white arrow), copied from the launcher vector's
1024 grid, beside the name and one line in the same navy. Text is live, so
edit it in the SVG. It was rendered with headless Chrome at 1024 x 500 and
flattened to RGB with Pillow.

**Screenshots.** Real screens from a debug build (`assembleDebug`) on the
`agent-emu-1` AVD (API 36, x86_64) on jmbp. Pro was on through the debug-only
`demoPro` local override; no RevenueCat purchase or production key was used.
Each was launched with the debug extras in `DebugLaunchOptions.kt`, which seed
twelve weekday mornings of history (`ScreenshotFixtures`) and pin the app
clock with `fixedNow`:

```sh
adb shell am start -n com.jackwallner.time/.MainActivity --ez demoPro true \
  --ez seed true [--es screen run|summary|leaving] --es fixedNow HH:mm
```

SystemUI demo mode was on (clock matching `fixedNow`, full Wi-Fi, no SIM,
full battery, no notification icons), heads-up notifications were off, and
`font_scale` was 1.0.

1. `01-know-when-to-start`: Home, `fixedNow 06:19`. Captured at the native
   1080 x 2400 and cropped to the top 2160 rows, so the gesture handle does
   not sit over the plan list. Scrolled slightly so no row is cut at the bottom.
2. `02-plan-with-your-real-pace`: onboarding reveal page. `--ez reset true
   --ei onboardingPage 1`, then "35 to 40 minutes", the default 8:15 AM
   weekdays, and Wake up, Shower, Get dressed and Breakfast ticked.
3. `03-see-when-you-are-slipping`: `screen run`, `fixedNow 07:31`, Breakfast
   3 minutes behind with the catch-up offer.
4. `04-learn-what-each-step-takes`: `screen summary`, `fixedNow 08:13`.
5. `05-walk-out-on-time`: `screen leaving`, `fixedNow 08:08`.

Shots 2 to 5 were captured with `wm size 1080x2160`, which keeps the
bottom buttons clear of the gesture handle. Change `font_scale` or `wm size`
and demo mode resets, so re-enter it before each capture.
