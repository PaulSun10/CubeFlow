# Timer Touch, Competition Loading, and Adaptive Titles

Date: 2026-10-09. Continued the existing dirty worktree; no commit or push.
This report supersedes only the title decision in the previous Competition
closeout. Existing navigation, semantic colors, official publication, Results,
Scrambles, historical Info sections, and Live behavior remain intact.

## 1. Recovered Large Title, Native Inline Title

The owner's final STEER requested the previous CubeFlow adaptive Large Title,
not the new fitter initially introduced during this pass. Git history identifies
that implementation in commit `02475bc4`, in
`CompetitionNavigationBarFontConfigurator.swift`, and it still exists in HEAD.

The original `fittedLargeTitleSize(for:baseSize:)` is now shared directly, rather
than copied or replaced. Its algorithm is unchanged:

- Bold font; maximum `min(preferredLargeTitleSize, 30)` points.
- Available width `max(UIScreen.main.bounds.width - 56, 220)` points.
- Measure the complete name, decrement by one point until it fits, floor 22pt.

`CompetitionNativeDetailTitle` calls that exact routine and applies the result
only to large-title font attributes. It clears the list's inherited inline font
override and leaves native inline text, layout, and collapse animation to UIKit.
The old principal toolbar VStack, 14pt text with 0.35 minimum scale, subtitle
controls, and duplicate in-content competition title are not restored. Ordinary
WCA and CubingChina use the same native navigation-title path. Existing trophy
information remains available. The original appearances are restored on exit.
Compact scroll-edge appearance is covered from iOS 15, its actual availability.

The earlier binary-search fitter introduced in this pass has been removed.
Native inline titles measure 17pt in the mounted simulator checks. Changing
Info/Results/Scrambles does not introduce a custom titleView or change the name.
The native collapse mechanism is retained, not replaced by a custom fade.

The recovered original policy has a 22pt floor: exceptionally long names can
still exceed a single line. This pass does not silently shrink below that floor
or claim arbitrary-length names fit. The full navigation item title is retained.
The original screen-width convention is intentionally unchanged by the STEER.

## 2. Timer Root Cause and Minimal Fix

A correctly sized touch surface was not enough. The Timer's ZStack places
read-only Split/Cards statistics above the zero-distance DragGesture surface.
The Cards glass/background can consume touches before the Timer gesture begins.
This is a demonstrated delivery/hit-testing problem, not evidence that the
Timer state machine rejected an accepted touch.

Before the fix, actual XCUITest digits/side/below/short-idle touches worked, but
Cards' blank statistics point `(35, 714)` did not start the Timer:
`before=0.851`, `after=0.851`. The test failed at that exact point.

The fix makes the entire read-only statistics surface, including its glass,
non-hit-testable only when `enteringTimesWith == "timer"`. It passes through to
the existing Timer gesture. Other input modes retain their prior hit testing.
The interactive scramble diagram, selectors, controls, geometry and visuals are
unchanged. No high-priority gesture or replacement recognizer was introduced.

The same physical screen coordinate in the simulator starts successfully after
the fix. With Hide Elements While Solving disabled, the test also stops through
that foreground surface and reaches result confirmation. Cancel avoids saving
test solves. Classic, Split and Cards digits, side/below blank regions, short
idle (3 seconds), and repeated short taps are covered.

DEBUG instrumentation, opt-in via `timerTouchDiagnostics`, records gesture
tracking/reset, changed/ended events and points, and running/pressing/ready/
inspection state before and after the existing state handlers. An accessibility
identifier makes digit assertions stable. Gesture lifetime/cancellation, state
functions, hold/start/stop delay, inspection, penalties, Smart Cube timing,
readiness, and solve persistence behavior were not redesigned.

Simulator evidence proves this interception bug and its fix. It does not prove
that all long-idle, background/wake, cancellation, or hardware-touch failures
share that cause or are now resolved.

## 3. Competition Loading Diagnosis and Changes

### Measured Bottlenecks

