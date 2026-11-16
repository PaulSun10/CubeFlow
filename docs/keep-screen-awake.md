# Keep Screen Awake

The native switch is in **Settings > Timer**. Its footer explains that it prevents automatic locking while using Timer or Battle. It shares the existing `@AppStorage` / UserDefaults architecture. A missing value means on, with no migration; an explicit off survives relaunch.

The row shows a blue NEW badge through bug-fix, maintenance and performance updates. The developer will remove it when replacing the previous NEW placements with the next feature batch. See [Feature Badge V1](feature-badges.md); the badge does not affect the switch or its preference.

## Ownership and lifecycle

The iPhone scene root contributes only when its selected tab is Timer and its scene phase is active. Layouts, input methods, timing phases and Battle rounds do not control the idle timer. Presenting a Timer-owned sheet does not unregister the scene; the registration belongs to the mounted root.

One MainActor coordinator reconciles those registrations against the saved preference and owns all writes to `UIApplication.shared.isIdleTimerDisabled`. Normal auto-lock returns when the preference is off or no active Timer scene remains. An inactive, backgrounded, removed or non-Timer scene does not keep the display awake or cancel another eligible scene. Exiting Battle into the visible Timer retains Timer's eligibility; exiting to another experience releases it. Marketing previews, the iPad placeholder and Mac are not wired. Nothing changes brightness, the system auto-lock preference, or the ability to lock manually.

## Localization

Both strings are present in all 19 languages listed by `appLanguageOptions()`. Xcode's 20th known region is Base, not a separately translated or selectable app language.

## Changed files

- `CubeFlow/CubeFlowApp.swift`, `CubeFlow/Views/iPhone/IPhoneContentView.swift`, and `CubeFlow/Views/iPhone/ScreenAwakePolicy.swift`: iPhone scene wiring and idle-timer owner.
- `CubeFlow/Views/iPhone/SettingsTabView.swift` and the 19 `Localizable.strings` catalogs: native toggle and footer.
- `CubeFlowTests/ScreenAwakeTests.swift`: default and preference persistence, overlapping registrations, stale updates, and the mounted iPhone-root lifecycle.
- `ROADMAP.md` and this closeout. No changes to Timer/Battle behavior or WCA recovery.

## Verification

101 selected tests passed on the iPhone 17 Pro simulator running iOS 26.5 with Xcode 27.2: 3 screen-awake, 10 Battle, 8 Timer scramble lifecycle, and 80 WCA coordinator tests. The screen-awake tests verify app requests via an injected writer, using the actual mounted iPhone root and simulated scene transitions for the integration case. They do not measure physical auto-lock. See `build/screen-awake/verified.log` and `verified.xcresult`.

All 19 string catalogs passed `plutil -lint` and contain both keys. `git diff --check` passed.

The unsigned generic iOS Debug build passed with the iOS 27.2 SDK, iOS 15.0 deployment target and no Broker mock flag. See `build/screen-awake/device-debug.log`. No iOS 15 runtime or physical-device auto-lock test was run.

## Physical acceptance

No new issue was reported in v0.16.1 feedback. A completed physical verification matrix was not reported.

1. With a finite system Auto-Lock interval, leave Timer idle past that interval in Cards and Classic. Check both Battle layouts, including waiting between rounds and a mixed-input match.
2. Switch to another tab or turn the setting off and confirm normal auto-lock resumes. Background and foreground the app on Timer and on another tab. Confirm manual locking still works, and relaunch with the switch off to confirm persistence.
