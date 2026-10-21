# Shoes On on Google Play: release prep (2026-10-20)

Prepared on fleet run `shift-android-time-1-1792530761` (jmbp2). Nothing has
been uploaded or created in Play Console or RevenueCat yet.

## Build facts

- Package `com.jackwallner.time` (same as the iOS bundle ID; permanent after
  the first upload). Namespace the same.
- `versionName` 1.0.1 (iOS `MARKETING_VERSION`), `versionCode` 1.
- `minSdk` 26, `targetSdk` 36, `compileSdk` 36.
- Permissions: `INTERNET` (RevenueCat), `POST_NOTIFICATIONS` (asked on the
  reveal page, like iOS), `RECEIVE_BOOT_COMPLETED` (alarms do not survive a
  reboot), `SCHEDULE_EXACT_ALARM` (user-granted, off by default on Android 14+;
  no Play declaration needed, unlike `USE_EXACT_ALARM`). Without the grant,
  alerts use a one-minute window and Settings shows "Allow alarms and
  reminders".
- No ads, no analytics SDK, no account, no backend. Routines stay in
  `filesDir/shoeson-state.json`, excluded from backup and device transfer.
- Signed AAB: the Air release worker (signing keys stay on the Air).
  `validateReleaseConfiguration` fails a release task without
  `REVENUECAT_PLAY_KEY` (`goog_`) and the upload keystore.

## Listing copy

`android/play-assets/listing/`: title (30), short description (77), full
description. Written from Android behaviour: no Live Activity or Watch claims;
the ongoing run notification with Done stands in for the Lock Screen view,
and the free "Next start" home screen widget (2026-10-20) is named once. No prices, no em dashes, no ADHD treatment claim.

Icon: `android/play-assets/icon-512.png` (iOS icon, no alpha).
Still to make: the 1024 x 500 feature graphic, and four 1080 x 1920 phone
screenshots composited from the raw captures (raw ones: Home, run, leaving,
summary, paywall in the run's evidence folder; Play rejects the raw 1080 x 2400
ratio). A widget capture on the launcher (countdown, Start now) is in
`~/fleet-evidence/shift-android-time-4-1792544616/screenshots/` on jmbp2.

## Data Safety answers (from the code)

- Data collected: **Purchase history** (RevenueCat, via Google Play Billing),
  **App interactions** limited to paywall-view counts sent as RevenueCat
  subscriber attributes (`pitch_views_*`, `converted_*`), and the RevenueCat
  anonymous **device or other ID**. Purpose: app functionality (entitlement)
  and analytics (purchase funnel). Not shared with third parties for their own
  use, not sold. Encrypted in transit: yes. Deletion: users can delete the app;
  no account exists to request deletion against.
- Not collected: location, contacts, health, personal info, messages, files,
  calendar. Routines and step timings never leave the device.
- Privacy policy URL: https://jackwallner.github.io/time/privacy-policy.html
  (Android section added in this run; publishes when `docs/` is pushed).

## Other App content forms

- App access: everything without login. Pro is a subscription. Optional
  reviewer access: long-press the version line at the bottom of Settings and
  enter the code; only its SHA-256 (`PLAY_REVIEW_CODE_SHA256` in ignored
  `android/local.properties`) ships. Empty digest turns it off. Jack picks the
  code and puts it in the review notes.
- Ads: none. Target audience: 18+ (adults managing their own mornings),
  not designed for children. Content rating: IARC questionnaire, no
  objectionable content. Health declaration: not a health app (planning aid,
  disclaimer in Settings). Category: Productivity (iOS primary).

## Decisions needed from Jack

1. **Pro on Android without a Watch.** iOS Pro is "every routine" plus the
   Apple Watch coach. There is no Wear OS app, so Android Pro is every routine
   only, at the same prices. Keep it, add a Wear OS app later, or price
   differently? The paywall says only what Android delivers.
2. **Reviewer code**: choose one and set `PLAY_REVIEW_CODE_SHA256` on the Air,
   or leave reviewer access off.
3. **RevenueCat Test Store key** for project `proj457863e6`: not on any fleet
   machine. Debug builds without it show fixture plans (iOS prices) with
   purchases off, mirroring the iOS simulator. Add `REVENUECAT_TEST_KEY` to
   `android/local.properties` on jmbp/jmbp2 to run the Test Store purchase path.

## Products (create in Play Console before RevenueCat)

- Subscription `com.jackwallner.time.yearly`, base plan `yearly` (1 year,
  auto-renewing, US $9.99), offer: 7-day free trial, new customers.
- Subscription `com.jackwallner.time.monthly`, base plan `monthly` (1 month,
  US $1.99), offer: 7-day free trial, new customers.
- Review Play's converted local prices against `~/ios/pricing/plan_shoeson.py`
  (the iOS PPP ladder) before activating.
- RevenueCat project `proj457863e6`: add the Play app, attach both products to
  entitlement `pro`, offering `default`, packages `$rc_annual`, `$rc_monthly`.
  Register the Android block in `~/.rc-clean/apps.json` on the Air and copy it
  to the MBP. The Play service account needs access to the new app.

## Remaining Console steps, in order

1. Create the app record (Air, Jack's Chrome), package `com.jackwallner.time`.
2. Air release worker: signed AAB, bundle inspection (target SDK, 16 KB page
   alignment, permissions), internal testing upload.
3. Products and offers above, then RevenueCat mapping and rc-clean registration.
4. Listing, feature graphic, composited screenshots, Data Safety, content
   rating, target audience, app access.
5. License-tester purchase and restore on a Play image; pre-launch report.
6. Production submission only under fleet pacing (one new app at a time on the
   E3 Apps account), managed publishing off.
