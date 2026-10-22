# Smart Cube Regression Recovery and TestFlight Readiness

2026-10-21. Continued the existing dirty tree. No physical device, signed build, archive, upload, version/signing change, commit, push, reset, or cleanup.

## 1. Historical Findings

Read the preceding `scramble-animation-regression-audit-oct21.md`, earlier Guidance/TestFlight reports, current production paths, focused tests, `git log`, `git show`, and historical diffs before changing behavior.

| Revision | Concrete evidence |
| --- | --- |
| `1844425d` | Recovery/presentation ownership foundation; the text/target affinity defect was already addressed in the preceding pass. No wholesale restoration. |
| `b0cf62dc` | Older Timer-owned recovery task, cancellation/identity guards, fallback and replacement policy. `[SCDEBUG] REPLAN` printed correction/remaining/candidate costs, decision/reason, generation and revision; `[SCDEBUG] GUIDANCE` printed restoration/suppression decisions. This is not `[ScramblePerf]`. |
| `8eb5369a` | Context-bound scramble prefetch, unrelated to Guidance solver logging. Retained. |
| `4d83d3ed` | Introduced the current animation engine, including dropping queued turns at six pending moves or 350 ms lag and retaining only two live-edge moves. That intentional snap policy is unchanged in subsequent committed history and remained after the preceding sequence fix. |
| Current dirty Guidance controller/planner | Adds latest-state/short/native lanes, validated known-path comparison, and equal-path suppression. The normalization-versus-displayed-cost defect found here is in these uncommitted changes, not attributable to a distinct committed revision. |

No physically verified last-good build can be identified solely from reachable commits. Pre-Phase-3 SceneKit source was snapshot-driven redraw, not a demonstrated earlier smooth-turn queue to restore. The hard-drop policy's introduction is certain; the exact date it became visibly objectionable on the user's device is not.

Historical cost/reason console helpers still exist in `SmartCubeDiagnostics.swift`, but the new controller does not call the old Timer-owned replacement logger. Existing structured rings already record source/target/path digests and publication decisions. Literal old/new path output was not established in the inspected committed logger; it is not falsely claimed to have been restored verbatim.

## 2. Guidance: Proven Defect and Targeted Fix

The planner simplifies and replay-validates a known continuation. The controller formerly compared a candidate against that **internally simplified** cost, even though the actual Timer still displayed the unsimplified route. Therefore a genuine screen improvement could be suppressed as equal-cost continuation reuse.

Negative control uses production fast search and controller: source solved, shown `R L R' U` (4 HTM), exact target `L U`, internally simplified known cost 2, candidate 2. Before correction, publication is nil and the test fails. After correction, the controller publishes the two-move route; an actual mounted Timer also adopts it while preserving the original scramble text and exact original target.

Correction: when verified-known-path evidence exists, compare candidate length with the actual submitted/displayed continuation length, not its hidden normalized length. Equal-cost or worse alternatives still retain the already displayed valid route. Existing source, target, device, generation, trust, cancellation, replay, and adoption guards remain. No solver budget, settle window, algorithm, global-optimality promise, or arbitrary refresh was changed.

Relevant source: `SmartCubeGuidanceController.swift:139`, `SmartCubeReplacement.swift:279`, `TimerTabView.swift:2387`. Existing and new tests cover equal-path retention, real strict improvement, delayed obsolete publications, actual Timer adoption, stationary post-input publication, and exact-target replay.

### Physical Export

The accessible `/Users/paulsun/Downloads/Untitled.txt` is byte-identical to the complete physical export analyzed in the preceding audit, SHA-256 `2aea3af5e841da18b063b6ea8b3c10b2076b1afe3ce3ea0fd5929b0f90726169`. This pass rereads all 2,014 rows and independently recounts stages; it is not a new post-fix capture.

- 920 RX/parser/main applications; 97 decoded, routed canonical moves and Timer consumptions. Sequences 109-205 are contiguous.
- 152 model display paths, all exact-target-valid; 58 candidate arrivals, 56 continuation reuses, two accepted adoptions.
- Maximum primary native search 350.330 ms; improvement 100.364 ms; native queue wait 0.00867 ms. These are distinct intervals, not a 15-20-turn release condition.
- One target digest throughout. The old export lacks original visible-scramble affinity; valid replay to that digest does not independently prove it was the user's intended visible target.
- The prior DEBUG callback defect explains why old view-update rows can describe the preceding context. It remains fixed. Neither those rows nor a model publication proves actual compositor pixels.

