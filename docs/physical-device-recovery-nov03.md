# Physical Device Regression Recovery - November 3-5, 2026

## Summary

Corrected visual turn backlog, device-management ownership, 2x2 target
binding and first-deviation Guidance. Restored the historical Battle hierarchy
with two independently mounted live cubes. Refined Data selection and
competition reports without changing native scroll physics or timing rules.
The complete application unit suite passed with six expected host/opt-in skips.
Physical BLE, display cadence and interactive acceptance remain open.

## Scope and Evidence Boundaries

Continued the existing App worktree and the November 3 performance reports.
The initial status and patch are preserved in `build/physical-recovery-nov03/`.
No commit, push, reset, deployment, real OAuth, backend change, physical-device
operation, software installation, or TNoodle/privacy change was performed.
The existing Xcode project and user-scheme changes were preserved.

Environment: Xcode 27.2, arm64 iPhone 17 Pro simulator, iOS 26.5. User-reported
physical failures remain the acceptance baseline. Simulator rendering, synthetic
clock tests, and compilation do not establish physical BLE latency, 120 FPS,
energy consumption, or iOS 15 runtime behavior.

## Smart Cube Pipeline and Root Causes

### Animation and Frame Pacing

BLE notifications enter the peripheral session, decode on its parser queue, and
apply on MainActor after parser-generation validation. The canonical feed applies
every accepted physical move before rendering; renderer subscriptions consume
that feed independently of SwiftUI snapshot publication. The presentation queue
never owns timing or reconstruction state.

The old presentation policy had a 1/30-second lower bound on catch-up animation.
At low render cadence, the next render callback can arrive just short of that
duration and cost an extra frame. A deterministic same-input comparison
reproduces a large backlog at 30 Hz. This is an established scheduler defect,
not proof that the physical device was literally running at 30 FPS.

| 200 moves at 20 TPS | Previous policy | Final policy |
| --- | --- | --- |
| 30-Hz clock | Maximum 41 pending; 2,817 ms after last input | Maximum 3 pending; 250 ms after last input |
| 60-Hz clock | Maximum 3 pending; 150 ms after last input | Maximum 3 pending; 150 ms after last input |
| 120-Hz clock | Maximum 2 pending; 158 ms after last input | Maximum 2 pending; 158 ms after last input |

These are deterministic logical-clock simulations, not measured display FPS.
The first candidate without the old 55-ms catch-up cap worsened 60/120-Hz stop
latency to 183/217 ms and was rejected. The final policy combines that cap with
the backlog-dependent 120-ms catch-up budget and a 1/120-second minimum.
`scheduler-before.swift`, `scheduler-after.swift`, `scheduler-candidate.swift`
and their harness/results are retained under the build artifact directory.

If visual work is older than 500 ms, obsolete queued visual transitions can be
coalesced only at a completed-turn boundary, keeping the newest three. Canonical
moves, their order, reconstruction, and Timer input are not dropped. Ordinary
and slow input retain every animation. The exceptional 128-entry flood guard
remains bounded. Interpolation and the existing turn geometry are unchanged.

SceneKit now renders continuously only during an active turn sequence and is
explicitly invalidated on that sequence's first tick. Its display link and
SceneKit frame requests use the attached screen's maximum refresh rate on
initial mount and later window attachment. Idle rendering stops again. Existing
hidden/background suspension and foreground canonical resynchronization remain.
This fixes configuration asymmetry and removes an on-demand scheduling dependency;
it does not establish the cause of every subjective initial-frame-rate report.
The existing `CADisableMinimumFrameDurationOnPhone` setting remains enabled.
Two mounted SceneKit renderers each consumed 200 injected canonical events,
settled to their own exact states within 500 ms of stopping, and paused again.
The mounted idle test recorded zero clock callbacks in 500 ms with continuous
rendering disabled. Neither test measures physical BLE or GPU power.