1. First useful Info waited for all unrelated detail sections and Live lookup.
2. China Live/optional competitors requests started after the other page requests.
3. The initial progressive WCA implementation parsed the same document twice on
   MainActor: 208.53ms + 154.85ms on real WC2025 HTML; schedule decode/transform
   added 59.17ms on MainActor.
4. A fresh SwiftUI test-host/navigation mount still costs roughly 400-500ms.
5. Remote latency remains substantial, particularly WCA. It is not a CPU problem
   that can be erased by local caching or a loading animation.

### Implementation

- Start overview and complete loaders concurrently, joining the existing
  in-flight main HTML request. Assign useful Info as soon as it is parsed.
- Retain existing same-identity content during reload. Guard competition/language
  identity and cancellation to prevent late assignment to another destination.
- Keep unreceived Rules/Travel/Schedule/Register loading, rather than labeling
  them unavailable just because the initial overview is partial.
- Start the existing independent China Live/optional competitors requests in
  parallel with other pages. No new endpoint, subscription or Live logic.
- Move semantic China About/Rules/Travel/Registration parsing to worker tasks.
  Legacy fallback and China schedule work are not claimed to be entirely off-main.
- Add a bounded four-document WCA parse actor: exact HTML, language and current
  time-zone key; in-flight coalescing; detached parsing; generation-safe clear.
  This shares computation, not stale HTTP data. Changed content is reparsed.
- Move WCA schedule JSON decoding and transformation off MainActor; preserve
  event rounds, room/venue/time zone, cutoff/limit/advancement and child-group rules.
- Stop China canonical WCA ID extraction at the first valid page.
- Keep official publication authoritative in the existing published-data store.
  Overview content cannot establish publication. Existing network/detail TTLs,
  refresh policy and canonical/provider/language cache keys are unchanged.

### Measurements

All values below are milliseconds unless shown otherwise. Service timings mean
model availability, not finished rasterization. URLSession response-await timing
includes actor resumption, not just on-wire transfer. DEBUG body construction
measures SwiftUI value construction, not the entire rendering/layout pipeline.

| Measurement | Before / earlier stage | Final measured implementation |
| --- | --- | --- |
| Controlled main page ~30ms, Regulations 1.1s | Useful Info formerly blocked until complete: 1136.14ms | Useful Info 33.19ms in same controlled load; complete still 1136.14ms |
| Repeated controlled cold run | Complete 1217.34ms | Useful Info 78.33ms; warm reopen 0.101ms |
| Real China cold service load | Complete 1328.15ms | Useful 775.33ms; complete 961.18ms |
| Real China warm service load | Complete 0.238ms | Complete 0.116ms |
| Real WC2025 before WCA worker/coalescing | Useful 3107.52ms; complete 4066.22ms | Useful 2671.04ms; complete 3011.01ms |
| WC2025 main HTML await | 2701.31ms, 654556 bytes | 2450.26ms, 654556 bytes |
| WC2025 document parsing | Two MainActor parses: 208.53 + 154.85ms | One off-main parse: 186.01ms |
| WC2025 schedule JSON + transform | 59.17ms MainActor | 64.89ms off-main |
| Real WC2025 warm service load | Complete 0.194ms | Complete 0.161ms |
| Synthetic identical WCA document | Main baseline 72.67ms | Off-main 64.93ms; cached parse 0.448ms; output identical |

Real-provider samples are not a controlled network A/B benchmark. Network
variation contributes to the elapsed differences; these numbers do not prove
faster internet/provider response. Controlled early-vs-full availability,
request counts, parse coalescing, output equivalence and off-main execution are
the direct evidence for the optimizations.
The controlled "formerly blocked" number is the measured complete-load barrier
from the same run, not a separate original-binary benchmark.

Baseline China main response took ~949ms; other sections ~842-908ms, followed by
a serial ~112ms Live request. Final China requests ran concurrently: main ~734ms,
other sections ~579-731ms, Live 404 ~543ms (a valid unavailable response for this
ended event). No Live data was fabricated.

