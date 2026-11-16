# Feature Badge V1

## Approved appearance

Option 06 uses a native noninteractive regular Liquid Glass capsule (32% tint opacity) on iOS 26+. On iOS 15–25 the same capsule uses a flat fill. Both retain scaled 12 pt bold system text, expanded width on iOS 16+, standard width on iOS 15, 8 pt horizontal and 3 pt vertical padding, and a centered 6 pt title gap. Accessibility text sizes stack the label and badge.

| Badge | Glass tint | Light foreground / fallback fill | Dark foreground / fallback fill |
| --- | --- | --- | --- |
| NEW | `#3D88EC` | `#005BC3` / `#E6F0FF` | `#82B5FF` / `#203650` |
| BETA | `#8B5CF6` | `#6537B5` / `#EFE7FF` | `#D3B4FF` / `#34264D` |

The visible labels are uppercase English in every language. The native control receives the localized feature title and a localized New feature or Beta feature description; the decorative badge is not a separate accessibility element. Removing a placement also removes its spoken status. Translation catalogs cover all 19 app languages.

## Placements and lifecycle

- NEW: **Settings > Timer > Keep Screen Awake**.
- BETA: **Settings > Connected Devices**, plus **Smart Cube** and **Smart Timer** in that list. Device names and Timer shortcuts are not badged.

Both badges are developer-controlled placements. NEW remains through bug-fix, maintenance and performance-only updates. When the next release introduces a batch of features requiring NEW, replace the previous NEW placements manually. BETA remains until the developer explicitly removes it. Neither badge depends on marketing version or build number; there is no automatic expiration, dismissal state, or migration.

The temporary palette/text override and comparison harness were removed. Existing color comparison PNGs and palette values remain in the ignored `build/feature-badge-palettes/final/` directory. No onboarding or broader feature-discovery work is included.

## Verification

The lifecycle correction replaces expiration tests with checks of developer-controlled visual and spoken status. The rendering test uses the actual local bundle without a version override. It captures the four placements in both appearances and separately demonstrates that omitting the NEW placement removes the badge while retaining the toggle.

- iPhone 17 Pro simulator, iOS 26.5: 23 focused tests passed (4 badge, 3 Keep Screen Awake, 16 Smart Cube settings/navigation), with no failures or skips. The earlier mounted Keep Screen Awake timeout did not recur.
- All 19 localization catalogs passed syntax and badge accessibility key checks. The unsigned generic iOS Debug build passed with a 15.0 deployment target. No app version or build setting was changed for this correction; the tested local bundle reports 0.16.0 (1).
- The result bundle and six rendering captures are kept locally under `build/feature-badge-lifecycle/`. This pass did not run the fallback on an iOS 15 device, perform a live VoiceOver check, or operate physical hardware.