Move timestamps retain decode-to-main/render age rather than resetting to view
enqueue time. Existing opt-in packet/parser/MainActor/canonical milestones are
retained. New DEBUG frame-interval aggregates and visual-coalescing counts use
the bounded diagnostic trace; there is no production per-frame logging.

### Connection, Loading, and Management

A management card previously admitted a connected device only after the reset
policy was resolved. That made its identity and Disconnect unavailable during
an unresolved policy, even with a real connected session. It now admits the
actual connected device independently of battery and policy metadata. Readiness
is still separately authoritative and is not weakened.

There was also an ownership hazard: switching the card's Discovery child to its
Management child could destroy the owner of the pending connection-policy
confirmation. Policy handling now belongs to the card root, which survives that
switch. Embedded pickers and Settings do not present a second confirmation.
The choice is bound to the original connection attempt, not whichever device
happens to be selected when a delayed action executes. A disconnected attempt
cannot approve or reset a newer connection.

These changes address concrete state/ownership defects. They do **not** prove
that all reported permanent Loading or missing GAN battery failures have the
same cause. Subscription acknowledgement, initial authoritative-state arrival,
decryption, and real reconnection still require a physical trace if the issue
recurs. Existing bootstrap waits for notification acknowledgement and is guarded
once per connection attempt; no guessed timeout or forced-ready state was added.

WeiPo Reset no longer becomes unavailable merely because a trusted state is
awaiting the next A3 after a turn. A reset requested in that interval is bound to
the connection attempt and waits for the latest valid authoritative A3 before
creating its local reference. Disconnect clears it. Missing/untrusted/invalid
native state remains a real guard. No undocumented protocol mapping was changed.

### 2x2 Event Binding

Selecting an active connected device was previously restricted by the Timer's
old requested puzzle size; a persisted 3x3 event could therefore exclude the
connected 2x2. The active-device picker now permits connected management devices
of either supported size. Smart Cube Timer event/scramble/model/persisted event
are synchronized from that active session's puzzle size. With no connected cube,
target construction follows the same effective event as scramble generation,
rather than a previous device's size. Ordinary Timer event selection is
unchanged. Mounted tests cover a persisted 3x3 session selecting
2x2, remounting, and switching 2x2 -> 3x3 -> 2x2.

### Guidance

No fixed eighteen-move threshold exists. A concrete integration error did:
Timer passed `keepsEqualPath: true` even when the displayed route was deviated
and had not been rebased to the current source. The controller correctly
suppresses an equal-cost candidate for a valid continuing route, but that
optimization suppressed a necessary replacement in this invalid-route case.

Timer now requests equal-cost replacement when the current path is deviated or
needs a new search. The valid-path optimization remains. The common next-token
path also avoids enumerating every remaining token before verifying the usual
next move. Existing request identity, target, sequence, cancellation, background,
device and trust checks remain. Mounted Timer tests assert the first deviation,
equal-length recovery, repeated departures from target, rapid supersession and
target replacement, not a later arbitrary move count.

The short search provides exact results within its existing three-HTM scope;
bounded Min2Phase results are verified source-to-target routes, not a claim of
global optimality. Standalone Smart Cube turns after target still begin timing;
the after-target Guidance test uses Combined mode to preserve that behavior.

The separate unsolicited Scramble Navigation entry, sheet and unused production
implementation were removed. Normal scramble generation, Guidance and shared
solvers remain. Its useful state-test fixture is now test-only
`GuidanceStateTestHarness`, not a retained hidden product feature. Previously
translated but now unreferenced strings do not expose an entry point.

## Battle

Historical reference: commit `46e32394`, `TimerLocalBattleView.swift`. Restored the
15-pt semibold secondary player name, 28-pt bold score, hierarchy and panel
spacing. Narrow side-by-side panels put the event control below the name/score
row so those two labels do not collide. This is presentation adaptation, not a
revert of the independent timing architecture.

