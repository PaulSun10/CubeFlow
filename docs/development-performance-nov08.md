# CubeFlow development and performance, November 8, 2026

## Critical issues

### WeiPo 2x2 Timer ownership

`SmartCubeBluetoothManager.reconcileActive()` previously used the requested Timer puzzle size to both choose and retain an owner. A connection that initially looked like 3x3 was eligible, but when its identity resolved to WCU_MY22/2x2, the identity publication scheduled reconciliation and removed it from the 3x3 candidate set. Management addressed the peripheral session by ID, so it kept showing that session's live 2x2. Timer addressed the manager's active session and fell back to the old requested size. The earlier manual-connect fix ran at connection time, before this later identity publication, and did not cover automatic reconnect.

The connected owner now remains authoritative after classification. With no owner, the manager considers the requested-size preference first, then takes the sole connected cube if there is no match. Explicit selection still works without disconnecting other cubes. The owner records its actual size once when it changes rather than persisting on every cube update or twice during explicit selection. Timer's existing event binding, context validation, renderer, and solve assignment consume that same owner. No changes to BLE decoding, cube animation, or Guidance semantics.

Mounted regression: a provisional connected 3x3 issues a scramble request; the same session receives WeiPo hardware identification and a real-format 2x2 snapshot. The actual Timer renderer changes from 3x3 to 2x2, an old 3x3 result is rejected, the 2x2 target survives remounting, and a fixture solve saves as 2x2. Both simulators passed after isolating the synthetic radio from a delayed simulator CoreBluetooth unavailability callback. This is not proof that the physical unit follows exactly that callback sequence.

### Data Select/X interruption and rectangular fill

The supplied 5.685 s Dark Mode recording shows one enter and one exit, not rapid repeated reversals. Around 2.35-2.42 s on entry, a hard horizontal edge exposes a black region below the list while the search accessory remains visible. The native tab bar briefly retains an empty capsule and the selection actions arrive while the old search accessory is still fading. Exit around 4.3-4.6 s shows overlapping transitions without that same hard edge. See `data-enter-handoff.png` and `data-exit-handoff.png`. The list rows above the edge stay stationary, consistent with the user's stable scroll offsets and changing viewport/insets. The recording's sample gaps are not physical display frame measurements.

Code inspection found two unnecessary changes during this handoff: replacement of the entire native Select/X button and toggling the root's tab-minimization policy at the same time as tab visibility. One Button now owns both labels and the tab retains its normal policy while selection temporarily hides it. No sleeps, debounce, gesture blocking, offset correction, background mask, or alternative animation was added. [Apple's tab minimization](https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)), [tab accessory](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)), and [safe-area bar](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)) are separate mechanisms; the screenshots do not establish which native layer owns the fill or what causes the rapid-tap hitch. Those two physical issues are not closed. The `glassEffect()` and `unsafeForcedSync` reports were not attributed to an application call site; neither text recurred in the complete simulator log. Simulator QoS warnings do not establish a connection to either.

The selection bar still has fixed leading/center/trailing anchors and 44 pt targets. Each action adapts to text or symbol independently using measured text and the actual center width. The existing English, Simplified Chinese, and Traditional Chinese Deselect All strings are used. Mounted tests cover both appearances, repeated reversals at both scroll edges, selected counts, hit testing, and the delete confirmation. They invoke the actual state handlers but do not measure finger-to-display latency.

## Performance and cleanup

The paired computation test uses the same 8,000 immutable samples, nine rolling metrics, DNF/+2 cases, and five trials. The prior path independently compressed/sorted each metric's input, materialized every result window, and allocated a second list to find each best finite window. Records now shares the input index and finds the same first best finite window during evaluation, with no full window arrays. The Average list still computes and displays every window. The test compares every metric's current value, best value, and finite window index.

| Subsystem | Baseline | Result | Evidence and confidence |
| --- | --- | --- | --- |
| Data Records computation | 188-200 ms | 99-104 ms | Two five-trial iOS 26.5 arm64 Debug runs; about 48% lower median in both. Strong for this computation, not a first-entry or frame-rate claim. |
| Launch | 1.608 s average, 6.67% RSD | 1.508 s average, 1.51% RSD | Five XCTest process launches on the same simulator model. No startup code changed; variation is not a demonstrated speedup. Timer controls with polling: 5.03-5.11 s versus 5.18-5.29 s. |
| Mounted tab first/reentry | Timer 107/337, Data 425/454, Algs 592/430, Explore 839/518, Settings 475/356 ms | 87/327, 449/439, 494/418, 849/489, 455/381 ms | One harness cycle pair per run. Data's initial 1,000-row snapshot still uses one fetch. Not a stable comparison or a device first-frame measure. |
| Report PNG | 68 rounds about 289-298 ms; 512 rounds about 1,033-1,037 ms | 68 rounds 260-265 ms; 512 rounds 964-974 ms | Separate simulator samples after a spacing change. Do not claim an encoder speedup. The 512-round output is one 1077 x 43608 PNG; largest strip bitmap remains 2,580,480 bytes, not a peak RSS bound. |
| Smart Cube discovery | Per-refresh candidate array and Set union/subtraction | Short-circuit stored-device/reconnect membership checks | Same discovery policy and existing scanner regressions; no hardware CPU/energy claim. |

