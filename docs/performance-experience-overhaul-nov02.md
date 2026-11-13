# Performance and Experience Overhaul - 2026-11-02

## Delivery Status

Implemented the bounded startup, cache-first loading, Manual Input, optional Inline Keypad, algorithm-search, and adaptive-layout changes described below. Preserved the pre-existing dirty worktree. No commit, push, release, deployment, upload, physical-device operation, or dependency installation was performed.

Verification is **not fully green**: the latest result for each of 157 distinct focused tests is 155 passed, 2 failed, 0 skipped. Both remaining failures concern a mounted simulator cache-test scroll-position precondition, not a demonstrated localization-response displacement. They remain unresolved and were not removed, skipped, or relaxed. The final unsigned generic iOS Debug build passed.

The user's approximately four-second launch-to-usable observation has not been remeasured on hardware. This report does not claim that it is eliminated or that physical scrolling is accepted.

## 1. Startup and First Scramble

- Removed the duplicate initial Timer statistics refresh: initial session synchronization suppresses its refresh, the foreground scramble is requested, then the existing explicit refresh runs once. Other legitimate refresh paths remain unchanged.
- Added a single-use launch reservation for exactly the persisted visible session/event. It starts the existing generation pipeline while SwiftUI mounts. The first matching foreground demand joins or consumes that request rather than initiating another one.
- Reservation validity includes the complete generation context. A mismatch invalidates it; a late completion cannot activate another session/event. It is never reused for Next or prefetch. Background launches, absent/invalid persisted sessions, Multi-Blind, and Smart Cube/Combined do not use this reservation.
- Kept native generation serialized and existing prefetch ownership. No all-events preloading, TNoodle solver/RNG changes, or Smart Cube restoration changes.
- Moved secondary FTO prewarming behind successful first-scramble activation instead of competing unconditionally with the initial visible puzzle. An actual FTO request still initializes its own existing pool immediately.
- Cached the 11 immutable diagram JavaScript sources and their JSON encoding once per process. Per-render puzzle, scramble, color, and stroke values remain request-specific. Warming uses the existing generation queue.

Remaining startup costs include synchronous Core Data persistent-store initialization, native runtime/first-puzzle initialization, and first WebKit process creation. The project uses Core Data, not SwiftData. Their actual device critical-path durations remain unmeasured; no persistence migration or native-runtime rewrite was attempted.

### Opt-in Instrumentation

DEBUG environment variable `CUBEFLOW_EXPERIENCE_TRACE=1` enables allowlisted `Experience` signposts: persistence begin/ready, root appearance, Timer initialization, visible-scramble request/ready/unavailable, and tab selection. A bounded first-frame probe observes 180 active display-link samples and reports gaps over 100 ms; dismantling invalidates its display link.

Times are relative to persistence instrumentation initialization, **not** an OS process-launch timestamp. Display-link gaps alone do not attribute a stall to a particular function. This is disabled by default and records no OAuth material or user input. No numerical cold/warm startup, tab-latency, or physical-device improvement is claimed from this instrumentation alone.

## 2. Competition Cache Delivery

The previous cached-list path awaited optional Chinese-name enrichment before presenting rows. That allowed an optional network request to gate useful cached content.

The final conservative lifecycle is:

1. Read already-stored localized names without starting or joining a network request.
2. Publish usable canonical/cached rows immediately, retaining the existing freshness, pagination, and provenance policy.
3. Warm optional localized names in a separate identity-bound task and persist them through the existing name store.
4. Do **not** republish active rows when that optional task finishes. A subsequent normal presentation can adopt the warmed names before native rows mount.
5. For runtime snapshots, compare the actual localized fields before the initial mount rather than relying on the model's ID-based equality. Preserve pagination, counts, and Top Cubers state when preparing that snapshot.

Cancellation, query signature, request identity, and source revision guard stale work. Existing stale-cache revalidation and explicit refresh remain authoritative. No live-result freshness policy changed. Runtime restoration now uses the same prepared-item publication helper as ordinary restoration.

Stable-ID/reconfiguration experiments did not establish a solution to the simulator offset behavior and were reverted. The existing content-hash-based native IDs, self-sizing, snapshot scheduling, idle/deceleration gates, scrolling physics, and offset handling remain. No offset compensation was introduced.

### Independently Proven Teardown Bug

Mounted tests exposed a diffable cell-provider lifetime failure: its weak coordinator reference could disappear while UIKit still requested a cell, returning nil and causing an assertion. The provider now retains its coordinator while active. `dismantleUIView` explicitly cancels refresh work, disconnects delegate/data source and refresh targets, unregisters scrolling, and releases the data source to break the ownership cycle. Post-dismantle work is guarded. This is lifetime cleanup, not a scrolling/layout redesign. Subsequent focused runs did not reproduce that crash.