Each player's compact native ellipsis menu opens existing input configuration
or the native handicap picker. Timing, scoring, both-ready gating, manual input,
round restoration and independent device assignments are preserved.

The missing model integration was real: independent timers/feed ownership did
not by itself mount a cube. Each Smart Cube panel now observes its assigned
peripheral session and mounts the shared renderer with its own 2x2/3x3 size,
canonical feed, trust and attempt. Square viewports prevent narrow panels from
cropping the model. Tests mount two actual SceneKit views in both layouts, send
distinct moves, and assert the other model remains unchanged. Both full-panel
screenshots and SceneKit snapshots were generated and inspected. This is not
physical dual-device acceptance.

## Data

- Select/X retains one Button identity instead of switching between separate
  toolbar buttons. No animation-duration extension or artificial delay was used.
- The selection-only native bottom toolbar no longer adds a full-width opaque
  background on iOS 26+. Existing scroll-edge blur remains its single background
  owner; native controls and their interaction remain. Tests retain the actual
  List scroll owner across selection/filter changes. Physical transition flashing
  still needs light/dark acceptance; static screenshots do not prove every frame.
- Checkmarks use a short progressive stroke trim, with the existing selection
  circle. Reduce Motion disables the draw transition. Fast selection remains
  synchronous.
- Select All becomes Deselect All for the current visible filtering scope.
  Filtering still prunes hidden destructive selections, preserving prior safety.
- Number-column font measurement is hoisted out of each visible row. Session
  selection counts are loaded through the owning private Core Data queue using
  count queries, not by materializing every session's `solves` relationship.
  The 1,000-solve fixture verifies counts and that those relationships stay faults.
  Its two count queries took 22.15 ms in the final simulator run, off the UI
  context. This is not a measurement of native menu opening latency.
- Histogram bins use human-readable widths and aligned boundaries; Square-1
  uses at least one-second bins. Empty outlier gaps do not create thousands of
  bars. Counts remain exact, including the final closed boundary, with at most
  80 occupied bins. Large, skewed, sparse and invalid-value cases are covered.
  A 4,000-solve fixture produced five aligned bins in 4.68 ms. The complete
  run also rechecked value-owned chart reuse: 100 reads of 2,000 solves took
  14.1-14.3 ms with one snapshot build versus 1,211-1,232 ms rebuilding on each
  read. That comparison includes the previous caching work and is a CPU
  microbenchmark, not a scrolling measurement.
  Line Chart structure is unchanged.

### Exact Button-Style Terminology

Sessions Edit is not a plain SwiftUI `.bordered` button. Its native toolbar
bridge uses `UIBarButtonItem.Style.prominent` plus `tintColor = .systemBlue` on
iOS 26+, and `.done` on older iOS. The existing shared policy is
`SessionNativeActionStyle`. Its corresponding content-button configuration is
`UIButton.Configuration.prominentGlass()` with tint on iOS 26+, falling back to
`.borderedProminent()` on iOS 15-25. Untinted actions use `.glass()` / `.bordered()`.

Suggested short name: **Native Tinted Prominent Glass** (with the native older-OS
fallback). Data selection Delete and Solve Detail Delete now use that shared
configuration with `.systemRed`, retaining their existing confirmations and
destructive behavior. It is not a hand-painted solid red substitute.

## Competitions and Reports

My Competitions now requests the available localized-name index before initial
Chinese presentation, rather than limiting itself to whatever detail pages had
already cached. The existing actor coalesces concurrent index loads; English
does not request that index. A cold-cache zh-Hant/zh-Hans fixture verifies one
request and both localized names before any detail navigation.
The page, name enrichment and loading state have one request owner. A cancelled
or superseded name lookup cannot publish stale rows, clear a newer spinner, or
leave its own spinner running. Both the account publication revision and
language still have to match. Removed the redundant second name lookup from
the view task. Deterministic tests hold name resolution across cancellation
and overlapping refreshes without real OAuth or provider calls.

