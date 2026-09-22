---
paths:
  - "scripts/**/*"
  - "fastlane/**/*"
  - "Shared/Services/StoreService.swift"
  - "Shared/Utilities/ScreenshotFixtures.swift"
  - "ShoesOnUITests/**/*"
  - "ShoesOn.storekit"
---

# Shoes On: store setup, screenshots and release

## Built 2026-09-22

- Bundle IDs registered with `scripts/asc-register-identifiers.py`.
- ASC record created in the web UI (the public API cannot create apps).
- `scripts/asc-setup-lifetime-iap.py` created the lifetime IAP: $14.99 USD
  base, all 175 territories, `READY_TO_SUBMIT` once the review screenshot is
  added. No PPP overrides yet; `~/ios/pricing/apply_iaps.py` can add them.
- RevenueCat was set up with the `rc` CLI (OAuth login):
  `rc projects create`, `rc apps create --type app_store` with the shared ASC
  key `9T82M4AZQ2` and In-App Purchase key `27M3333KDW`, then product,
  entitlement `pro`, offering `default`, package `$rc_lifetime`.
  An empty duplicate project `proj501d15fa` with the same name exists from a
  retried create; the CLI cannot delete projects, so remove it in the dashboard.

## First submission still needs

- The first non-consumable must be attached to the version by hand in the
  ASC UI (see `ios-dev` skill, "Submitting IAPs with a version").
- IAP review screenshot: render `-PaywallSnapshot` under StoreKit Testing
  (`ScreenshotUITests.testPaywallShowsTheLocalizedPrice`).
- App Store screenshots, App Privacy labels (Purchases: App Functionality,
  not linked, no tracking), age rating, review contact.

## Launch arguments (DEBUG)

- `-SeedScreenshotData`: twelve weekday mornings of history on one routine.
- `-Screen run|leaving|summary`: open a run in that state (with the seed).
- `-OnboardingPage N`: open onboarding at page N (0 to 5).
- `-PaywallSnapshot`: the paywall alone. `-DemoPro`: Pro on.
- Watch: `-SeedScreenshotData [-Screen idle] [-Free]`.

`ScreenshotUITests` renders every surface and attaches PNGs; export with
`xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>`.
Fixture times are relative to now, so clock times in captures vary.
