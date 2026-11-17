# Post-v0.16.1 performance pass

## Summary

This pass starts from `e95e4e04b`, including the v0.16.1 settings, shared Battle scramble, WCA recovery, and badge lifecycle work. The previous [whole-app](comprehensive-performance-reliability-nov03.md), [stabilization](deep-performance-stabilization-nov03.md), [native toolbar/CJK](native-toolbar-cjk-performance-nov09.md), and [November 13 closeout](development-closeout-nov13.md) establish which improvements already shipped. Their measurements are context, not this pass's baselines.

The implemented changes reduce chart history work, repeated Algs learning-state decoding, 2×2 checkpoint canonicalization allocations, and WCA profile HTML processing. None changes a view layout, timing rule, database model, network policy, or app setting.

## Before/after evidence

Same arm64 iPhone 17 Pro simulator, iOS 26.5, Xcode 27.2, Apple M2 Pro host on macOS 27.3 (26C5035r), CubeFlow Debug with the WCA test mock condition, test parallelization disabled. The tests call production code with deterministic input values. One warm-up precedes five trials (chart and WCA) or seven trials (Algs and checkpoints). Values are milliseconds, median (min to max); percentage is `(before - after) / before`. These are local computation benchmarks, not frame pacing, cold launch, real network latency or BLE performance. Wall-clock measurements include simulator scheduling noise. No paired RSS, GPU or power measurement was collected.

| Workload | Before | After | Reduction (ms) | Reduction (%) |
| --- | ---: | ---: | ---: | ---: |
| Chart history, 1,000 solves | 15.337 (15.130–15.592) | 12.839 (12.694–13.038) | 2.498 | 16.3% |
| Chart history, 10,000 solves | 145.221 (141.734–148.267) | 117.752 (116.177–119.387) | 27.469 | 18.9% |
| Chart history, 50,000 solves | 721.021 (708.430–752.764) | 593.726 (581.313–596.352) | 127.294 | 17.7% |
| Chart history, 100,000 solves | 1,423.635 (1,418.931–1,447.606) | 1,150.387 (1,145.477–1,159.413) | 273.248 | 19.2% |
| Learning indicator checks, 493 cases, 5,825-byte progress JSON | 84.157 (82.426–89.542) | 0.452 (0.437–0.503) | 83.704 | 99.5% |
| 2×2 checkpoint keys, 1,024 simulated turn states | 89.034 (87.595–91.673) | 57.235 (55.732–57.925) | 31.799 | 35.7% |
| WCA profile HTML, 1,600 result rows, 793,745 bytes | 335.409 (331.599–345.012) | 131.502 (130.551–132.191) | 203.907 | 60.8% |

Chart, Algs and checkpoint after values are from the focused run, and each was repeated successfully on final code in the full suite. WCA after values are from that full run, under the same simulator/build configuration as the focused WCA baseline.

### Startup baseline

Before changes, XCTest measured app launch at 1.571 s mean, 1.70% relative standard deviation, five measured process launches (1.539–1.614 s). The repeat reported 1.542 s, 1.25% RSD (1.519–1.566 s). The ranges overlap; no startup code changed and no launch improvement is claimed. This is the XCTest launch metric, not a compositor trace, scramble readiness measurement, reboot-cold launch, or warm foreground-resume timing.

Separate mounted snapshots measured first entry / reentry of Timer 120/344 ms, Data 594/552 ms, Algs 954/328 ms, Explore 723/498 ms, and Settings 635/378 ms. One two-cycle run with 1,000 fixture solves; intervals include mounting, native layout, screenshot rendering and test polling. Data first published in 617 ms with one fetch; second activation was at two cumulative fetches. A reentry fetch alone does not prove it is redundant, because Data must also see saves made elsewhere. No startup or tab latency reduction is claimed.

The full-suite repeat measured Timer 131/321 ms, Data 221/534 ms, Algs 523/530 ms, Explore 580/422 ms and Settings 567/436 ms. Data first published in 603 ms, also with one fetch. The large swings, including slower Algs reentry despite cheaper learned-state reads, rule out general tab-latency claims from these samples.

