---
paths:
  - "ShoesOn/App.swift"
  - "ShoesOn/Views/**"
  - "Shared/Utilities/UnfoldedSplit.swift"
  - "ShoesOn/Info.plist"
  - "project.yml"
---

# Shoes On: iPad layout

iPad support is permanent once shipped: `TARGETED_DEVICE_FAMILY "1,2"` on the
app and the Live Activity widget (Watch targets stay Watch), all four iPad
orientations in `UISupportedInterfaceOrientations~ipad`, iPhone stays portrait.

- **Home and the run** use `FoldSplit`, the iPhone Duo machinery: at regular
  width of 720pt or more it puts two phone-width panes side by side (Home beside
  History, the run beside its plan). iPad inherits it, including Split View
  widths, so nothing iPad specific is needed there.
- **Onboarding and the paywall** are one phone-width column: `readableColumn()`
  (560pt, centred, in `Components.swift`). Onboarding pages centre vertically at
  regular width so a tall screen does not hang them from the top. On iPad the
  setup root skips `FoldSplit` and its logo pane; Duo keeps it.
- **Sheets** (Settings, routine editor, Pro, day change) are system form sheets
  on iPad and keep their phone layout inside it.
- **Live Activities and alarms**: iPad has no Lock Screen run, so the Settings
  "turn on Live Activities" row is phone only (`refreshPermissions`). Alerts are
  plain notifications and work as on iPhone. `StoreService.shared` must never run
  its `didSet` inside its own init (it re-enters the singleton and crashes).
- **Proof**: `gh-sim launch --device "iPad Pro 13-inch (M5)"` for portrait. gh-sim
  cannot rotate, so landscape and Split View need a leased local iPad sim
  (`agent-sim checkout`). Screenshot args are in `store-and-release.md`.
  `-OnboardingPage` and `-PaywallSnapshot` mount the view bare, so they show the
  column, not the real sheet.
