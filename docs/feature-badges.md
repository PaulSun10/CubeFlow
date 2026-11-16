# Feature Badge V1

## Approved appearance

Option 06 uses a native noninteractive regular Liquid Glass capsule (32% tint opacity) on iOS 26+. On iOS 15–25 the same capsule uses a flat fill. Both retain scaled 12 pt bold system text, expanded width on iOS 16+, standard width on iOS 15, 8 pt horizontal and 3 pt vertical padding, and a centered 6 pt title gap. Accessibility text sizes stack the label and badge.

| Badge | Glass tint | Light foreground / fallback fill | Dark foreground / fallback fill |
| --- | --- | --- | --- |
| NEW | `#3D88EC` | `#005BC3` / `#E6F0FF` | `#82B5FF` / `#203650` |
| BETA | `#8B5CF6` | `#6537B5` / `#EFE7FF` | `#D3B4FF` / `#34264D` |

The visible labels are uppercase English in every language. The native control receives the localized feature title and a localized New feature or Beta feature description; the decorative badge is not a separate accessibility element. An expired badge contributes no spoken status. Translation catalogs cover all 19 app languages.

## Placements and lifecycle

- NEW: **Settings > Timer > Keep Screen Awake**, introduced in marketing version 0.16.1.
- BETA: **Settings > Connected Devices**, plus **Smart Cube** and **Smart Timer** in that list. Device names and Timer shortcuts are not badged.

The shared policy reads `CFBundleShortVersionString` and compares three numeric components to the feature's declared version. NEW appears only on an exact match, including every build of that version. Missing or malformed metadata hides NEW. BETA ignores metadata and remains until its placement is removed. No dates, counters, user dismissal, or migration are involved. Permanent previews and tests can inject a version; project metadata is unchanged.

The temporary palette/text override and comparison harness were removed. Existing color comparison PNGs and palette values remain in the ignored `build/feature-badge-palettes/final/` directory. No onboarding or broader feature-discovery work is included.

## Verification

On the iPhone 17 Pro simulator (iOS 26.5), all five badge tests and all 16 Smart Cube navigation and management tests passed. The combined 24-test run had one mounted Keep Screen Awake test time out on tab return (and emit an InvalidTransition error); the isolated rerun passed all three Keep Screen Awake tests without test or code changes.

Native render captures are in `build/feature-badge-v1/screenshots/`: `settings-*.png` (injected 0.16.1), `devices-*.png`, and `settings-after-update-*.png` (injected 0.16.2). Both appearances were captured; text recognition verifies the expected badge counts. The unsigned generic iOS Debug build passed with an iOS 15.0 target; the local build remains marketing version 0.16.0. Localization and diff checks passed. Physical VoiceOver, appearance and pre-iOS-26 runtime verification were not performed.
