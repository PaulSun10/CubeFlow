# FMC, Battle selector and targeted performance closeout

Date: 2026-11-02. Baseline: main at 82b455c39 plus the existing dirty worktree.

## A. Executive Summary

- Restored FMC through one existing native 3x3 random-state request, followed by a constrained representation of that same target. No guessed native index, independent random-state generator, or substitute-puzzle fallback.
- Implemented one panel-owned Battle event selector shared by Head-to-Head and Side-by-Side. Actual selectable content rotates with its owner; opponent timing remains accessible.
- Reduced repeated chart preparation, unnecessary sorting for the latest algorithm attempt, and unused Cards diagram preparation in Battle.
- Removed only unused private Battle plumbing and superseded private chart model declarations.
- Final focused run: 64 unique tests passed, zero failed/skipped. Additional host C++ boundary check: 19/19. Final unsigned generic iOS Debug build passed with the existing iOS 15 deployment target.
- No physical-device interaction, dependency installation, commit, push, release, deployment or upload. Original dirty work is preserved.

## B. FMC Implementation

### Verified requirements and capabilities

Official TNoodle's FMC implementation uses `R' U' F` at both ends. Its constrained middle avoids an F/B-axis first move and R/L-axis last move so the padding cannot cancel or combine across the joins. Its tests also check canonical notation.

Primary references inspected during this pass:

- [Official FMC implementation, pinned source](https://raw.githubusercontent.com/thewca/tnoodle-lib/d01a947d9f028f38085cda9b0507a9cf3d3f38a8/scrambles/src/main/java/org/worldcubeassociation/tnoodle/puzzle/ThreeByThreeCubeFewestMovesPuzzle.java).
- [Official FMC tests, same revision](https://raw.githubusercontent.com/thewca/tnoodle-lib/d01a947d9f028f38085cda9b0507a9cf3d3f38a8/scrambles/src/test/java/org/worldcubeassociation/tnoodle/puzzle/ThreeByThreeCubeFewestMovesTest.java).
- [WCA Regulations 4b](https://www.worldcubeassociation.org/regulations/#4b) and [4b3](https://www.worldcubeassociation.org/regulations/#4b3).

The bundled upstream source archive confirms slot 1 is ordinary 3x3. Slot 11 is another ordinary ThreeByThreeCubePuzzle, not an exposed FMC implementation. None of the previously corrected native indices changed. The native dylib is unchanged; its SHA-256 remains `35ca5611930688d63e6e43b9e2a5d49d6c9dec08ca54a98a136645ce454b4103`.

### Chosen construction

Let the native sampled target be S and padding P = `R' U' F`. Compute C = inverse(P) * S * inverse(P). Use the existing min2phase solver to find an outer-move sequence g reaching C with the verified boundary restrictions. Emit P g P. The complete output therefore reaches exactly S, rather than altering S by mechanically wrapping its original scramble.

`TNoodleScrambler` requests native slot 1 exactly once for FMC, then calls `Min2PhaseBridge.fmcScramble(from:)`. The bridge validates both middle and full states before returning normalized notation. Solved/single-turn or malformed native inputs fail closed. FMC retains its existing event identity, prefetch ownership and saved-solve association.

The existing C++ Search gains an optional per-instance solution filter. Rejected representations do not replace an accepted solution or tighten its length bound. Only FMC installs this filter; ordinary solve callers keep their original policy. This is a constrained representation search, not another random-state generator.

Search is bounded by depth 21, 1,000,000 probes and cooperative 1.5-second interruption after table initialization. Output is at most 27 moves including padding. If a verified representation is not found, return unavailable; do not silently sample another target or return another puzzle. The deadline is cooperative, not a hard real-time guarantee.

### Correctness and limits

Six FMC tests cover exact underlying slot, fixed padding, canonical joins, full-state equality using an independent Swift facelet oracle, difficult short middle states, invalid-input failure, ordinary 3x3 compatibility, prefetch isolation, mounted rapid switching/stale callbacks and saved event/text. A separate host check exercised empty plus all 18 single-move middle states: 19/19 passed.

This restores validated official-style FMC formatting and state preservation for practice. It does not certify CubeFlow as a WCA-approved scramble program or replace the bundled TNoodle version. The simulator tests inject native generation results; they execute the real bridge/search but cannot execute the iOS-only TNoodle dylib. Native generation throughput and rare bounded-search failure rates were not measured on an iPhone.

## C. Battle Event Selector

- `BattleEventSelector` uses existing event definitions, names, Cubing Icons, system typography, regular material, a selected checkmark and native Buttons/ScrollView. All 19 existing selectable events remain in their original order, including the standard/fast 4x4 distinction.
- The selector lives inside the player's panel. Player two's entire panel/content rotates 180 degrees in Head-to-Head; Side-by-Side stays upright. Width/height are bounded to the owner panel, with a scrollable list and selected-row positioning on opening.
- The owner-panel backdrop dismisses and intercepts touches. The other panel remains reachable. Selection never invokes timer readiness/start/stop callbacks.
- Opening and choosing consult an authoritative parent-state permission closure, not a potentially stale rendered Bool. A running or pressed player cannot switch events; an idle opponent may still select.
- Mode changes dismiss the selector. Close, backdrop, repeated reopen, selected state and accessibility escape/selected traits are supported. Owner controls are hidden from accessibility while covered. Handicap semantics and controls are unchanged.

Two tests cover event/rotation policy plus mounted production Timer integration in both modes: choice propagation, independent scramble ownership, repeated dismissal, active-player guard and actual UIKit hit-testing of the two native contact surfaces. Screenshot attachments and PNGs were inspected for real content rotation, containment, scrollability and selected checkmark. These are mounted simulator fixtures, not physical ergonomic or VoiceOver acceptance.

## D. Performance Improvements

| Area | Original inefficiency | Change | Evidence | Risk |
| --- | --- | --- | --- | --- |
| Data trend preparation | Computed getters repeatedly sorted solves, adjusted penalties and rebuilt histogram bins during chart updates | Presentation-owned immutable `SessionSolveTrend`; fresh input constructs a fresh snapshot; no global cache | 2,000 comparable solves, 100 reads, five trials: 100 preparations become one. Before 1250.98-1286.93 ms; after 12.84-13.75 ms in Debug simulator. Numerical/order/bin results match the prior implementation | Low: preserves old penalty, tie-order and bin-edge semantics; changes input preparation ownership only |
| Chart selection lookup | Nearest-point scan/selected-bin search occurred inside every mark closure | Resolve selected point/bin once before constructing the Chart | Structural reduction: N identical selection lookups become one per chart construction. Mark/annotation count, order and appearance unchanged; no device timing claim | Low: same immutable input and selection |
| Algorithms recent practice | Descending sort of every attempt solely to use the first | Strict-newer linear reduction, preserving the first item on timestamp ties | 2,000 records: original sort made 41,521 comparisons; linear implementation needs 1,999 and creates no sorted output array. Empty/tied/varied inputs match old output | Low: JSON decoding and content lookup remain unchanged |
| Battle scramble delivery | Cards-configured users prepared PNG diagrams even though Battle consumes only text | `prepareDiagram: false` for Battle only; default remains true for existing Timer callers | Mounted Cards fixture verifies at least 12 Battle deliveries are consumed synchronously at the raw completion boundary, without waiting for diagram preparation | Low: per-player request/token checks remain intact; solo text/diagram atomic presentation unchanged |

Timings measure this specific repeated-getter workload, not whole-app speed, frame rate or physical-device improvements. No percentages or allocation counts are claimed. The chart snapshot no longer retains unused full solve samples, including their scramble/comment fields; no memory-byte reduction was measured.

## E. Code Cleanup

- Removed unused private `toggleLocalBattleTimer`; reference inspection found only its definition, no dynamic/conditional/test call. Native touch handlers remain the existing entry points.
- Removed unused `reservesExitZone` argument plumbing in Battle; it had no reads. Root exit-button layering and hit targets remain intact.
- Replaced obsolete private `SolvePoint`/`HistogramBin` declarations with the actual snapshot's nested value types; preserved identity rules.
- No broad formatting, renaming, fallback removal, warning suppression or framework extraction. No unrelated warning was changed merely to make the build log quieter.

## F. Findings Not Implemented

- Timer statistics already use owned snapshots; no evidence justified changing timing, precision or high-frequency state handling.
- Smart Cube/virtual cube resources are coordinator-owned; no demonstrated safe hardware-independent renderer/BLE optimization justified touching them.
- Explore already has request pooling, snapshot caching, cancellation and stale-response checks. No duplicate request path was demonstrated; no additional cache was introduced.
- Algorithms history decoding/formatters might benefit from keyed reuse, but input/language invalidation and benefit were not established. Left unchanged.
- CubingChina SSE, advancement and reconciliation remain frozen. No independent performance defect justified refactoring them.
- Existing TNoodle privacy evidence gates and AppIntents metadata warnings are outside scope, not newly resolved or newly introduced here.

## G. Validation

Environment: Xcode 27.2, existing iPhone 17 Pro iOS 26.5 simulator; no runtime/tool downloads. Final device-target build uses arm64-apple-ios15.0. This proves compilation at the minimum target, not execution on an iOS 15 runtime.

Final selected test run:

| Suite | Passed |
| --- | ---: |
| FMCScrambleTests (new) | 6 |
| BattleEventSelectorTests (new) | 2 |
| FocusedPerformanceTests (new) | 5 |
| ScrambleNativeMappingTests (updated FMC expectation) | 6 |
| SmartCubeSolverAuditTests | 5 |
| LocalBattleReliabilityTests | 5 |
| ReliabilityPresentationTests | 4 |
| TimerScrambleLifecycleRegressionTests | 8 |
| TimerScramblePositionTests | 3 |
| WCAOfficialParticipationTests | 3 |
| CubingChinaLiveProgressTests | 10 |
| TimerScramblePrefetchTests (Swift Testing) | 7 |
| **Unique total** | **64** |

- Final result: 57 XCTest + 7 Swift Testing, 0 failed, 0 skipped. Thirteen tests are new. Reruns are not counted as additional unique tests.
- Separate host-native check: 19/19 production bridge/search boundary fixtures; not a second iOS test suite and not execution of the native TNoodle dylib.
- Early targeted attempts failed selector guard/transition assertions and a stale-request fixture selection. The authoritative permission guard and fixture lifecycle were corrected. Final reruns pass; earlier failures are not counted as passing evidence. Initial standalone host-probe link/include setup errors were corrected before its successful run.
- Unsigned generic iOS Debug builds passed, including the final source after chart-selection lookup hoisting. No signing/provisioning changes. No Release build was needed.
- Existing TNoodle required-reason privacy warnings and skipped AppIntents metadata extraction remain. Simulator WebKit process-assertion messages and an internal QoS warning occurred during mounted tests, without test failure; no speculative workaround was added.
- `git diff --check`: passed. Baseline hash comparison: exactly 15 expected existing files changed, no missing baseline files, no unexpected modifications. Frozen source groups and prior reports remain unchanged.

Reproducibility: selected tests ran with `xcodebuild test`, scheme CubeFlow, Debug, simulator ID `24E6D520-DF19-4F61-89DB-55F2F418484E`, the twelve suites above, parallel testing disabled, and signing disabled. Final build used `xcodebuild build -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug -destination 'generic/platform=iOS' -skipPackageUpdates CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=`. Both used the existing DerivedData and `DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer`.

Ignored evidence directory: `/Users/paulsun/Desktop/Projects/CubeFlow/build/fmc-battle-performance-nov02/`. Final evidence: `complete.log`, `complete.xcresult`, `debug-build-final.log`, `native-fmc-check.log`, `selector-headToHead.png`, `selector-sideBySide.png`. Initial status, binary diff and SHA-256 baseline are retained there. No test/build process or booted simulator remained at closeout.

## H. Worktree and Files

This pass modified 15 baseline files, including two that were already untracked. It added six files including this report. No file was deleted. Final repository state is intentionally dirty: 43 tracked modified paths and 31 untracked paths, including all prior work. `project.pbxproj` is unchanged. No changes outside the iOS project were made.

Modified relative to this task's baseline:

- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Min2PhaseBridge.h`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Min2PhaseBridge.mm`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Vendor/min2phaseCXX/src/Search.h`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Vendor/min2phaseCXX/src/Search.cpp`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/TNoodleScrambler.swift`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/TimerLocalBattleView.swift`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/TimerTabView.swift`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/LocalBattleTestProbe.swift` (pre-existing untracked)
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/DataTabView.swift`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/AlgTabView.swift`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/Algs/AlgSupport.swift`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/en.lproj/Localizable.strings`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/zh-Hans.lproj/Localizable.strings`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/zh-Hant.lproj/Localizable.strings`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/ScrambleNativeMappingTests.swift` (pre-existing untracked)

Added:

- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/BattleEventSelector.swift`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/SessionSolveTrend.swift`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/FMCScrambleTests.swift`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/BattleEventSelectorTests.swift`
- `/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/FocusedPerformanceTests.swift`
- `/Users/paulsun/Desktop/Projects/CubeFlow/docs/fmc-battle-performance-nov02.md`

Confetti is untouched. Timer timekeeping, inspection, penalties, gestures, haptic timing, animations and PR behavior are preserved. Previously accepted Battle ownership/touch fixes, Cards atomicity, CubingChina Live and corrected native mappings remain. WCA OAuth, Smart Cube Guidance/BLE, backend, privacy manifests and signing were not modified. Shared default solver behavior has focused regression coverage; its only new opt-in behavior is FMC's solution filter.

## I. Remaining Manual Verification

Later, when a device is available:

1. Generate several FMC scrambles through the actual iOS native framework; inspect fixed ends, rapid FMC/3x3 switching and saved event/text. Observe cold/warm generation latency and any reported bounded-search failures.
2. In both Battle layouts, check the opponent-facing selector, repeated open/choose/dismiss, long-list scrolling, smallest supported phone/Dynamic Type and that only the owner panel is blocked. Check VoiceOver focus/escape and selected-row announcement.
3. Confirm subjective selector ergonomics while the other player starts/stops independently. Automated simulator hit-testing is not a claim of physical touch acceptance.

No physical testing is requested or required to proceed with this completed local implementation pass.
