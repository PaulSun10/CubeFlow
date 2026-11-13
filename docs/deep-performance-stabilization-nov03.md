# Deep Performance and Stabilization - November 3, 2026

## Scope and Evidence

Continued the existing dirty App worktree and read
`docs/performance-battle-sharing-nov03.md`. Initial status, patch and SHA-256
file inventory are retained in the ignored `build/deep-stabilization-nov03/`
directory. No commit, push, deployment, real OAuth or physical-device operation
was performed. Existing changes, including the Xcode user scheme, are retained.
No iPad/Mac redesign, TNoodle/privacy changes, new dependencies or software
installation were involved.

Environment: Xcode 27.2, Debug arm64 iOS 26.5 simulator, iPhone 17 Pro model.
The final generic device build targets iOS 15.0. This is not iOS 15 runtime
validation or a physical iPhone performance result.

## Measurements

| Measurement | Before | After | Interpretation |
| --- | --- | --- | --- |
| XCTest application launch, five trials | Mean 1.713 s, RSD 3.19% | Mean 1.550 s, RSD 1.86% | About 9.5% lower on this simulator; not a measurement of the physical black-frame interval |
| Mounted idle virtual-cube application DisplayLink callbacks in 500 ms | 31, continuous rendering enabled | 0, application clock paused, continuous rendering disabled | Removes application idle wakeups; GPU power/frame cadence still needs hardware profiling |
| 1,000 2x2 solved checks, same inputs/full matcher reference | Roughly 294-314 ms | Roughly 0.19-0.26 ms | Predicate microbenchmark, not BLE or whole-solver throughput |
| 128-row report | 81.5 ms synchronous main-thread render; 85,612,800 bitmap bytes | 2.4-13.3 ms main-thread preparation; 43-68 ms total async export; 48,234,240 bitmap bytes | Main-thread work moved and pixel count bounded; about 44% fewer bitmap bytes, not a hard RSS bound |

Raw launch samples are in `launch-before.log` and `compatibility-final.log`.
Renderer baseline is in `baseline.log` / `renderer-before.txt`. Repeated
predicate/export measurements are in `lifecycle-verified.log`, `full-unit.log`
and `final-regressions.log`. No Instruments energy/GPU trace was collected.

## Runtime Corrections

- Startup: unvisited Data/Algorithms/Explore/Settings roots are deferred until
  first selection, then retain mounted navigation identity. Timer and root WCA
  session restoration remain immediate. Persistence ownership and launch-time
  BLE restoration are unchanged. No splash, artificial delay or asynchronous
  persistence rewrite was introduced.
- Rendering: canonical events immediately wake the existing animation clock;
  it pauses when the queue settles. SceneKit uses on-demand rendering while
  retaining its native camera/gesture transactions. Hidden/background views
  keep authoritative state without replaying an invisible backlog. Foreground
  restoration resynchronizes before processing new live turns. Existing TPS,
  turn interpolation, queue ordering and move animation remain unchanged.
- State: solved 2x2 recognition uses the 24 proper solved orientations,
  generated from the existing geometry. The full arbitrary target matcher is
  unchanged. Exhaustive tests compare all 720 uniform color permutations and
  successive scrambled/invalid states against that full matcher. Solved 2x2
  and 3x3 strings no longer allocate repeated per-face strings.
- Guidance: completed identical requests do not repeat searches. Explicit
  cancellation permits retry; A-B-A supersession still selects A. Existing
  identity, source/target, device, generation, sequence and trust guards remain.
  Hidden/background Timer/navigation searches cancel; foreground returns use
  the latest authoritative state. Timing/reconstruction capture still runs.
- Battle: no-op configuration/target/enabled/readiness updates do not rebind,
  reparse or publish. A restored partially completed round permits the other
  player to start independently. A fully scored round is not restored as a
  completed *new* round. Captured connection callback state prevents a brief
  disconnect from disappearing behind a newer queued connected state. Timer
  retains ownership of timing/scoring, both-ready gating and assignments.
- Sharing: main-thread preparation snapshots immutable drawing commands and
  existing badge images. A serial actor owns offscreen bitmap rendering,
  cancellation and an autorelease pool. Latest metric/artwork identity rejects
  stale completion. Existing preview remains visible during replacement;
  sharing/saving is disabled until that replacement is ready. A report bitmap
  is limited to approximately 12 million 8-bit pixels; logical column layout
  is unchanged. The remote image cache has advisory 32-entry / 32-MiB limits.
- Organizer HTML: source identity includes base URL, HTML, color and text size.
  New loads get a nonce; late old-document height messages are ignored.
  Synthetic initial navigation is validated against the current source instead
  of a shared one-shot flag that older callbacks could consume. CSP,
  nonpersistent WebKit and external-link handling are preserved.
- Live selection: explicit initial/user selection synchronously updates the
  retained bridge's selection marker. A queued prior observation can no longer
  make a subsequent configure overwrite the newer UI choice. Equivalent result
  publication suppression and transport contracts remain unchanged.