The separate Timer readiness UI harness passed three process relaunches (median 5.181 s, range 5.095–5.301 s) and three warm foreground activations (median 1.670 s, range 1.641–1.670 s). These measurements include XCTest activation/polling delays. They are final-state observations, not a paired before/after, not a first-frame reading, and not native scramble/diagram latency.

## Implemented changes

- **Data charts:** `SessionPerformanceHistory` reused the indexed history and bounded buckets shipped before this pass but built each Ao5/Ao12 window from copied solve samples, repeatedly decoded penalties, and built sorted temporaries. It now adjusts each sample once, keeps the latest 12 ranked inputs, and uses one reusable scratch buffer with `SolveMetrics`. The chronological sort, timestamp tie-break, DNF sentinel ordering, trim/sum order, chart selection and buckets are unchanged. Fixed-sized window buffers replace per-row window allocations; the history itself still stores an observation per solve.
- **Algs:** Row, group and overview progress reads used the same JSON string but decoded it for each lookup. A main-actor, one-entry read cache keyed by the complete saved string reuses the unchanged map. Updates still write via the same persistence path; a changed, malformed, or replaced string is decoded as before. Canonical membership and legacy keys remain the source of truth. This retains one decoded map, not a historical cache and not one cache per row.
- **Smart Cube:** The exact 2×2 checkpoint canonicalizer now compares normalized candidates lazily and constructs only the winning key. Rotation search, lexicographic choice and accepted inputs are unchanged. The benchmark requires the original digest of every checkpoint byte; an independent existing test compares against the exhaustive equivalence matcher. No changes to move capture, solver decisions, stale-result rejection, native protocols or rendering.
- **WCA/Explore:** The profile result parser was normalizing competition and individual solve cells twice per row and normalizing unused cells. It now normalizes only displayed values once, slices attempts without a separate copied array, and reuses fixed hot regexes. A full sorted-JSON digest from the baseline protects complete parsed output, including inherited competitions, official badges, trimmed attempts, and DNF. HTTP/auth, publication, disk persistence, and freshness are unchanged.

## Broader review and decisions

| Area | What was checked and why it was retained |
| --- | --- |
| Startup / first use | `CubeFlowApp` initializes Core Data before injecting its context; it reserves the persisted visible event's scramble only when eligible. `IPhoneContentView` defers unvisited tabs and retains mounted navigation identity. No paired device trace attributes the black frame to a safely movable cost. No prewarming of inactive tabs, persistence migration, or first-interaction deferral. |
| Timer / scramble | `TimerScramblePipeline` already runs generation on worker queues, isolates FTO, and defers secondary warming until the existing readiness gate. Timer's previously optimized PB/snapshot work, context-aware prefetch, solve accuracy and immediate state transitions stay intact. No evidence supports changing scheduling or reserving extra scrambles. |
| Data / Sessions | `SessionSolveSnapshotReader` returns immutable values from a private Core Data context; derived indexing/statistics are detached. Session-sheet counts still issue one count per session; measure with a realistic multi-session SQLite store before changing store query shapes or count freshness. No migration, fetch projection, selection, or import/export behavior change. The largest new workload is chart computation, not a 100,000-row database/UI benchmark. |
| Smart Cube / Virtual Cube | `SmartCubeGuidanceController` retains task cancellation and latest-state gates. `SmartCube3DView` renders on demand. The mounted regression again recorded zero application display-link callbacks in 500 ms with continuous rendering disabled; this confirms existing idle behavior, not new savings. The change is confined to 2×2 checkpoint computation. No measured BLE, first-turn, continuous frames or idle-energy improvement. |
| Battle | `LocalBattleScrambleState` bounds preparation to the current and next round, blocks round advancement until both solves complete, and owns readiness per player. No duplication of scramble generation or change to waiting feedback, input combinations, or timers. |
| Algs / training | Existing indexed search, Square-1 CSP work, ordered grouping and bounded diagram caches remain. Only persisted learned-progress reads changed; no sort, case content or training behavior changed. |
| Competition / WCA / Live | Cache-first list publication, provider identity, snapshot size/age caps, in-flight coalescing, and schedule parsing are already protected. Observed repeated grid label formatter construction in `CompetitionTimedScheduleView`, but did not change that or the native Filter without mounted timing evidence. The WCA change is limited to existing HTML parsing; no Live routes or official/provisional rules changed. |
| Settings / shared UI | Checked tab activation, localization caches and screen-awake lifecycle. No benchmark justified changing broad observation, appearance previews or idle-timer ownership. The feature badge, native controls and translations are untouched. |