The capture lacks path notation and unsimplified displayed costs, so it cannot prove how many of its 56 reuses were affected by the newly reproduced defect. The defect is fixed, but **the physical 15-20-move symptom remains an acceptance gate**, not declared solved by tests.

### Improved DEBUG Evidence

`SmartCubeGuidanceTrace.path` emits bounded, validated move notation (at most 64 tokens), count and existing identity/digest correlation. `candidate-evaluated` distinguishes shown, raw calculated and selected paths; `candidate-arrived` includes shown and candidate paths; reuse records show normalized-known versus displayed cost. Invalid arbitrary strings become `?`. No per-frame log, raw packet/facelets, full device ID, extra polling or unbounded storage is added. The same bounded in-memory ring is used.

Capture remains discoverable at **Settings > Development > Guidance Capture** in DEBUG, independent of Protocol Debug. Move-path notation is deliberately present in this opt-in diagnostic evidence and may coincide with part or all of an original scramble; the separate original-scramble field remains a digest. Share exports only intentionally. `[ScramblePerf]` is still generator performance, not this evidence.

## 3. Animation

The actual coordinator/SCNView negative control enqueues 24 rapid canonical turns. Old code commits intermediate targets without rendering them and drops most queued animations. The negative run fails both settled-state and every-target-in-order assertions.

Changes in `CubeTurnPresentation.swift:94`:

- Ordinary catch-up no longer deletes pending turns at six entries/350 ms.
- An arriving BLE enqueue can start an idle presentation, but completing an active animation belongs to a render tick rather than another enqueue.
- Current-angle continuity is preserved during catch-up; queued animations have a 1/30-second minimum, providing intermediate phases on a normally serviced 60 Hz renderer rather than sub-frame durations.
- The queue is explicitly bounded at 128 pending turns. An exceptional larger unrenderable flood resynchronizes once to its authoritative latest state and records `animation.overflow-resync` in DEBUG. It is not an unlimited replay/backlog promise, nor represented as normal rapid-turn behavior.
- Preserve the preceding canonical-sequence snapshot fence, executable-turn validation, trust/gap/reset boundaries, attempt rebinding, zero-TPS mode, background/foreground recovery and canonical ingestion order.

Tests inspect actual SceneKit pivots/intermediate angles and every target for U/U, U2, mixed turns and a 24-turn burst. Deterministic 60 Hz render ticks under sustained 20 TPS input drain with no skipped target. Overflow remains bounded and subsequent turns can animate. These do not establish real BLE/display cadence on iOS 27.2.

The existing SceneKit lifecycle/performance console prints and scene-tree counting are now DEBUG-only; diagnostic traversal is not retained in Release. Existing animation clock and renderer are unchanged, with no additional timer.

## 4. Device Discovery and Management

Confirmed empty-state cause: Timer used saved-device existence to route a tap into `SmartCubeManagementCard`, whose supported content deliberately requires a connected device. A saved/offline cube or scanning-only state could therefore open its "no connected cube" fallback.

`SmartCubeDiscoverySections.swift` supplies shared native sections to both `SmartCubeLabView` and the existing `SmartCubeDevicePickerView`:

- **My Devices:** all saved identities remain present offline. Connected entries show existing status/battery and open the unchanged management card. Discovered, disconnected saved devices expose a trailing Connect; unavailable/connecting/connected saved entries do not expose another actionable Connect.
- **Other Devices:** currently discovered, supported, unsaved identities, deduplicated by UUID. Successful normal connection uses the existing save path, automatically removing that identity from Other Devices. Two same-model/same-name devices remain distinct.
- The Timer compact row falls back to the actual discovery page when no management-eligible connection exists. A virtual-cube management tap in that state uses the existing picker, rather than presenting an empty card. No Active device is required to browse.
- Explicit rescan clears the previous discovery snapshot along with advertisement timestamps. Saved devices remain; a fresh scan repopulates available entries. Actions recheck current discovery membership before initiating a connection.
- Existing protocol-family classification excludes timers before this list receives peripherals. No name-based filter, protocol change, new scan timer, auto-connect policy, forced disconnect, or Active-selection behavior was added.

