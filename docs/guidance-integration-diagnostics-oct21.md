# Guidance Integration, Discoverable Capture, and Management Follow-Up

## Status

The physical 15-20-additional-turn Guidance failure is **not established as fixed**. The user installed the latest source through Xcode; an outdated installation is not an explanation. This pass does not change solver budgets, settle timing, protocol mappings, target semantics, trust guards, or adoption policy to manufacture a green result.

Confirmed corrections are the discoverability/ownership of Guidance capture and the management card's native button treatment. A new regression exercises the actual mounted Timer and actual session-to-active-device routing, rather than another implementation of Timer logic in a harness. It does not reproduce missing current-state updates with the supplied synthetic canonical turns. Physical BLE-to-screen evidence remains necessary to identify the persistent failure's owner.

## Production Guidance Path Inspected

1. `SmartCubePeripheralSession.handleStateData`: receipt, serial parser queue, decrypt/parse, generation-guarded main-thread application. Each decoded move is handled independently. The first-16/every-25 verbose sampling gates logging, not event processing.
2. `enqueueMove`/`emitMove`: optional existing 260 ms slice-pair coalescing, committed canonical facelets, then ordered feed publication. History retention is 120 events, not a 15-20-turn release threshold.
3. `SmartCubeBluetoothManager.makeSession` and `SmartCubeActiveFeedRouter`: the real per-session Combine subscriptions forward only the selected connected device into the stable, monotonically sequenced active feed. No new batching policy is introduced.
4. `TimerTabView.consumeSmartCubeEvent`/`handleSmartCubeMove`/`handleSmartCubeFacelets`: epoch sequence, timestamp, trust and timing-lifecycle checks; progress matching; immediate guaranteed/advanced recovery presentation; original-target request scheduling. The snapshot duplicate guard and current-request identity checks were inspected separately from the solver.
5. `SmartCubeGuidanceController`: latest-request ownership and cancellation, exact-short lane, settled native lane, replay-verified known-path comparison. An equally good verified continuation intentionally need not produce a replacement publication. A quiet continuation is not itself stale guidance.
6. `applySmartCubeGuidance`: drain ordered updates before adoption; match current device, exact source, original target, epoch/revision, generation, trust and eligible lifecycle; replay verification is retained. No target rotation, solve-to-solved shortcut or connectivity-only eligibility is added.
7. `SmartCubeScrambleProgressView`: actual progress tokens, completion state and both active/fallback recovery plans. Source/target and displayed-path digests now accompany the SwiftUI update boundary, including whether that route replays from the current source to the exact target. This is not a GPU-present callback.

The 21-move bound limits candidate route length; it does not wait for 21 received turns. No demonstrated 15-20-input buffering threshold was found in these paths. This does not rule out a hardware/protocol-specific ingestion problem or another physical-only lifecycle condition.

## Actual Timer Regression and Its Limits

The new test mounts `TimerTabView`, seeds a connected/trusted session, and uses the **production** `makeSession` subscriptions, session `emitMove`, active router, canonical feed, Timer handlers, real controller/planner and renderer. DEBUG probe closures only prepare a fixed original scramble and read the mounted Timer's actual state. They do not reimplement guidance/adoption.

It follows eight original moves, performs six short deviation/inverse turns with pauses, then sends twenty turns without a run-loop pause. All 34 canonical moves reach Timer. Displayed paths replay to the unchanged original target after each checked state, including each burst turn. After the final turn, native search adopts a verified 16-move route without another physical input. The exported trace distinguishes nine valid continuation reuses from one accepted replacement. These are simulator fixtures, not measured physical BLE latency.

The initial version of this fixture failed because a startup asynchronous scramble request was still allowed to replace the test-injected target. The DEBUG preparation seam now invalidates that fixture's pending generation/prefetch before setting its fixed scramble. That test-isolation correction is **not** presented as a proven production root cause. The simulator's initial unsupported-radio callback also completes before its synthetic session is seeded.

