---
paths:
  - "scripts/**/*"
  - "fastlane/**/*"
  - "app-store/**/*"
  - "research/**/*"
  - "Shared/Services/StoreService.swift"
  - "Shared/Utilities/ScreenshotFixtures.swift"
  - "ShoesOnUITests/**/*"
  - "ShoesOn.storekit"
---

# Shoes On: store setup, screenshots and release

## Store setup (2026-09-22)

- Bundle IDs: `scripts/asc-register-identifiers.py`. ASC record: web UI (the
  public API cannot create apps).
- Subscriptions: `scripts/asc-setup-subscriptions.py` (group "Shoes On Pro",
  yearly level 1, monthly level 2, one-week trial in every territory, localized
  names from `fastlane/metadata/<locale>/products.json`). USA base only; the
  per-territory ladder came from `~/ios/pricing/plan_shoeson.py` + `apply.py`
  (348 rows). The first version shipped a $14.99 lifetime; it was deleted
  before any submission.
- RevenueCat via the `rc` CLI (OAuth): app created with the shared ASC key
  `9T82M4AZQ2` and In-App Purchase key `27M3333KDW`; products, entitlement
  `pro`, offering `default`, packages `$rc_annual` / `$rc_monthly`.
- Listing: `scripts/build-locale-metadata.py` then
  `scripts/asc-upload-localizations.py --all-locales`;
  `scripts/asc-configure-listing.py` sets rights, categories (Productivity,
  Lifestyle), age rating, review contact (phone from `~/.time_credentials`,
  never the repo) and notes.

## Keywords

Research and decisions: `research/keywords-2026-09-22.md`. Keyword fields
per locale live in `scripts/keyword_research.py`. Astro temporary app `133`;
migrate to `6814953557` at launch.

## Screenshots

- App Store set: `app-store/screenshots.json`, rendered with
  `~/ios/appstore-screenshots/bin/shotflow`. `-FixedNow HH:mm` (DEBUG,
  `AppClock`) pins the clock so captures read as a morning.
- Paywall review renders: `ScreenshotUITests.testPaywallShowsEachPlanPrice`,
  one per product, under StoreKit Testing.
- Sync with `~/ios/appstore-screenshots/bin/asc-sync-screenshots`, never a
  repo-local uploader.

## First submission

The first subscription group must be attached to the version in the ASC UI
(group page and each subscription page, Add for Review, pick the draft). See
the `ios-dev` skill.

## Launch arguments (DEBUG)

- `-SeedScreenshotData`: twelve weekday mornings of history on one routine.
- `-Screen run|leaving|summary`: open a run in that state (with the seed).
- `-OnboardingPage N`: onboarding at page N (0 to 5).
- `-PaywallSnapshot [yearly|monthly]`: the paywall alone. `-DemoPro`: Pro on.
- `-FixedNow HH:mm`: shift the app clock.
- Watch: `-SeedScreenshotData [-Screen idle] [-Free]`.