### Cache Evidence and Limitation

The latest cache run passed 13/15 tests, including canonical rows mounted while enrichment remained suspended, no active name-only republishing, stable native IDs in the successful enrichment case, persistence across name-store recreation, warmed-name adoption by a subsequent mounted browser, freshness/revalidation, and stale-response protection.

Two tests fail at the strict list-interior precondition, before releasing the suspended localization response:

- `testActualBrowserKeepsCachedRowsWhenOptionalLocalizationFails`
- `testActualBrowserRejectsLateCachedLocalizationAcrossFilterABA`

At `CompetitionBrowserCacheTests.swift:487`, the mounted collection reports offset -116 pt, its top boundary, rather than an interior position greater than -115 pt after a programmatic scroll. A bounded test-only display-link settlement helper did not resolve it. Thus those runs cannot establish the intended before/after interior-scroll comparison. This is not evidence that name enrichment caused the clamp, nor proof of an OS defect. The underlying fixture/native-layout interaction remains unknown. Assertions are retained; the safe production approach was not replaced with a speculative list rewrite.

## 3. Manual Input

One shared parser/draft/save path serves Default Keyboard and Inline Keypad.

### Fixed

All nine formats are supported: `X`, `X.XX`, `X.XXX`, `X:XX`, `X:XX.XX`, `X:XX.XXX`, `X:XX:XX`, `X:XX:XX.XX`, `X:XX:XX.XXX`.

Unseparated digits are grouped from the right; lower time fields are base 60 and reject overflow rather than normalizing into another format. The leading field is bounded to nine digits and raw input to 18 characters. Explicit `.` and `:` override automatic grouping in both modes, retain supported explicit precision, and reject incomplete/invalid saves. Default Keyboard + Fixed `X` preserves the existing ordinary seconds workflow; there is no third interpretation mode.

### Smart

- Up to three unseparated digits use hundredths: `921 -> 9.21`.
- Longer input produces valid hundredths/thousandths candidates, with minute/hour grouping where applicable: `3512 -> 35.12 / 3.512`, `9210 -> 92.10 / 9.210`, `110013 -> 11:00.13 / 1:10.013`.
- Uses the median of the latest 20 usable current-event/current-session solves; if none exist, uses same-event historical solves. DNF/nonfinite/invalid samples are excluded and +2 uses adjusted time. A single valid solve can supply context.
- Relative-distance ranking is deterministic. Insufficient history or a near tie uses the configured Hundredths/Milliseconds preference. No network/AI dependency.
- Immediate alternative selection persists while editing; raw input is retained. Clearing resets the override. The displayed candidate is the saved value, and saved solves are never reinterpreted.
- Save captures the immutable current scramble assignment, requires persistence success, consumes that assignment once, clears the draft, and advances normally. Reentrant duplicate saves are guarded. Existing PR/Confetti behavior is preserved.

The four settings use existing AppStorage conventions and English, Simplified Chinese, and Traditional Chinese localization.

## 4. Inline Keypad, Layout, and Accessibility

- One optional keypad component is shared across Cards, Split, and Classic; Default Keyboard remains available and uses the same parser/save logic.
- Native interactive Glass where available, iOS 15 material fallback, immediate press feedback, reusable selection haptic generator, and at least 44-point targets.
- Decimal/minute separators, raw input, interpreted preview, immediate candidate switching, Clear, and Save.
- Backspace deletes immediately and repeats after a hold; release, cancellation, drag exit, and removal cancel repeat work.
- VoiceOver labels/values/actions and Reduce Motion-aware press feedback.
- Cards/Split use their allocated central region without feeding keypad height into ordinary scramble exclusion geometry. Classic retains a compact presentation and existing surrounding statistics.
- Mounted tests caught clipped raw input and an unreachable Save control. Direct intrinsic-height observation and allocated-header layout math corrected those issues. Final mounted 393 x 852 tests verify both raw input and Save inside the viewport for all three arrangements.
- Additional fitting tests cover 320/768-point containers with accessibility Dynamic Type. These are not a complete short-landscape/resizable-window physical acceptance test.

Simulator fixture screenshots were inspected for Classic, Split, and Cards. They show raw input, preview, keypad, and Save reachable in the tested portrait viewport. They do not establish physical press/haptic quality or every keyboard/window configuration.

## 5. Data, Algorithms, Explore, and Chat