A 10 s Instruments Time Profiler launch on iOS 27.0 captured app and Timer SwiftUI construction, main-thread Core Data initialization, and off-main scramble resource prewarming. No paired Instruments trace or compositor timing exists. One ancillary table reported no known input source; time-profile samples were present. The trace supports leaving persistent-store ordering and prewarming alone. Renderer clock, camera and scene ownership; Guidance cancellation; Timer prefetch; Algorithms indexing; Explore, CubingChina, WCA result caches and navigation; and image encoding were inspected or covered by existing regressions, not rewritten. Long-session energy, GPU pacing and heap growth remain hardware profiling work.

Removed the superseded Battle handicap menu and matched-glass settings presentation. Reused existing card surface, shadow, backdrop, native circular close control and GAN connection details rather than adding parallel UI or a BLE transport.

## Battle and share

- Battle uses independent Results-style settings panels. The opposing panel retains its rotation and can remain open separately. Event selection keeps settings open; X closes it. Motion is a restrained scale/fade with Reduce Motion support. The bottom-left exit uses the same close button. Smart Cube input is offered only for supported 2x2/3x3-family events. Touch and manual remain available. One player may use the existing GAN Smart Timer at a time; a matching hardware completion uses the transmitted time, not the app's wall-clock estimate. Duplicate running packets refresh correlation without restarting the round, and disconnection/stale completions do not submit a score.
- One signed -10...10 value backs both steppers. The other player sees its negation; only the giver's displayed final time and scoring time increase. The raw result is unchanged; local Battle scores remain in-memory, with no new persistence. Handicap changes cannot alter an active or partly completed round.
- Competition Report only normalizes divider-to-event-title spacing and divider margins. Banner, text, rows, formats, order and full single PNG remain. The rendered layout test verifies the divider margin and 10 pt title gap for six events.
- The editorial Highlight groups event, metric, the selected metric's highest verified record, and the value. Identity and competition follow one blue rule. Average/Mean shows attempts; Single and individual-attempt exports do not reserve that space. No branding. Inspect `highlight-ordinary-light.png`, `highlight-WR-dark.png`, `highlight-single-light.png`, and the remaining PR/NR/CR/WR variants in `build/development-nov08/`.

## Verification and acceptance

- iOS 26.5 first complete application run: 1,193 passed, zero failures, six skipped across 841 XCTest and 358 Swift Testing cases. The skips were the opt-in provider probe and five entitlement-dependent Keychain cases. Five XCUITests covered launch and Competition navigation/share entry points.
- Second complete application run: 1,192 passed, one test failed, six skipped. The unchanged organizer WebKit test read an uninitialized document after its settle window; the log reports about 2.1 s WebContent/GPU startup and 0.58 s Launch Services delay. This is consistent with a timing-sensitive fixture, not proof of a production regression. The same test passed unchanged in the first suite and in 0.339 s on the focused rerun. Do not count that as a clean second full run.
- Latest source: 18 focused iOS 26.5 cases passed, including the GAN repeated-packet and rejected-early-start tests, both-ready/dual-cube round cases, mounted WeiPo and the organizer rerun. The enhanced Report/Highlight fixtures passed and the iOS 27.0 mounted set passed 4/4 before the last isolated Battle packet gate. The original test-only radio race was corrected using the existing DEBUG scan driver.
- Final unsigned generic iOS Debug, localization lint (60 files), and `git diff --check` passed. The app plist retains iOS 15.0 minimum; no iOS 15 runtime was used. Existing TNoodle and App Intents metadata warnings remain outside scope.
- First manual check: with Timer's previous event set to 3x3, connect only WeiPo, open Timer without reopening management, verify 2x2 model and scramble, then save a 2x2 solve. Repeat on auto-reconnect and briefly check a GAN 3x3 remains normal.
- Second manual check: on the affected iPhone, compare a settled enter/exit and rapid reversals at both list edges in Light and Dark, with tracing off first. If either defect persists, correlate a new recording with the existing opt-in DataSelection trace; compare the fill and hitch separately.
- Third manual check: in both Battle layouts, verify each X and persistent event selection, check +5/-5 scoring with a real GAN timer and another input, then disconnect/reconnect mid-round. Review the exported Highlight and a long Report in preview, Share, and Photos.

All application changes remain in the existing dirty worktree. The user-supplied DEBUG scheme setting is preserved. No physical device, Web/Broker repository, production infrastructure, Git commit or push was used.

## Files and evidence

- Smart Cube: `SmartCubeBluetoothManager.swift` and `SavedSmartCubeDevices.swift`.
- Data and shared iPhone shell: `DataTabView.swift`, `IPhoneContentView.swift`, and `DataTabSupport.swift`.
- Battle: `TimerLocalBattleView.swift`, `TimerTabView.swift`, and `LocalBattleDevices.swift`.
- Export: `CompetitionReportImage.swift`, `CompetitionPagedExport.swift`, and `CompetitionSharePreview.swift`.
- Regression fixtures: `PhysicalRecoveryRegressionTests.swift`, `SmartCubeManagementTests.swift`, `NativeUIRecoveryTests.swift`, `BattleEventSelectorTests.swift`, `BattleMixedInputTests.swift`, and `CompetitionPagedExportTests.swift`.
- Local results, build logs, Time Profiler trace, screenshots and exported PNGs: `build/development-nov08/`. The final duplicate-packet gate was verified by `settled-focused.xcresult` and `generic-settled.log`; the full runs, launch metric, and iOS 27 mounted checks are separately recorded. No third complete run was performed.