The participation mark's entire control is 20 pt rather than 26 pt. It uses a
mini native capsule with zero extra content insets, not just a smaller glyph.

Competition/round result-card Report is a circular share control directly below
the existing X, reusing its 38-pt visual diameter and 44-pt hit target. A round
summary loads the competitor's complete report on demand, without navigating
to another card or exporting just that round. Loading failure presents the
existing error; cancellation and selection identity prevent stale presentation.
The card header reserves the controls' vertical space so native glass shadow
does not tint the first table's badges. The existing 36-pt rows and their
single/average corner-badge pixel checks are unchanged.

Report rendering removes both the fallback top-left CubeFlow label and the
footer branding. Fallback is localized Competition Report; footer is just the
page number. Competition/person title hierarchy is consistent. Report record
images reuse compact badges, with blue PR only for the signed-in matching
competitor and gray PR for others; WR/CR/NR keep their existing semantics/colors.
Actual generated output was inspected. Result Highlight design was not redone.

Complete pagination, wrapping, row/attempt formatting, off-main serial PNG
rendering, per-page memory limits, lazy previews, all-page share/Photos inputs,
cancellation cleanup and file leases are preserved. A 12-million-pixel limit is
per image, never a silent row limit. Existing 4,000-row planning, 512-row export,
concurrent/cancelled export and lease tests remain in the complete regression.
Final run: 4,000 rows planned as 82 pages in 1,121 ms; 512 rows exported as eight
PNGs in 878 ms with a largest page bitmap of 46,972,800 bytes. This is a per-page
bitmap bound, not a process RSS or share-extension memory measurement.

## Launch and Tab Responsiveness

The Timer-first launch reservation, retained lazy tab identities and existing
off-main snapshots were reviewed. No measured evidence justified adding eager
all-tab prewarming, an artificial splash, a scheduling delay, or a replacement
tab animation. Existing mounted all-tab first-entry/warm-return tests remain.

Final mounted snapshot test (ms; includes UIKit/SwiftUI mounting and screenshot
work, not tap-to-photon):

| Tab | First entry | Warm return |
| --- | ---: | ---: |
| Timer | 104 | 339 |
| Data | 205 | 476 |
| Algs | 509 | 437 |
| Explore | 766 | 359 |
| Settings | 500 | 450 |

The Data fixture published its 1,000 rows after 565 ms on first entry, with one
fetch. These are single-run snapshots, not evidence of transition clipping or
a controlled speedup over the previous run.

The targeted cold-launch UI test verifies the actual restored Timer controls,
including an enabled/hittable input menu, event control, and non-placeholder
scramble presentation. The Simulator TNoodle bridge deliberately reports
unavailable, so this cannot establish first usable solve or native scramble
generation latency. Mounted Timer reservation and scramble lifecycle tests use
deterministic injected generation and separately validate that state handoff.

| Launch measurement | Final observed result |
| --- | --- |
| XCTest system AppLaunch (five samples) | 2.165 s mean, 1.769-2.570 s range, 15.2% relative standard deviation |
| Timer controls, three terminated-process relaunches | 10.740 / 5.241 / 5.214 s, including XCTest startup, idle checks and accessibility IPC |
| DEBUG persistence initialization | 36.7 / 19.2 / 18.1 ms |
| DEBUG Timer initialization span | 3.8 / 1.4 / 1.5 ms |
| First active display callback from persistence begin | 1,507 / 819 / 850 ms |

The DEBUG callback is not the first visible pixel, and the XCTest control
measurement is not touch-to-photon. The largest traced interval is before the
root's appearance, not inside the measured persistence or Timer initialization
spans; that interval is not attributed to a specific code bottleneck. Prior
1.550 / 1.657 / 1.692-second launch means and this noisier run do not form a
controlled A/B. No startup speedup or absence of physical regression is claimed.
Subjective Data/Algs/Explore animation clipping remains a physical profiling item
if it persists; no speculative native tab-transition replacement was made.