- Algorithm searchable text is normalized once; matching entries are partitioned in one pass per query instead of repeated full scans for each result category. Existing notation/data, Unicode search, stable result identity, and empty-state behavior are retained.
- After first activation, Algorithms retains its native navigation subtree through inactive/reactivated tabs. A mounted test verifies the same navigation controller survives. It is not eagerly mounted before first use.
- Data trend and algorithm-search reading widths are bounded at 960 points on wider containers without changing compact iPhone presentation. Earlier chart/snapshot optimizations in the dirty tree were preserved, not counted as newly implemented work.
- Explore starts independent global-record loading before awaiting optional person-region data. Record provenance and correctness-sensitive Live logic are unchanged.
- Data's existing native filter Menu was retained; no demonstrated defect justified replacing it.
- The CubingChina chat Tab-accessory prototype produced an unwanted full-width Glass container and was removed. The original floating button remains. Public accessory placement APIs did not establish the requested independently floating circle synchronized to native minimization in this pass. No private hierarchy introspection or scroll approximation was shipped.
- This is an adaptive foundation, not a full iPad app port. Existing iPad availability/navigation limitations remain.

## 6. Measured Versus Expected Performance

| Workload | Before | After | Evidence boundary |
| --- | --- | --- | --- |
| Algorithm search, 2,000 items, 20 queries, 3 Debug simulator trials | 262.68 / 262.63 / 258.62 ms | 48.15 / 47.05 / 45.78 ms | Comparable local microbenchmark; not physical UI latency/FPS |
| Immutable diagram-source preparation | 11 file reads/JSON encodings per render | Once per process; shared thereafter | Source/lifecycle assertions; no render-ms benchmark |
| Explicit initial Timer statistics refreshes | 2 in the initialization path | 1, after foreground scramble request | Code-path reduction; not one refresh across the whole process |
| Optional localization network gate | Cached rows awaited optional enrichment | Cached rows mount with enrichment suspended | Mounted deterministic fixture; no claimed device-ms reduction |
| First foreground scramble scheduling | Waited for Timer mounting/initialization | One matching persisted-event reservation overlaps mounting | Ownership tests; native first-puzzle device duration unmeasured |

No synthetic number is substituted for the user's cold-launch observation. Simulator native-runtime limitations and test generation fixtures prevent a representative device TNoodle launch comparison.

## 7. Verification

Used Xcode 27.2 at `/Applications/Xcode-27.2.app/Contents/Developer`, existing iPhone 17 Pro simulator with iOS 26.5, and existing DerivedData. No runtime/software installation. The simulator is shut down and no xcodebuild/xctest process remains.

### Test Results

The latest result per distinct test across the focused full run and targeted reruns is:

- XCTest: **115 passed / 2 failed / 0 skipped**, 117 distinct cases.
- Swift Testing: **40 passed / 0 failed**, across Algorithm Presentation, Explore Composition, and Timer Scramble Prefetch.
- Combined: **155 passed / 2 failed / 0 skipped**, 157 distinct tests. This is an aggregate across runs, not a single all-green final run.

XCTest coverage includes Manual Input (7), mounted Manual Entry lifecycle (3), launch reservation (4), diagram resources (2), algorithm search/navigation (3), cache delivery (15), snapshot cache (14), Top Cubers sizing/animation/packing (15), Timer scramble lifecycle (8), position (3), FMC/native mapping (12), Battle reliability/selector (7), Live progress (10), existing performance (5), presentation reliability (4), and solver audit (5).

The final broad focused run had 116/117 XCTest passing plus 40 Swift Testing passing. The continuation cohort reran 59 XCTest cases; 44 non-cache cases passed, while five cache assertions still expected an experimental ID format. Those expectations were corrected to the preserved content-hash format without removing full-ID equality or offset checks. The final cache rerun was 13/15 as detailed above. No failed test was silently excluded from this report.

Other failures encountered and corrected during development included JSON-escaped resource assertions, keypad viewport geometry, and the sizing test fixture's disabled master diagnostics gate. Top Cubers sizing production logic was not changed to satisfy that fixture. The rejected chat prototype and unsuccessful native identity experiments are not part of the delivery.

Test invocations use `xcodebuild test -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug`, the existing simulator destination, explicit `-only-testing` suites, no parallel testing, bounded test timeouts, `-skipPackageUpdates`, and disabled signing. Exact commands and output are retained in:

```text
/Users/paulsun/Desktop/Projects/CubeFlow/build/experience-overhaul-nov02/final.log
/Users/paulsun/Desktop/Projects/CubeFlow/build/experience-overhaul-nov02/resume-closeout.log
/Users/paulsun/Desktop/Projects/CubeFlow/build/experience-overhaul-nov02/cache-delivery.log
```

