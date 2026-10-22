# Guangzhou Loading Tail - Clarified Acceptance Follow-up

2026-10-11. Extends the preserved dirty worktree. No commit, push, project configuration change, unrelated UI change, or Smart Cube/Timer behavior change.

## Corrected Measurement Definition

The owner clarified that **Info appeared, but the loading indicator continued** during the original approximately 25-second occurrence. That is a whole-loading-session measurement, not a 25-second delay before useful Info. This clarification supersedes that interpretation in the earlier [acceptance report](competition-timer-acceptance-oct11.md).

The original event still has no contemporaneous per-request trace, so these results do not retrospectively account for all 25 seconds or prove a 25-to-7-second causal speedup.

## Proven Avoidable Dependency

On a cold China detail destination, `detailContent.hasCompetitorsLink` initially equals false. The initial loading plan therefore omitted Competitors. Only after About completed did `historicalResources` add it. The toolbar correctly remained busy for that pending work.

That serialization was unnecessary: the existing provider sets `hasCompetitorsLink` for China independently of About HTML, and existing navigation exposes Competitors before publication and inside published Info. The fresh baseline trace confirms the cost:

- Info's useful data completed at 3,445 ms from coordinator start.
- Competitors then required another 2,470 ms, including its roughly 2.15 MB response and off-main parsing.
- All sections completed at 5,991 ms. Results/Scrambles had already finished; Competitors was the last section.

The fix makes China Competitors part of the initial concurrent resource plan, alongside About, Regulations, Travel, Schedule and Register. Discovery's existing scheduled-resource set still prevents a duplicate request when About arrives. The obsolete `knownCompetitors` argument was removed from the internal plan and its callers.

The indicator is **not** hidden or ended when Info appears. It still tracks every real pending detail/publication/scramble/psych request. Tickets still require the explicit provider flag; implicit archived Live remains gated; international loading policy, cache TTLs, cancellation and refresh generations are unchanged.

## Actual UI Results

Same real Guangzhou search/navigation method, same simulator and fresh-first-detail flag. Screenshot capture and AX-tree export were moved **after** the idle measurement so they no longer inflate its duration. These timings still include XCTest tap/idle synchronization and approximately one-second predicate polling.

| Interval | Fresh baseline, serial Competitors | Concurrent run | Concurrent repeat |
| --- | ---: | ---: | ---: |
| Tap to useful Info | 4,881.63 ms | 5,843.82 ms | 5,707.99 ms |
| Tap to whole-session idle | 7,968.07 ms | 6,956.64 ms | 6,853.12 ms |
| Loading after Info appeared | 3,086.40 ms | 1,112.79 ms | 1,145.11 ms |
| Prepared Results selection | 1,604.97 ms | 1,556.42 ms | 1,609.01 ms |
| Prepared Scrambles selection | 1,555.01 ms | 1,538.99 ms | 1,581.90 ms |
| Immediate reopen to Info | 1,943.14 ms | 1,943.91 ms | 1,997.29 ms |

Observed whole-session completion improved about 13-14%; the observed post-Info tail improved about 63-64%. **Info itself arrived later in both concurrent runs.** These observations are not a claim of faster first-visible Info or of uniformly faster networking. The first concurrent trace recorded About delivery around 4,890 ms, compared with around 3,260 ms in the baseline; broader concurrency and remote variation cannot be separated causally from these few samples.

The first concurrent trace recorded all-section completion at 5,518 ms, with useful Info at 5,081 ms: the coordinator's actual remaining tail was about 436 ms, rather than the baseline's 2,545 ms. The UI polling floor means the visible after-Info measurements are coarser than those internal intervals. No pending work was discarded to obtain the result.

This corrects a real remaining loading-coordination dependency and reduces the clarified symptom in the measured runs. A consistent major total-loading speedup, or an exact explanation of the historical 25-second network occurrence, is still not established.

## Verification

- `WholeSessionBaseline.xcresult`: one real navigation UI test passed before the production fix, using the corrected whole-session measurement.
- `WholeSessionConcurrent.xcresult`: 17 loading tests, five refinement tests and one real navigation UI test passed, 23 focused methods total.
- `WholeSessionConcurrentRepeat.xcresult`: the same real navigation UI method passed using `test-without-building`; no new simulator build or broad suite.
- New deterministic regression: China Competitors starts before Info; remains pending after all other initial sections finish; only its completion ends loading. Also verifies one initial request, no speculative Tickets/Live, and no new international Competitors request.
- Previous actual light/dark UI work is untouched. The latest [real Guangzhou Info screenshot](assets/competition-acceptance-oct11/guangzhou-concurrent-loading-info.png) was inspected and confirms preserved navigation, adaptive body Large Title and native Info content.
- `git diff --check` passes. The external `project.pbxproj` change remains preserved.
- The owner-authorized additional final unsigned generic iOS Debug build passed (`BUILD SUCCEEDED`, exit 0). Log: `/tmp/cubeflow-oct11/followup/authorized-tail-final-generic-ios-debug.log`.

Final build command:

```sh
xcodebuild build -project CubeFlow.xcodeproj -scheme CubeFlow \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /Users/paulsun/Library/Developer/Xcode/DerivedData/CubeFlow-goanodogbuagehdsqrslicdbjmha \
  CODE_SIGNING_ALLOWED=NO
```

Evidence is retained under `/tmp/cubeflow-oct11/followup/`: result bundles, diagnostic exports, request metrics, UI timings and screenshots. The previous successful generic build remains recorded separately; it is not incorrectly described as covering this later production change.

## Changed Files

- `CubeFlow/Views/Shared/CompetitionSectionLoading.swift`: cold China Competitors joins the initial plan.
- `CubeFlow/Views/iPhone/CompetitionTabView.swift`: removes the obsolete known-Competitors argument; existing initial loading flags follow the revised plan.
- `CubeFlowTests/CompetitionSectionLoadingTests.swift`: adds the pending-work/concurrent-start regression.
- `CubeFlowTests/CompetitionRefinementTests.swift`: updates the internal plan calls; existing ticket/international policy assertions remain.
- `CubeFlowUITests/CompetitionPerformanceTests.swift`: measures whole-session idle and post-Info tail before screenshot/AX export overhead.

Remaining physical acceptance: repeat the exact opening/refresh on the affected device/network and observe both Info arrival and final idle. If the long tail recurs, use the existing DEBUG per-resource/network traces to identify the request still pending; do not infer that the original 25 seconds were entirely caused by the removed serialization.