The seed bypasses BLE, encryption and protocol parsing. The 47 passing regressions therefore cannot resolve a device-only input failure. Likewise, an intermediate SwiftUI update may refer to a previous view value while multiple canonical states arrive in one render transaction. Diagnose a stationary failure against the last source/sequence after input stops, not one intermediate `valid=false` row in isolation.

## Discoverable DEBUG Capture

Previously, Copy Guidance Diagnostics was inside `SmartCubeLabView.statusSection`, conditional on both a connected active cube and Debug Mode, below the saved-device rows. It was not on the saved device's detail page, and Development had no Guidance link. Timer's compact connected-device action can open the management card instead of the lab. Protocol Debug also owned the recorder's enable flag. The previous report's path was too ambiguous and setup-dependent; it did not establish that the user could find an export in that device-details hierarchy.

New direct path: **Settings > Development > Guidance Capture**. A second link exists in the Smart Cube lab. Both compile only in DEBUG. The Development link does not require Debug Mode, Protocol Debug, a particular puzzle, or a connected peripheral. The separate process-owned recording flag survives Settings/Timer tab navigation and is not reset when Protocol Debug changes. No polling timer or background task is introduced. Force-quitting still discards the in-memory evidence.

Evidence additions:

- Fixed-key scalar counts for BLE receipt, parser begin/end, main application, decoded moves, canonical publication and Timer consumption, counted since Clear Guidance Capture.
- Decoded move timestamps linking packet receipt, parser-queue wait and parser execution, without raw packets/facelets.
- Active-device routing acceptance, linked by shortened move ID.
- Exact displayed-path validity, cost and digest, plus consumed sequence, source/target digests and existing epoch/generation/adoption checks.
- Explicit capture start/stop, retained counts and copy confirmation accessibility value.
- Shortened coalescing parent IDs, replacing full UUIDs in that diagnostic detail.

Both existing rings remain bounded at 2,048 entries. Export is bounded to one scalar-count header plus the last 2,047 Guidance entries; gyro packet rows cannot evict those Guidance rows. No full device identifier, raw facelet state, original scramble text, device name or solve history is added. The normal Protocol Debug path still works independently; if it remains enabled it can continue its existing diagnostics after dedicated capture is stopped.

## Management Card

The actual reference is `SessionManagementToolbarConfigurator` in `DataTabView`: a UIKit `UIBarButtonItem`, `.prominent` on iOS 26+, `.done` earlier, with `.systemBlue` tint. Its existing configuration is extracted unchanged into `SessionNativeActionStyle` and is still called by Session Edit/Done.

The rejected card used `.glass(.regular.tint(tint.opacity(0.2)))` plus colored foreground overrides; that was not the reference. It is removed. A prototype using actual toolbar bar items reproduced the reference coloration, but UIKit kept the visible buttons content-sized despite setting the item's public width. Its snapshot failed the full-width visual requirement, so it is not the final implementation.