Matching xcresult bundles are in the same ignored evidence directory.

### Build and Static Validation

Final-source unsigned generic iOS Debug build: **PASS**, arm64, iOS 15.0 deployment target. Three incremental generic Debug builds passed during this implementation/continuation; the last covers the final runtime-cache publication correction.

```sh
DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer xcodebuild build \
  -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug \
  -destination generic/platform=iOS \
  -derivedDataPath build/competition-navigation-loading/DerivedData \
  -skipPackageUpdates CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
```

Final output: `/Users/paulsun/Desktop/Projects/CubeFlow/build/experience-overhaul-nov02/debug-build-delivery.log`.

`git diff --check`: PASS. All three changed Localizable.strings files pass `plutil -lint`.

Existing build warnings remain: the TNoodle privacy-review evidence gate, AppIntents metadata extraction without an AppIntents dependency, and the existing always-run TNoodle signing phase. This task did not resolve or change those unrelated gates. There was no signed device/archive/Release validation in this pass.

## 8. Files and Worktree Safety

Baseline: branch `main`, HEAD `82b455c39`, 43 modified tracked files and 31 untracked files. Hash comparison against the task baseline identifies 20 baseline files changed by this task, 10 new files including this report, and **zero baseline files deleted**. Final status: 49 modified tracked files and 41 untracked files, including earlier unrelated work. Nothing staged, reverted, cleaned, committed, or pushed by this task.

### Changed Baseline Files

```text
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/CubeFlowApp.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Models/PersistenceController.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/CompetitionService.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/ScrambleDiagramView.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/AlgTabView.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/Algs/AlgSupport.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/Algs/AlgTrainerAndSearchViews.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/CompetitionTabView.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/DataTabView.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/Explore/ExploreView.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/IPhoneContentView.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/SettingsTabView.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/TimerScramblePipeline.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/TimerTabView.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/en.lproj/Localizable.strings
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/zh-Hans.lproj/Localizable.strings
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/zh-Hant.lproj/Localizable.strings
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/BattleEventSelectorTests.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/CompetitionBrowserCacheTests.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/CompetitionTopCubersSizingTests.swift
```

### New Files

```text
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/AppExperienceTrace.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/ManualTimeInput.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/ManualTimeEntry.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/TimerLaunchScrambleReservation.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/AlgSearchPerformanceTests.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/DiagramScriptCacheTests.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/ManualTimeEntryLifecycleTests.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/ManualTimeInputTests.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/TimerLaunchReservationTests.swift
/Users/paulsun/Desktop/Projects/CubeFlow/docs/performance-experience-overhaul-nov02.md
```

Confetti, project.pbxproj, OAuth, Smart Cube/BLE/Guidance, TNoodle internals/binaries, and correctness-sensitive CubingChina SSE/progression files are unchanged from this task's starting state. Their pre-existing Git differences remain preserved. Original cache self-sizing/Interactive Glass/disclosure behavior was not replaced. Ignored logs, xcresults, baseline hashes, and inspected simulator screenshots remain under the evidence directory; they are not proposed source commits.

## 9. Deferred and Physical Acceptance

1. Compare cold and warm launch on the same device/event/session; observe first usable Timer, first valid scramble/diagram, rapid Next, and foreground restoration. Use the opt-in signposts to separate persistence, generation, and first-render costs. Startup improvement is expected structurally, not yet proven as a device duration.
2. With a populated competition cache and slow/offline optional localization, open both List and Glass, scroll through deceleration, switch filters, refresh, and return. Current rows must remain stable; warmed names should appear on the next normal load, not rewrite the active list. Confirm Top Cubers/Glass/disclosure behavior remains accepted. The two mounted-test interior-position failures still require follow-up evidence.
3. In each Timer arrangement, test Default Keyboard and Inline Keypad with all nine formats, Smart examples, current-session/same-event history, DNF/+2, explicit separators, override/edit/delete/hold, and rapid Save. Confirm the saved value and scramble match the displayed assignment exactly once.
4. Test keypad reachability at large Dynamic Type, small/short windows, VoiceOver, Reduce Motion, and older-iOS material fallback. The tested portrait fixtures do not cover every physical layout.
5. Switch Algorithms away/back after navigating/searching; verify retained state and query responsiveness. Check wider Data/Algorithms reading widths and ordinary iPhone layout.
6. Confirm the original CubingChina floating chat remains usable. Exact native-minimized-bar synchronization and a full iPad experience remain deferred; no inferior accessory prototype was retained.

No physical acceptance action was performed automatically.