Stable UUIDs, Many Connected/One Active, explicit Active selection, connection policy prompts, reset/disconnect/forget semantics and native card buttons remain. Existing mounted management tests cover inspecting an inactive connection without changing Timer Active. New tests cover partition, duplicate names/IDs, discovery disappearance, save/forget/restart, and an actual mounted native list with no Active device.

Radio silence cannot instantly establish physical absence with the existing nonduplicate BLE scan; no expiry poller was introduced. An explicitly refreshed snapshot removes old availability, and an unavailable connection still follows the existing timeout/failure behavior. Physical scan/connect/disappearance remains manual verification.

## 5. Typography and Preserved Controls

| Location | Before | After |
| --- | --- | --- |
| Compact Timer cube battery | Prominent indicator default: body medium, ordinarily 17 pt | Explicit subheadline regular monospaced digits, ordinarily 15 pt; same first-text-baseline row |
| Management battery | 22 pt regular | 23 pt medium monospaced digits; unchanged centered name row |
| Device name | Timer subheadline medium; management Results-derived 24 pt bold | Unchanged |

Actual compact production rows were rendered and inspected in Light and Dark Mode. The actual two-device management Menu card was rendered: battery dark ink is 16.67 pt versus title 17.67 pt. Screenshot attachments are in `images/` and `timer-images/` under this pass's artifact directory. OCR alone is not substituted for optical inspection.

Reset native large/full width, neutral Disconnect, red Forget, equal lower widths, native prominent Glass configuration, colors and destructive confirmation are unchanged from this pass's baseline. `SessionNativeActionStyle.swift` is byte-identical to baseline.

## 6. Smart Cube Scramble Verification

The preceding synchronous text/target assignment, immutable `TimerSolveAssignment`, request/owner fences and single advance after persistence remain. No generator, navigation, persistence schema or historical solve rewrite was added.

Existing actual Timer tests pass three consecutive Smart Cube solves with distinct targets, immediate next-scramble turns, Core Data reload, reconstruction initial state and the production Solve Detail sheet. Device/attempt, session/event and stale-callback tests pass. Ordinary Timer's actual consecutive-solve pixel/persistence tests also pass; this does not recast the user's Smart Cube-specific report as a manual-Timer failure.

## 7. Focused TestFlight Readiness Audit

**Not release approval.** No Release binary was built; account/signing status and App Store Connect were not accessed.

Current configuration remains bundle `com.paulsun.cubeflow`, marketing `0.10.0`, build `1`, minimum iOS `15.0`, automatic signing and an existing team. App Release uses whole-module compilation and has no DEBUG condition; test target minimum 26.2 does not raise the app minimum. Xcode 27.2 beta (`27B5019j`) was used for the permitted unsigned Debug checks. Exact beta-tool upload eligibility is unproven, not automatically accepted or rejected.

**Confirmed engineering gates before a broad external beta:**

1. Missing `PrivacyInfo.xcprivacy` in app/Config/vendor despite actual UserDefaults/AppStorage, uptime and file-metadata usage. Inventory and declare justified reasons before distribution; no blanket manifest was invented in this audit. Apple's [UserDefaults documentation](https://developer.apple.com/documentation/foundation/userdefaults) requires declaration; its [required-reason API categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) define relevant categories and permitted purposes.
2. Existing WCA OAuth still embeds a confidential-client secret and has no authorization state/PKCE round trip. Presence/absence was rechecked without printing credentials. Resolve public-client/authentication security and credential rotation before broad distribution; no secret, auth redesign, server deployment or ICP work is included here.
3. Hardware acceptance remains open for Guidance and live animation. Passing canonical/simulator fixtures does not close those physical regressions.

**Owner/distribution checks still required:** correct app record and bundle, Developer Program/agreements, distribution certificate/profile and application identifier, eligible toolchain, beta description/feedback/contact/review access, privacy disclosures and encryption declaration. The app uses device-protocol cryptography; no export exemption was asserted. See Apple's [TestFlight requirements](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/), [upload guidance](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), and [beta encryption information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds/).