For the required full-width content controls, the shared policy uses UIKit's corresponding native `UIButton.Configuration.prominentGlass()` with system blue/red tint, and `.glass()` for neutral Disconnect. This is a native content-button adaptation of the toolbar reference, **not** a claim that a UIButton and a toolbar UIBarButtonItem are the same object or have identical context metrics. Apple's [prominentGlass documentation](https://developer.apple.com/documentation/UIKit/UIButton/Configuration-swift.struct/prominentGlass%28%29) describes this native prominent Liquid Glass configuration. Earlier supported OS versions use native bordered configurations. No custom Glass effect, background fill, opacity or foreground override is involved.

Mounted Light/Dark screenshots were inspected. Reset occupies the full 317 pt content width in the 361 pt fixture; Disconnect/Forget have equal actual bounds and a 12 pt gap. Reset is blue, Forget red, Disconnect adaptive neutral. The existing per-device callbacks and destructive confirmation remain. The native UIKit controls keep a stable coordinator and invoke the current action closures.

Battery becomes **20 pt regular monospaced digits**, centered in the identity row. Device name stays on the unchanged **24 pt bold WCA Results title modifier**, including the existing close-control reserve. WCA Results styling itself is not modified.

## Filter

The physically accepted stable presentation-owner root is unchanged. So are native popover animation, pending-reopen acknowledgement, filter/date semantics and Browser scrolling.

New analysis of the existing complete Browser trace, rather than another independent presenter comparison, separates the intervals across twelve intentional dismissals on iOS 26.5:

| Interval | Observed range |
| --- | --- |
| Close request to native will-disappear | 4.74-54.98 ms |
| Native will-disappear to transition completion | 794.92-925.34 ms |
| Transition completion to dismissal-finished acknowledgement | 0.019-0.269 ms |
| Acknowledgement to reopen intent, 11 applicable cases | 0.027-17.42 ms |
| Acknowledgement to native presentation binding, 11 applicable cases | 2.26-34.54 ms |

The measured long interval is before native completion; no comparable application-controlled delay after acknowledgement was found. These callbacks do not prove the first invisible compositor frame, nor prove an OS-only defect. Bypassing completion would risk the detached-preview crash already fixed. No safe production latency correction was demonstrated; the stable implementation remains. Physical iOS 27.2 latency remains unresolved.

## Verification

- `regression-v7.xcresult`: **47 XCTest passed**, zero failures/skips. Includes actual Timer integration, latest/current-state Guidance, lifecycle, diagnostic privacy/retention, native management rendering/actions/ownership and actual Browser Filter lifecycle regression.
- `navigation-explicit-v12.xcresult`: **one real Settings/Timer UI acceptance test passed**, zero failures/skips, on iOS 26.5. Debug Mode is off and no peripheral is connected; the test opens the actual Development link, starts recording, switches to Timer and back, stops recording, verifies retained count/copy enablement, taps Copy and checks the action's confirmation value. Final screenshot: `navigation-verified-images/BA37E7F6-8C69-4C53-B117-517356B4113F.png`.
- The **one final unsigned generic iOS Debug build passed**, exit 0. Command: `xcodebuild -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/competition-navigation-loading/DerivedData -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build`. Evidence: `final-unsigned-debug.log` / `.exit`. The remaining warning is skipped AppIntents metadata extraction without an AppIntents.framework dependency; the existing TNoodle script note is unchanged.
- Pre/postbuild production-source SHA-256 verification passed. Final `git diff --check` passed.

Earlier attempts are retained, not counted as passing: missing explicit Combine/CoreData imports were fixed; a cross-process UI-test pasteboard read was interrupted at the simulator's system paste permission prompt; the discarded toolbar prototype caused a UIKit layout-observation loop; the first fixed-target Timer fixture allowed an unrelated in-flight startup request to overwrite it; a configuration-object equality assertion compared UIKit-resolved objects rather than the relevant style fields. Final regression uses actual button bounds and relevant configuration fields, not that equality assertion. No generic iOS build was used for these focused-test iterations.

The navigation reruns also exposed a stale simulator test-bundle resolution: a process sample showed loaded XCTest UUID `B94E33E5-E65C-373B-9B36-6C2956B91CF1` from a container-manager `Dead/temp` path, whereas the current built and installed bundle had UUID `5638BB1F-883C-3A86-9860-6E36B3BC8B6E`. That process still executed the removed pasteboard-read assertion. One renamed-case run reported success with **zero tests**, which is explicitly not counted. An iOS 27.1 attempt stalled during app launch and was stopped. A fresh focused `build-for-testing` and a simulator-only `.xctestrun` with an explicit current host-filesystem `TestBundlePath` eliminated the old-container resolution. The final result independently confirms the new class/method actually executed exactly once and passed. No simulator was erased, app data/cache deleted, or physical-device installation blamed. A post-test clipboard CLI read was unavailable because Xcode had already shut the simulator down; the UI action confirmation and retained export-format tests, not that unsuccessful CLI read, are the copy/export verification evidence.

Final passing union: **48 distinct tests** (47 XCTest subsystem regressions plus one XCUITest), not a sum of reruns. The final UI case is `GuidanceCaptureSettingsAcceptanceTests.testDevelopmentCaptureRetainsStoppedRecordingAcrossSettingsAndTimerTabs`. Existing framework QoS/SceneKit warnings are not represented as application lifecycle failures or silently fixed outside scope.

Preservation audit against the task's initial dirty-tree hashes: 7,559 unchanged source/support files, ten scoped modified existing files, six scoped additions listed below, zero missing files. Ignored Finder metadata was not part of the Git-visible baseline and is excluded from the addition count. `project.pbxproj`, accepted Explore alignment, Browser layout/scrolling, Filter implementation, WCA Results, protocol mappings and all other existing files remain unchanged relative to this task's starting state. No test/build process started by this pass remains active at closeout.

## Scoped Files

Existing files changed relative to this task's baseline:

```text
CubeFlow/Views/Shared/SmartCubeBluetoothManager.swift
CubeFlow/Views/Shared/SmartCubeDiagnostics.swift
CubeFlow/Views/Shared/SmartCubePeripheralSession.swift
CubeFlow/Views/iPhone/DataTabView.swift
CubeFlow/Views/iPhone/SettingsTabView.swift
CubeFlow/Views/iPhone/SmartCubeLabView.swift
CubeFlow/Views/iPhone/SmartCubeManagementCard.swift
CubeFlow/Views/iPhone/TimerTabView.swift
CubeFlowTests/SmartCubeGuidanceTraceTests.swift
CubeFlowTests/SmartCubeManagementTests.swift
```

New files:

```text
CubeFlow/Views/iPhone/SessionNativeActionStyle.swift
CubeFlow/Views/iPhone/SmartCubeGuidanceCaptureView.swift
CubeFlow/Views/iPhone/SmartCubeTimerGuidanceProbe.swift
CubeFlowTests/SmartCubeTimerIntegrationTests.swift
CubeFlowUITests/SmartCubeGuidanceCaptureNavigationTests.swift
docs/guidance-integration-diagnostics-oct21.md
```

All Timer/session/router changes in this pass are DEBUG instrumentation or test seams. Production Guidance behavior is not relabelled as repaired. No physical device was accessed; no devicectl, signed build, archive, upload, commit, push, reset, revert or cleanup was performed.

## Manual Physical Evidence

1. In the newly built DEBUG app, open **Settings > Development > Guidance Capture**. Debug Mode and Protocol Debug can remain off. Stop an existing recording if needed, press **Clear Guidance Capture**, then enable **Record Guidance**.
2. Return to Timer with the trusted connected 3x3 and its existing original scramble target. Do **not** Mark Solved or request a new scramble. Make one relevant deviation, then pause about two seconds. Do not make another 15-20 turns just to force a change. Note whether the instructions visibly change, and the cube model/input mode.
3. Return to **Settings > Development > Guidance Capture**, disable **Record Guidance**, then **Copy Guidance Diagnostics**. Paste the text with the short physical action description and whether the stalled display persisted throughout the pause. The count and copy action remain available after stopping; do not force-quit before exporting.
4. Interpret scalar transport counts, linked protocol/canonical/Timer move IDs, active-route acceptance, final source/sequence, displayed-path validity/digest, scheduled/candidate/adoption checks and final SwiftUI update together. An equal verified continuation can legitimately remain quiet. A latest stationary path that fails replay, or stops at an earlier sequence, is different evidence. Raw packet capture is a separate follow-up only if this identifies a pre-canonical input problem.
5. Physically compare management buttons against Data > Sessions > Edit; check full-width/equal-width actions, title/battery balance, neutral Disconnect and unchanged destructive confirmation. Confirm Filter remains crash-free; its latency is not claimed fixed.
