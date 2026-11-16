# System Default Language

## Findings

Before this change, Settings already had a partial Follow System option. It was translated in English and both Chinese catalogs. The app registered a nonpersistent `appLanguage` fallback at launch and when returning active, but derived it from `Locale.preferredLanguages` rather than CubeFlow's effective bundle language. Many existing AppStorage readers also have an English fallback if the registration is missing. A persisted English value takes precedence over the registration, as intended. The source and Git history do not establish whether the reported iPhone had a saved English value or hit the system resolver path. Older AppStorage declarations alone are not evidence that a default was persisted.

## Behavior

**Settings > General > Language** starts with System Default and retains all 19 named languages in their existing order. The app reads `Bundle.main.preferredLocalizations` first for the effective native language, including the iOS app-level language, then uses Foundation's regional matching against the supported identifiers and the system's ordered preferences if the bundle has no supported choice. English remains the fallback for no supported match. See [Apple's per-app language guidance](https://developer.apple.com/videos/play/wwdc2019/403/?time=1160) and [iOS matching rules](https://developer.apple.com/library/archive/qa/qa1828/_index.html).

Simplified Chinese (such as China and Singapore) resolves to `zh-Hans`. Hong Kong, Taiwan and Macao resolve to the shared `zh-Hant` catalog; CubeFlow does not ship separate Hong Kong and Taiwan translations. An explicit script takes precedence. Brazilian and European Portuguese use `pt-BR` and `pt-PT`. Foundation handles related locale fallbacks such as `pt-AO` to `pt-PT`.

The persistent `appLanguage` key remains the in-app override. A missing key means System Default; the resolved system language is registered in memory, not persisted as a manual choice. Returning to System Default refreshes the registration before removing the override. Existing saved values, including English, are not reset or migrated. Settings also updates the selected option when only the mode changes and the effective text language stays the same.

Existing consumers keep their AppStorage bindings, locale and RTL wiring, and separate numeral settings. No changes to Base, development language, navigation, or the WCA, Battle and screen-awake implementations.

## Changes and physical acceptance

Changed `AppLocalizationSupport.swift`, `SettingsTabView.swift`, translated the System Default string across all 19 catalogs (the two existing Chinese translations were retained), added `AppSystemLanguageTests.swift`, and updated `ROADMAP.md` and this report.

On iPhone, verify a first launch with a non-English device language and no saved override; choose a different native iOS CubeFlow language with System Default; pick an explicit language in CubeFlow and relaunch; then return to System Default. Include Arabic RTL, both Portuguese variants, and Chinese (Simplified, Hong Kong and Taiwan). Native iOS changes may relaunch the app; in-app selection does not require an app restart.

Physical verification was unavailable for the v0.16.1 closeout.

## Automated verification

94 selected tests passed on the iPhone 17 Pro simulator (iOS 26.5, Xcode 27.2): 5 new language tests, 1 existing language regression, 5 Battle, 3 Keep Screen Awake and 80 WCA coordinator tests. These include mocked native language precedence and observed SwiftUI registration changes, not physical use of iOS's per-app language screen. Results: `build/system-language/focused.log` and `focused.xcresult`.

All 19 shipped catalogs contain the option exactly once, pass `plutil -lint`, and were checked for the key in their compiled bundles. `git diff --check` passed.

The unsigned generic iOS Debug build passed with the iOS 27.2 SDK and iOS 15.0 deployment target (`build/system-language/device-debug.log`). No iOS 15 runtime or physical-device checks were run.