The preliminary Toronto2026 probe returned empty data and is not counted as a
successful WCA load. Subsequent actual WCA samples used the verified WC2025 ID.

Actual mounted cold-host measurement: first visible ~400ms; initial-mount main
heartbeat ~500ms; subsequent remote-wait heartbeat ~166ms. A warm-host earlier
run was first-visible ~46ms/heartbeat ~74ms. Cold graph mounting remains a
measured residual, not an optimization claimed complete. Screenshot rasterization
is excluded from the remote-wait heartbeat assertion because it is synchronous
test work. No full Instruments CPU-stack attribution was performed.

## 4. Focused Verification

Artifacts are under `/tmp/cubeflow-touch-loading/`.

- `Focused.xcresult`: 2 schedule-clock, 13 China adapter, 25 published integration
  tests passed. This overall run also contained one new heartbeat-test failure
  caused by synchronous screenshot work; it is not described as an all-green run.
- `TouchDiscrimination.xcresult`: intentionally exposed the pre-fix Cards touch
  failure. Retained as before-fix evidence.
- `FinalFocused.xcresult`: 7 passed, zero failures, including actual Timer
  XCUITest and mounted titles. It predates the final WCA worker implementation.
- `FinalParser.xcresult`: 3 passed, zero failures after WCA worker changes:
  cold-host mounted responsiveness, real-provider probe, WCA sharing/off-main.
  An earlier `ParserFocused.xcresult` assertion included fresh-host mounting in
  the remote-wait heartbeat. It was corrected by measuring those phases
  separately, while retaining/reporting the real cold-mount cost.
- `ScheduleWorker.xcresult`: 2 passed, zero failures: explicit XCTest schedule
  worker fixture and progressive/warm/reopen/failure test. A separately requested
  Swift Testing filter did not execute and is not counted.
- Final STEER title verification: 24 mounted China/WCA Info/Results/Scrambles
  states (light/dark, expanded/inline) plus inherited-font test passed. The new
  helper initially asserted UIKit's default font was nil; UIKit materializes
  its 17pt default. The corrected test compares native descriptors instead.
  `RestoredTitles.xcresult` retains the two passing mounted/font tests and that
  initial helper assertion failure. `RestoredTitleHelper.xcresult` passed the
  corrected helper (1 test, zero failures). The stalled failure-diagnostics
  subprocess of the former run was stopped after tests finished; test execution
  and the simulator itself were not interrupted. Screenshots are below.

There are 48 distinct focused tests with passing relevant runs (40 existing
Competition regressions, 7 Timer/loading/title unit tests, 1 actual Timer UI
test), not one monolithic all-green 48-test invocation. No broad unrelated suite.

Coverage includes one shared main-page request, bounded/reused parsing,
content/locale invalidation, same competition reopen, another competition then
return without extra request, failed HTTP responses, mounted slow sections,
official publication/canonical identity and cancellation, and the existing
slow Scrambles/tab-switch regression. Live-provider probes are opt-in, not
routine network tests. No solve records were persisted by the new Timer UI test.

## 5. Files Changed by This Pass

Inherited dirty files are preserved, including untracked Competition files and
reports. Task-specific changes:

- `CubeFlow/Views/Shared/CompetitionService.swift`
- `CubeFlow/Views/Shared/CubingChinaDetailAdapter.swift`
- `CubeFlow/Views/Shared/CompetitionLoadingTrace.swift` (new)
- `CubeFlow/Views/Shared/CompetitionWCAInfoParseStore.swift` (new)
- `CubeFlow/Views/iPhone/CompetitionTabView.swift`
- `CubeFlow/Views/iPhone/CompetitionNativeDetailTitle.swift`
- `CubeFlow/Views/iPhone/CompetitionNavigationBarFontConfigurator.swift`
- `CubeFlow/Views/iPhone/TimerTabView.swift`
- `CubeFlowTests/PublishedCompetitionIntegrationTests.swift`
- `CubeFlowTests/TimerCompetitionReliabilityTests.swift` (new)
- `CubeFlowUITests/TimerTouchReliabilityTests.swift` (new)
- This report.