## Verification

Result bundles and logs are under `build/physical-recovery-nov03/`.

| Artifact | Result |
| --- | --- |
| `recovery-verified.xcresult` | 15/15 focused recovery cases passed before final regression corrections |
| `full-unit.xcresult` | Simulator preflight busy; zero tests executed |
| `full-regression.xcresult` | Complete run: 1,154 passed, 7 failed, 6 skipped |
| `regression-corrections.xcresult` | 31/31 passed, including the seven previous failures and recovery fixtures |
| `full-final.xcresult` | Complete run before the DEBUG launch trace correction: 1,167 total, 1,161 passed, 0 failed, 6 skipped |
| `launch-final` | System launch metric passed; DEBUG traced launch crashed, remaining test attempt interrupted |
| `launch-trace-verified.xcresult` | DEBUG crash absent; original assertion assumed an ordinary Timer rather than the persisted Smart Cube session. Simulator also lacks the native TNoodle generator |
| `launch-controls.xcresult` | **1/1 passed**, three cold launches with DEBUG tracing and restored Timer controls |
| `full-after-trace` | Interrupted to correct the My Competitions publication race; not counted as a complete result |
| `localized-names-ownership.xcresult` | **6/6 passed**, cancellation, overlapping refresh, localized index and participation coverage |
| `full-closeout.xcresult` | **Complete final-source run: 1,169 total, 1,163 passed, 0 failed, 6 skipped** |
| `generic-debug.log` | **Unsigned generic iOS Debug build passed**; app Info.plist and Mach-O both report minimum iOS 15.0 |
| Localization | Validator passed 19 catalogs; `plutil` passed 60 `.strings` files and `Config/Info.plist` |
| Whitespace | `git diff --check` passed; existing project configuration and dirty changes retained |

The final run contains 812 XCTest cases (806 passed, six skipped) and 357 Swift
Testing cases (all passed). The skips are five real Keychain cases unsupported
by the unsigned host (OSStatus -34018) and one opt-in provider probe. Optional
post-test diagnostics could not find `simctl`; the test run and result bundle
completed successfully. No failing suite was excluded.
`codesign -dv` confirms the built app is unsigned, and `vtool -show-build`
reports `platform IOS`, `minos 15.0`, SDK 27.2. This is a compilation check,
not iOS 15 runtime verification. Existing TNoodle privacy-evidence and missing
AppIntents metadata warnings remain; nothing here changes those release gates.

Early harness failures were investigated, not hidden: the first new Data test
incorrectly expected hidden selected rows to remain selected; native list layout
also lagged snapshot publication. New routed BLE fixtures initially received the
simulator's real radio-unavailable callback and now use the existing scan test
driver. The first WeiPo fixture paired a native F code with a contradictory A3;
it now uses the already-verified F endpoint from CubeStateEquivalenceTests.
Production protocol validation was not relaxed.

The first complete run exposed native Report-button shadow tinting the first
badge row, an overly aggressive visual age cap for the existing 24-turn burst,
and a disconnected Timer building a 3x3 target for a 2x2 scramble. The source
fixes preserve the original pixel, exact intermediate-frame ordering and target
affinity assertions. Two old histogram assertions encoded the deliberately
replaced fixed-bin algorithm; the new checks require aligned boundaries, exact
counts, unchanged penalty/time ordering and a golden one-second fixture. The
remaining failures were harness issues: the mounted Guidance test now waits
for its observer to appear, and the Algs screenshot test creates its own output
directory. The complete final run rechecked all of these together.

Cold-launch profiling itself exposed a DEBUG-only crash before persistence
initialization: `EXC_BAD_ACCESS` in `_os_log_encode`, reached from the C-format
`os_signpost` call in `AppExperienceTrace.mark`. Switched to typed `Logger` and
`OSSignposter` interpolation (available on iOS 15). No new launch work is done
with the trace disabled. The restored-state UI test subsequently passed all
three traced launches. The underlying Simulator TNoodle bridge was not changed.