Offscreen drawing uses immutable image/color snapshots and a worker-owned
context, not background UIKit views. See Apple's
[SceneKit renderer documentation](https://developer.apple.com/documentation/scenekit/scnscenerenderer)
and [image renderer documentation](https://developer.apple.com/documentation/uikit/uigraphicsimagerenderer).

## Regression Results

One complete `-only-testing:CubeFlowTests` run exercised **1,140 tests**:
783 XCTest plus 357 Swift Testing. Initial result: **1,116 passed, 18 failed,
6 skipped**. The XCTest log reports 44 assertion/error events; those are not
44 distinct failed tests.

Every initially failed test was subsequently retested successfully. The whole
1,140-test suite was not repeated a second time. This is broad coverage plus
targeted final verification, not a claim that the original full-run bundle is
green. No failing assertion was deleted, disabled or made more tolerant.

| Final verification artifact | Actual result |
| --- | --- |
| `final-regressions.xcresult` | 46 XCTest: 43 passed, 3 still failed at that stage; all 14 new tests passed |
| `compatibility-final.xcresult` | 137 tests: 136 passed, only the separator sampling test still failed; includes 133 Swift Testing and the launch metric |
| `separator-viewport.xcresult` | Remaining separator test passed, including equal light/dark pixel profiles at the trailing boundary |
| `generic-debug.log` | One unsigned generic iOS Debug build passed, arm64 / iOS 15.0 |
| Localization | All 60 strings files pass `plutil`; 19 Localizable catalogs pass the existing syntax/duplicate/key/placeholder validator |
| Whitespace | `git diff --check` and checks of the new files pass |

Six original skips remain intentional: five real Security.framework Keychain
checks cannot run in the unsigned simulator host (OSStatus -34018), and one
real-provider network probe is opt-in. No credentials or production session
were used to bypass these gates. Existing TNoodle privacy-gate and AppIntents
metadata warnings remain outside this task.

### Failure Investigation

- Battle fixture: initializing the simulator's real BLE central after seeding
  fake sessions allowed its later unsupported-radio callback to clear them.
  The test now uses existing isolated per-device session injection while still
  mounting the production Timer and real tab lifecycle. No readiness predicate
  was loosened. Actual scored-round restoration was corrected in Timer.
- HTML rapid reload: old initial-navigation callbacks could consume the newest
  load's shared flag. Current-source navigation plus nonce-bound height messages
  passes same-HTML/new-base, rapid replacement and late-height tests.
- Retained Live bridge: the queued selection-marker bug above was a runtime
  defect, not merely an outdated test.
- Old tests conflicted with accepted production contracts: compact 20/30-point
  selectors; exact canonical own-PR identity; start-day Browser date windows;
  Western Arabic numeral default; current fixed marketing sample; continental
  ER records; typed provider evidence rather than URL-only Live availability;
  parent-coordinated scramble loading; English competition names from the
  English summary rather than the localized Chinese-name field. Fixtures now
  express those contracts explicitly. Record-discovery tests retain an exact
  bounded request set, allowing only the existing selected-round progression
  neighbors, not unrelated record-round scanning.
- Discovery OCR: the test's locale did not override AppStorage language left by
  another test. It now sets and restores the actual application-language key.
- Guidance trace: a completed duplicate is intentionally not new work; the
  cancellation trace now tests a genuinely new pending identity.
- Chat: the runtime renamed its native item adaptor. The integration test
  recognizes the shared adaptor suffix and still asserts one bottom-right item.
  This test remains sensitive to future private UIKit hierarchy changes.
- Separator: screenshots show intact lines. The geometry probe measures only
  the summary columns, which move outside the horizontal viewport, while the
  actual rule belongs to the whole summary-plus-solves Canvas. Sampling the
  real table viewport, rather than the offscreen summary center/window margin,
  preserves the strict visibility/identical-intensity assertions and passes.
  Production separator drawing was not changed.
- The mounted renderer's fixed 60-ms intermediate-angle assertion failed once
  during the complete run, then passed unchanged in final focused verification.
  That timing sensitivity remains a limitation, not a proven hardware fix.

## Changed Files in This Pass

App source: `ContentInteractionSupport.swift`, `CubeStateEquivalence.swift`,
`CubeTurnPresentation.swift`, `SmartCubeGuidanceController.swift`,
`IPhoneContentView.swift`, `SmartCube3DView.swift`, `TimerTabView.swift`,
`LocalBattleDevices.swift`, `LocalBattleTestProbe.swift` (DEBUG),
`SmartCubeScrambleNavigator.swift`, `CompetitionSharePreview.swift`,
`CompetitionOrganizerHTMLView.swift`, `CompetitionTabView.swift`.

New tests: `DeepStabilizationTests.swift` (11) and
`DeepUIStabilityTests.swift` (3). Updated tests: `BattleMixedInputTests.swift`,
`CompetitionNavigationLoadingTests.swift`, `CompetitionRecordIntegrityTests.swift`,
`CompetitionRecordsRefinementTests.swift`, `CubeFlowTests.swift`,
`CubingChinaUnifiedResultsTests.swift`, `CubingLiveRecordDiscoveryTests.swift`,
`PublishedCompetitionIntegrationTests.swift`, `SmartCubeDevicePolishTests.swift`,
`SmartCubeGuidanceTraceTests.swift`, `WCAExplorePublicDataTests.swift`.
This report is new. Other pre-existing dirty files are not part of this pass.

## Physical Acceptance Still Required

1. Cold launch with representative large local data: first Timer frame,
   scramble/diagram availability, black-frame interval and first visits to each
   deferred tab. Repeat cold/warm runs; simulator launch measurements are not
   physical process-start or disk-migration evidence.
2. Two real cubes: early turns, both-ready start, independent finishes,
   disconnect/reconnect of one player, scored next round and Timer tab return.
3. Rapid Guidance deviations, target/device changes and background/foreground:
   routes must always execute from current authoritative source to current target.
4. Virtual cube: isolated and rapid turns, camera/peek interactions, exact final
   state, foreground restoration, frame pacing and idle energy/thermal behavior.
5. Long mixed-event reports and concurrent exports: final rows/badges, missing
   artwork, rapid highlight selection, actual Share extensions and Photos save.
   The pixel cap and serial worker are not a total-process memory guarantee.
6. Confirm existing List/Glass scrolling, Top Cubers disclosure, Filter native
   presentation, Result Card transitions/Back and trailing-table separators on
   the physical iOS beta. Simulator pixel/lifecycle tests are bounded evidence.