No project file, deployment target, dependencies, Smart Cube/Combined/BLE,
Replay, reconstruction, Live advancement, glyph metrics, unrelated Explore,
Rankings, Records, or algorithm work was changed by this pass.

## 6. Final Build and Screenshots

`git diff --check` passed. Touched untracked files were checked as well, including
this report. One and only one generic iOS Debug build was run, successfully:

```sh
xcodebuild build -project CubeFlow.xcodeproj -scheme CubeFlow \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /Users/paulsun/Library/Developer/Xcode/DerivedData/CubeFlow-goanodogbuagehdsqrslicdbjmha \
  CODE_SIGNING_ALLOWED=NO
```

[Build log](/tmp/cubeflow-touch-loading/generic-ios-debug.log):
`** BUILD SUCCEEDED **`, no compiler errors. The only build warning was skipped
AppIntents metadata extraction because no AppIntents.framework dependency exists.
The existing unconditional TNoodle sign-script scheduling note is not a failure.
No production source changed after this build. Minimum deployment remains iOS 15.

Actual final SwiftUI screenshots inspected after the STEER, not mock designs:

- [China recovered large title](/tmp/cubeflow-touch-loading/restored-title-screens/954F175F-915E-4309-9764-168AEE8DFFC4.png)
- [China native inline title](/tmp/cubeflow-touch-loading/restored-title-screens/8F2922BE-C321-483F-8336-EE9527A51844.png)
- [WCA recovered large title](/tmp/cubeflow-touch-loading/restored-title-screens/B5D9EDD8-6EA5-4352-8D00-DD5F4DBDBA4D.png)
- [WCA native inline title](/tmp/cubeflow-touch-loading/restored-title-screens/1EF676A9-BCC4-4BC7-AD90-971F8F02F627.png)
- [China dark Scrambles expanded](/tmp/cubeflow-touch-loading/restored-title-screens/6B7A7525-5F16-4B94-8C9C-6A214DDAF212.png)
- [WCA dark Scrambles inline / last row](/tmp/cubeflow-touch-loading/restored-title-screens/771A76DB-1C4A-459F-95E8-EECFA0D7AA62.png)
- [Timer Cards blank-statistics touch after fix](/tmp/cubeflow-touch-loading/final-screenshots/5B06EEFA-E9D8-4877-ACC1-192F12F47F99.png)

The fixture name fits without ellipsis in the expanded title; inline text is
normal native size and has no section subtitle/duplicate title. Existing China
semantic colors, international accent, full-size scramble wrapping and bottom
scroll clearance remain visible. The mounted tests exercise scrolling between
expanded/inline endpoints; frame-by-frame physical collapse/flicker acceptance
is still needed. Timer screenshots show the actual simulator run (its unsigned
TNoodle runtime is unavailable); they are touch evidence, not scramble-engine
validation. Earlier progressive Info screenshots show content before completion
but are not used to prove navigation-title appearance.

## 7. Physical Acceptance Still Needed

1. On an iPhone, Classic/Split/Cards digits and blank statistics touches for
   start and stop, short repeated taps, long idle, background/wake, and with
   Hide Elements While Solving both on and off.
2. Verify hold-to-ready/Start Delay/Stop Delay, inspection +2/DNF, result
   confirmation, and alternate input modes remain unchanged.
3. Both providers: long titles, native collapse, rapid Info/Results/Scrambles
   changes, push/pop back to list, rotation, narrow devices, larger text, and
   an iOS 15-era device. Extremely long titles retain the original 22pt floor.
4. Real network: cold/warm/reopen/another competition, slow/failing section,
   refresh, published Results/Scrambles, historical China Info sections and
   a genuinely live competition. Simulator service probes do not prove full
   physical publication/rendering or live-hardware behavior.