### Files Changed in This Pass

- Smart Cube: `CubeTurnPresentation.swift`, `SmartCube3DView.swift`,
  `SmartCubeBluetoothManager.swift`, `SmartCubePeripheralSession.swift`,
  `SmartCubeExperience.swift`, `SmartCubeManagementCard.swift`,
  `SmartCubeLabView.swift`, `ConnectedDevicesView.swift`, `SettingsTabView.swift`,
  `TimerTabView.swift` and removal of `SmartCubeScrambleNavigator.swift`.
- Battle: `LocalBattleDevices.swift`, `TimerLocalBattleView.swift`.
- Data: `DataTabView.swift`, `SolveManagementViews.swift`,
  `SessionNativeActionStyle.swift`, `SessionSolveSnapshotReader.swift`,
  `SessionSolveTrend.swift`, `AppExperienceTrace.swift`.
- Competition: `WCAMyResultsView.swift`, `CompetitionTabView.swift`,
  `CompetitionNativePresentation.swift`, `CompetitionSharePreview.swift`,
  `CompetitionSharing.swift`, `CompetitionPagedExport.swift`.
- Regression coverage: new `PhysicalRecoveryRegressionTests.swift`,
  `PhysicalRecoveryPresentationTests.swift`, `PhysicalRecoveryLaunchTests.swift`
  and `GuidanceStateTestHarness.swift`; supporting updates to the existing
  animation, Guidance, performance, Battle/sharing and Algs fixtures, plus
  `WCAOfficialParticipationTests.swift` for page/name request ownership.

## Physical Acceptance

1. Connect GAN immediately after cold launch, repeat Ask/Keep/Reset policies,
   and check Timer and Settings models. Open management even before battery
   arrives; Disconnect must remain available. If Loading recurs, reproduce in
   DEBUG with `Protocol Debug` enabled and use `Copy Guidance Diagnostics` to
   retain the bounded protocol/readiness trace. Do not assume missing battery
   data is proof of missing authoritative state.
2. Turn slowly, normally, and at roughly 20 TPS for 10 seconds. Check the first
   turn after idle, continuous motion, brief stopping, tabs, background/foreground,
   and multiple live views. Final state must match and old moves must not replay
   for seconds. Compare initial mount and remount. Check camera drag after idle.
   Measure actual frame pacing on the 120-Hz iPhone; use the diagnostic capture
   only for a second pass so the normal feel is evaluated without tracing.
3. Select WeiPo 2x2 while Timer had 3x3 persisted. Verify event, 2x2 model, scramble,
   saved metadata, remount and device switching. Request Reset just after a turn;
   it must stay available and apply against the next authoritative A3.
4. Verify Guidance on the first off-route turn, after target in Combined, rapid
   turns, target replacement, device switch and background recovery. Normal
   standalone timing after a completed scramble must still start normally.
5. Assign two physical cubes in both Battle layouts. Each model and timer must
   follow only its assigned cube, with correct puzzle size, both-ready gating,
   independent finishes, reconnect and round restoration. Recheck manual input.
6. Rapid Data Select/X, Select All/Deselect All with filters, Delete confirmations,
   Reduce Motion, Session selection, and a 4,000-solve Square-1 histogram. Inspect
   the bottom edge through the full transition in both appearances.
7. Cold Chinese My Competitions without opening details; check names and smaller
   participation marks. Open Report from both card levels, inspect own/other PR
   and regional badges, then all-page native Share/Photos including a long report.

## Remaining Uncertainties

Intermittent physical Loading/battery transport failures, exact input-to-display
latency and 120-Hz frame pacing, physical tab/selection animation quality,
physical dual BLE Battle/2x2 timing, and Photos/share-extension delivery remain
unverified. No simulator test substitutes for those checks. Cold-launch change
versus the earlier binary is not established without a controlled comparison.