Bluetooth Always usage text and `bluetooth-central` background mode are present; calendar, location, local-network/Bonjour and photo-add descriptions are present. Foreground/background BLE restoration and prompt-denial behavior still require manual acceptance. Release excludes the dedicated capture UI and new path evidence, so preserve any needed Debug capture before switching configurations. Third-party provenance/notices and actual Release optimization/signing validation remain distribution checks, not demonstrated by this Debug build.

**Nonblocking/deferred:** optional discovery auto-expiry beyond explicit rescan, further aesthetic tuning, unrelated Filter latency, other platforms and alternate solvers. None were expanded in this pass. Version/build/signing/entitlements were not changed.

## 8. Verification and Files

Artifacts: `build/smart-cube-recovery-testflight-oct21/`.

- `negative-controls.xcresult`: two tests fail before production correction, at three assertions. Preserved as evidence, not counted as passing.
- `focused-v1.xcresult`: 67 XCTest and 48 Swift Testing tests pass, zero failures.
- `timer-row-final.xcresult`: one additional XCTest (actual Timer row in both appearances) and two specifically selected existing presentation-store Swift tests pass.
- Final distinct passing union: **118 tests**. No broad unrelated suite, physical automation or hidden zero-test success is counted.
- The one authorized unsigned generic iOS Debug build passed, exit 0 (`final-generic-debug.log`), `CODE_SIGNING_ALLOWED=NO`. The only build warning was skipped AppIntents metadata extraction without an AppIntents.framework dependency. No second generic build or Release binary was produced.
- All 7,330 source/configuration hashes are unchanged before/after the final build. Against this pass's dirty-tree baseline: 7,560 files unchanged, 18 scoped existing files changed, no baseline files missing. Additions are the shared discovery sections, focused discovery test file and this report.
- `git diff --check` and three localization plist checks pass. The project file, Info.plist, native button style, prior scramble pipeline/store, Filter, Browser scrolling and accepted Explore alignment remain byte-identical to this pass's baseline. No task-owned test/build process remains active.

Changed existing production files: `CubeTurnPresentation.swift`, `SmartCubeGuidanceController.swift`, `SmartCubeGuidanceTrace.swift`, `SmartCubeReplacement.swift`, `SmartCubeBluetoothManager.swift`, `SmartCube3DView.swift`, `SmartCubeLabView.swift`, `SmartCubeManagementCard.swift`, `ConnectedDevicesView.swift`, `TimerTabView.swift` (offline entry routing only), and the three `Localizable.strings` files (Other Devices label only).

New production file: `CubeFlow/Views/iPhone/SmartCubeDiscoverySections.swift`.

Changed tests: `CubeTurnPresentationTests.swift`, `SmartCubeAnimationRegressionTests.swift`, `SmartCubeLatestGuidanceTests.swift`, `SmartCubeGuidanceTraceTests.swift`, `SmartCubeTimerIntegrationTests.swift`. New test: `SmartCubeDiscoveryListTests.swift`. This report is new. Unrelated dirty files are preserved.

## Minimum Manual Acceptance

1. Build/run this source manually. In Smart Cube mode record the visible original scramble, complete three solves, compare each Data > Solve Detail scramble, and make one immediate following-scramble turn after completion.
2. Turn U/U, U2 and `R U F' L2 D`, then a short rapid mixed burst. Verify intermediate movement and final stickers. Leave/return and reconnect once; legitimate resync must remain correct.
3. For Guidance, Clear and enable **Settings > Development > Guidance Capture**. Return to Timer, record the screen and original scramble, make one deviation and pause about one second. If stuck, stop input, retain the stationary video, Stop and Copy the export. New shown/calculated/selected paths and costs distinguish an unchanged valid continuation from suppressed improvement. Do not make 15-20 extra moves just to provoke publication.
4. With no Active/connected cube, open the cube/device entry and verify My Devices/Other Devices, offline persistence and Connect eligibility. Rescan after moving one cube out of range. Connect two same-model cubes, inspect each card, and confirm the original Active connection is preserved until explicitly changed. Verify Forget confirmation and rescan reappearance.
5. Check both battery locations in both appearances. The existing native buttons must remain visually and behaviorally unchanged.

These manual checks, privacy/authentication work and separately authorized distribution validation are required before claiming first-TestFlight readiness.