No experimental production rewrite was applied and reverted. Changes considered but not taken include speculative startup service deferral, a different Data store/query strategy, broader Algs view caching, and renderer or BLE publication changes without a device trace.

## Reproduction and evidence

Run `PostReleasePerformanceTests` with the CubeFlow scheme, an iOS 26.5 iPhone 17 Pro simulator, `-parallel-testing-enabled NO`, `CODE_SIGNING_ALLOWED=NO`, and `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DEBUG CUBEFLOW_WCA_BROKER_MOCK'`. For a paired baseline, run the same test fixture against the baseline implementations; exclude the exceptional-value test and golden assertions only if reproducing the original baseline test revision before those checks were added. On compatible baselines the golden assertions also pass. `WholeAppPerformanceTests/testNativeRootTabFirstEntryAndWarmReturn` and `CubeFlowUITests/testLaunchPerformance` provide the separate mounted and launch baselines.

Local raw logs and XCTest result bundles: `build/post-0161-performance/` (`baseline`, `workloads-before`, `workloads-after`, `wca-before`, `full`, `ui-remainder`, `ui-triage`). Build output is recorded in `generic-debug.log`. The initial after run also passed the existing mounted chart/selection and 2×2 geometry/reference tests.

### Regression results

- All five new tests passed in the unrestricted run (chart fixtures and exceptional values, learned-state update/invalidation, exact checkpoint digest, and complete WCA parsed output).
- The app test target ran 938 XCTest cases: 931 passed, 1 failed, 6 skipped. It also reported 363 Swift Testing cases passed. The skips were five unsigned-host Keychain entitlement cases and the opt-in real provider probe.
- Before the launch-screenshot template, the unrestricted UI run completed 47 cases: 30 passed and 17 failed. The template repeatedly reported the same `testLaunch` selector (3,779 successful invocations in the raw log) and still had not advanced after almost seven hours. The unrestricted run was interrupted at that point; its result bundle is not a completed suite. The remaining UI classes ran separately without rebuilding or modifying the tests: 11 passed and 4 failed, no skips. Combined non-template UI totals: 41 passes, 21 failures, 0 skips. All five Data/Sessions toolbar cases, guidance capture, Timer cold/warm readiness, and inspection Exit passed.
- `WCABrokerAppIntegrationTests.testSharedManagerCreatesOneStableOwner` repeated its [documented pre-pass failure](wca-recovery-battle-nov16.md#automated-evidence): both accesses returned the same singleton, but the configured mock factory saw 0 calls instead of 1. The app-hosted root may have initialized the singleton before the test installed the factory. No test assertion, singleton, mock ordering, or OAuth flow was changed.
- Localization: all 79 tracked app resource files of type strings/stringsdict/xcstrings passed syntax validation; the 19 app language catalogs are unchanged. `git diff --check` passed.
- The unsigned generic iOS Debug build passed with SDK 27.2 and `MinimumOSVersion=15.0` in the product. Local version 0.16.1 (1) came from the existing uncommitted Xcode settings and was not changed by this task. No actual iOS 15 runtime was used. Build warnings include the existing TNoodle privacy evidence gate and skipped AppIntents extraction; simulator runtime warnings included existing native hosting and QoS diagnostics.

UI failure triage (see `full.log` for individual cases):

- `CompetitionPhysicalFinalBrowserTests` and the Makati `CompetitionTopCuberProfileAcceptanceTests` use the saved October 11 Makati and Tokai rows, request Recent, and pass through the real 30-day date filter without an injected date. By November 17 those rows cannot be shown. Missing card controls and missing publication during the intended swipe do not exercise their intended scenario.
- `CompetitionPerformanceTests.testExploreBrowseAndAdjacentSectionChevron` expected `explore-browse-competitions`, an identifier absent from the baseline production hierarchy. `CompetitionScrollRetentionAcceptanceTests` looked for “Competition Scroll Diagnostics”; the unchanged Settings entry is “Scroll Capture.”
- `CompetitionResultsNavigationAcceptanceTests.testOfficialByCompetitorUsesCompleteDownloadedProductionResults` reached the correct Tymon Kolasiński profile (content and title are in the accessibility dump) but its iOS 26.5 navigation bar identifier was the hosting-controller type rather than the competitor name. The result rows had already passed the earlier checks.
- `CompetitionLongScrollAcceptanceTests.testCapturedLongGlassRepeatedSwipesWarm` measured 1.24 pt of title-origin drift against a 1 pt threshold; the isolated repeat failed at 1.46 pt. This exact metric has failed in older saved runs. Its current cause is not established, and the assertion was not changed. The ordinary-scroll and disclosure suites passed.
- Two Explore/competition live-search benchmarks timed out locating named provider rows before reaching the timing assertions. They do not establish a new latency measurement or a regression in the HTML parser.
- In the remaining UI run, the English and Simplified Chinese Explore flows reached Discover but did not find the bundled “Svalbard 2025” row at its initial scroll position. The row remains in the bundled history; recommendations can precede it in the unchanged list. That does not establish the exact cause of the failed assertion.
- The two Timer touch failures were both `timer-time-display` accessibility discovery failures before the first touch assertion, and both repeated in the isolated run. Unlike the inspection Exit test, these cases do not inject the isolated in-memory session fixture. The test simulator's persisted global preference was Smart Cube; the unchanged Timer can also restore input mode from its session. The actual failing view branch was not established. A follow-up should make the input/session fixture deterministic and then exercise the original gesture assertions, not relax them.

## Physical verification and release-note boundaries

1. Profile cold launch, warm resume, first valid scramble plus diagram, and first/repeated tab mounting with real stores. Separate time to first frame from time to a usable Timer.
2. Profile Data history and chart selection at large sizes, SQLite session count costs across many sessions, and time/peak memory during session switching or cancellation.
3. Capture 2×2 and 3×3 rapid turns, reversals, guidance and final cube states; measure present-frame timing and idle power separately, including concurrent Battle move streams.
4. Verify cold/offline/refresh flows and parse vs. network latency with a representative long WCA profile. Compare Algs first load, list scrolling and Learn state updates.

Safe future release-note wording: “Reduced solve-trend preparation time by about 19% for 10,000 and 100,000 solves in a simulator benchmark.” “Reduced repeated learning-status processing in large algorithm sets.” WCA parser and 2×2 checkpoint benchmarks describe internal computation and should not be advertised as faster online loading or Bluetooth responsiveness.

## Changed files

| Area | Files |
| --- | --- |
| Chart computation | [SessionPerformanceLineChart.swift](../CubeFlow/Views/iPhone/SessionPerformanceLineChart.swift), [SolveMetrics.swift](../CubeFlow/Views/Shared/SolveMetrics.swift) |
| Algs | [AlgSupport.swift](../CubeFlow/Views/iPhone/Algs/AlgSupport.swift) |
| Guidance | [CubeStateEquivalence.swift](../CubeFlow/Views/Shared/CubeStateEquivalence.swift) |
| WCA profile parsing | [WCAResultsService.swift](../CubeFlow/Views/Shared/WCAResultsService.swift) |
| Tests | [PostReleasePerformanceTests.swift](../CubeFlowTests/PostReleasePerformanceTests.swift) |
| Documentation | This closeout and [ROADMAP.md](../ROADMAP.md) |

Pre-existing local changes to Xcode project metadata, the shared and personal schemes, and eleven untracked screenshots are outside this pass. No files were staged; no Git publication, version change, build archive, or physical-device operation was performed.
