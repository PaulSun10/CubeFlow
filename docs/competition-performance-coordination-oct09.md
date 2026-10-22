# Competition Loading, Original Titles And Shared Results

2026-10-09. Continued the existing dirty worktree at `c551de97`. No reset,
commit or push. This report supersedes the earlier Competition title and
published-results presentation decisions, not the preserved provider work.
Timer was frozen throughout this Competition goal; its inherited changes remain.

## Actual Navigation Measurements

These are actual XCUITest searches and competition-row taps in the running app,
not isolated service benchmarks. The endpoint is the mounted rich Info document.
Device: iPhone 18 Pro simulator, iOS 27, Debug, English, same test method.

| Navigation | Before observed | Latest observed |
| --- | ---: | ---: |
| Beijing Autumn Rivalry, first measured opening | 2.578 s | 1.910 s |
| Toronto Weeknights I, first measured opening | 2.155 s | 1.727 s |
| Beijing, immediate reopen | Not recorded | 2.004 s |
| Toronto, immediate reopen | Not recorded | 1.962 s |
| Published Results selection to first row | Not recorded | 1.491 s |
| Published Scrambles selection to first row | Not recorded | 1.528 s |

Important qualifications:

- These intervals include XCTest finding/tapping/idle synchronization and its
  approximately one-second existence polling. They are not frame-accurate timings.
- Before Beijing was already a persisted full-detail cache hit. Latest Info used
  persisted resource caches, but published Results/Scrambles were fetched afresh
  after app launch. Before Toronto fetched its HTML; latest Toronto reused Info.
  Do not attribute the entire difference to faster parsing or faster networking.
- The first new-resource-cache cold Beijing opening was **3.998 s**, before the
  subsequently identified competitors main-thread parse was moved off-thread.
  A subsequent final-version run with the parsed detail cache set aside is
  recorded separately below. No blanket network improvement claim is made.
- The owner's original 8-20 second waits were not reproduced in the retained
  baseline navigation run. We established specific blocking/repeated-work paths,
  not a retrospective accounting of that uninstrumented run.
- One intermediate run spanned host sleep, simulator shutdown and an unavailable
  competition list. Its multi-minute launch/wait timings were discarded.

Evidence: `/tmp/cubeflow-competition-performance/NavigationBaseline.xcresult`,
`NavigationResumed.xcresult`, `FocusedCorrectionsFinal.xcresult`, and final
`FinalLeaseAndUI.xcresult`. Matching console logs and exported diagnostics are
retained beside them. `detail-first-visible` traces based on destination creation
are not used as tap-to-visible timings: SwiftUI may construct destinations early.

### Final-Version Cold App-Detail Cache Run

`ColdDetailNavigation.xcresult`, **one real UI test passed**, using
`test-without-building` against the already compiled final simulator app,
including the archived-Live gate correction. No production code changed.

| Navigation | Cold app-detail cache | Immediate reopen |
| --- | ---: | ---: |
| Beijing Autumn Rivalry | 1.873 s | 1.978 s |
| Toronto Weeknights I | 4.697 s | 1.952 s |

Results selection was 1.536 s; Scrambles 1.947 s, including automation overhead.
The original parsed detail cache was temporarily set aside, then restored
byte-for-byte: SHA1 `36fb18c3032d20d04226c44d4b21b7839bd167af` before and after.
The newly generated cache is retained separately with the test evidence. No
simulator erase, saved-data deletion, or unrelated cache cleanup was performed.
HTTP/CDN caches were not reset; "cold" here means the app's parsed detail cache
and fresh per-launch memory, not a claim about every external cache layer.

The slower Toronto cold load was primarily remote waiting: main HTML **3017 ms**,
Results **2826 ms**, concurrently. Info completed at **3203 ms** from coordinator
start; all sections at **3313 ms**. Rich-document worker parsing was **11-26 ms**,
`main=no`; one main-HTML response served Info and Schedule. Reopen Info completed
at **65 ms**, all sections at **175 ms**. This trace supports a remaining provider
latency limitation, not another multi-second synchronous document parse.

Cold Beijing HTML requests ranged **220-333 ms**; the 2.7 MB competitors response
took **526 ms**, with **40 ms** worker parsing. Info completed at **460 ms**;
all sections at **2400 ms**, independently of Info, dominated by the official
Results response at **2025 ms**. Scrambles fetched once after publication validation.

## Demonstrated Costs And Corrections

1. The previous full-detail path coupled useful Info to unrelated sections and
   used include-Live/include-competitors full-detail variants. The parent now
   merges independently completed resources; there is no whole-page barrier.
2. Rich HTML semantic parsing occurred synchronously while constructing SwiftUI
   content and repeated on reconstruction. The baseline recorded a **226.89 ms**
   main-thread parse plus repeated smaller parses. Immutable semantic elements
   now parse on a detached worker and are shared/cached. UIKit, fonts, selection
   and layout remain main-actor work. Final traces explicitly show `main=no`.
3. The first coordinated cold run exposed Beijing's **2.7 MB competitors HTML**
   parsing on MainActor, with about **1.1 s** occupied by competitors processing.
   The existing parser now runs off-thread; the count reuses the parsed previews
   instead of parsing Nuxt state again. Final worker: **38.85 ms**, 370 people,
   `main=no`. This is not a same-cache/same-temperature CPU speedup benchmark.
4. WCA Info and schedule share the same main HTML request. Immutable WCA Info
   parsing and schedule decoding run off-thread; the full original native Info
   presentation remains, rather than replacing it with a small summary.
5. Published Results and Scrambles previously had separate destination-driven
   loading. Official publication remains authoritative; once validated, the
   parent prefetches Scrambles into its owned observable store. Selecting either
   destination reuses loaded data, not a second transport/parse/model operation.
6. Underlying request pools track consumers. One departing section releases only
   its lease; the last departing consumer cancels remote work. A parent can join
   a Scrambles request started by a section and survive that section's cancellation.
   Superseded/cancelled identities do not assign state or poison replacement caches.

In the final real run, whole-lifecycle completion from coordinator start was
**2.382 s Beijing / 0.681 s Toronto**, including published Scrambles. Reopens
completed the lifecycle in **246 / 179 ms**. These are app-side lifecycle timings,
not replacements for the actual tap measurements above.

Provider latency still varies: Beijing Results **2021 ms**, 709,842 bytes;
Toronto Results **258 ms**, 37,745 bytes; Scrambles **186 / 195 ms**. Beijing
Results decode/model took **14.23 / 6.64 ms**; Toronto **1.94 / 0.45 ms**.
The UI does not wait for these unrelated requests to render Info.

## Coordinated Loading Policy

- China starts About, Regulations, Travel, Schedule and historical Registration
  concurrently. Available Competitors joins when capabilities are established.
- WCA starts complete Info and Schedule together, sharing their HTML. Historical
  Register/Competitors load only when available and applicable, not when hidden
  by a confirmed published lifecycle. Public WCIF is preferred; HTML is fallback.
- Past competitions validate official publication concurrently with Info.
  Published Results trigger Scrambles; unpublished/failed publication can load
  available Live without redefining publication. Future/current competitions
  request Live concurrently. An explicitly opened Live archive starts Live
  immediately even when official published Results exist.
- Publication retry uses the owned parent task lifecycle rather than refreshing
  only the Results store and leaving Scrambles outside the lifecycle.
- Each resource merges only its fields, independent of completion order.
  Registration/competitors/Live results cannot erase previously rendered Info.
- Keys separate provider, competition, locale and resource. Static parsed content
  retains the existing six-hour persistence; Live memory lifetime is 15 seconds,
  Competitors 60 seconds. Recent shared HTML is bounded to 24 entries/60 seconds;
  semantic documents to 32 entries. Published service caches retain existing
  one-hour published / 60-second unpublished lifetimes and bounded capacities.
- Pull-to-refresh, provider validation, canonical identity, historical China
  sections and the existing real-time Live subscription shell remain intact.

## Restored Title And Info

Git history `02475bc4` supplied the actual original `fittedLargeTitleSize` routine.
It is reused directly: bold, maximum `min(preferredLargeTitleSize, 30)`, floor
22 pt, one-point fitting steps, width `max(screenWidth - 56, 220)`. No new UIKit
binary-search fitter or custom small principal toolbar title is introduced.

The in-content Large Title is again **below primary navigation**, for both
providers. Its original floor remains; exceptionally long titles can wrap rather
than shrink to an unreadable single line. The existing separator/scroll-driven
transition controls only native inline title visibility. UIKit owns inline font
and layout; mounted tests measure **17 pt**, with no custom `titleView`. The
navigation-bar appearances are restored on exit.

Actual Toronto UI retains General Info, organizers/delegates/contact/location
links, image/document content, Events with formats/rules, Schedule with calendar
and table controls, and additional organizer-authored Info sections. Native rich
links/tables/images/selectable text and event/schedule parsers were reused.

Screenshots inspected after the existing section crossfade completed:

- [China body Large Title](assets/competition-performance-oct09/real-info-CN.png)
- [WCA complete Info and body Large Title](assets/competition-performance-oct09/real-info-CA.png)
- [Native inline title](assets/competition-performance-oct09/real-wca-inline-title.png)
- [WCA Events](assets/competition-performance-oct09/real-wca-info-events.png)
- [WCA Schedule](assets/competition-performance-oct09/real-wca-info-schedule.png)

## Actual Live List And Card Reuse

The existing `CompetitionWCALiveRoundDetailView` list/card implementation was
extracted into `CompetitionResultExperience` and `CompetitionResultCardState`.
The real Live shell still owns its subscriptions, lifecycle and deep links.
Published canonical rows use presentation-only adapters: no fake Live person IDs,
open rounds or advancement state, and no Live transport for published people.

Published modes/event/round selectors remain. The list shows rank/name/statistics,
not all five attempts. Tapping opens the same Live-style card, then All Results,
then the existing official `WCAProfileView`. Attempts remain inside the card;
rare-format and zero-average formatting use official published semantics.

- [Published list](assets/competition-performance-oct09/real-published-results.png)
- [Competitor card](assets/competition-performance-oct09/real-published-card.png)
- [All Results](assets/competition-performance-oct09/real-published-all-results.png)
- [Official profile destination](assets/competition-performance-oct09/real-wca-profile.png)
- [Scrambles and E1](assets/competition-performance-oct09/real-published-scrambles.png)

The profile screenshot proves navigation into the existing profile destination,
not completion of its independent remote profile request.

Chinese mean labels now read "平均" in both localizations. Extra scrambles use
E1/E2 while official strings, normal numbering, grouping/copy/diagrams remain.
Live schedule dots use the matching event-round/group activity's official room
color (first scheduled colored block for a round summary), not date-based green
or blue. Invalid/missing colors fall back to neutral secondary; r1 cannot match r10.

Primary references inspected before implementation: the official WCA
[competition controller](https://github.com/thewca/worldcubeassociation.org/blob/main/app/controllers/api/v0/competitions_controller.rb),
[WCA Live components](https://github.com/thewca/wca-live/tree/main/client/src/components),
and CubingChina's competition controller/current public detail structures.
Retained reference snapshots are in the evidence directory's `references/`.
Existing CubeFlow provider extractors and UI were reused; no GPL implementation
code or privileged registration data was imported.

## Verification And Boundaries

- FinalLeaseAndUI: **17 focused unit tests + 1 real UI test passed**. Covers
  resource cache/coalescing/failure/identity/freshness/cancellation, out-of-order
  merging, rich semantics, loading policy, schedule colors, labels, presentation
  adapters, card navigation, full-size Scrambles, slow-network section switching,
  and parent-joins-section cancellation. 618-row fixture first row: **123 ms**.
- FocusedCorrectionsFinal additionally passed the 24 mounted native-title
  scenarios and original fitter/independent-loading tests. In the delayed-section
  fixture, Info completed around **174 ms**, other-section completion **1224 ms**;
  first visible host **43 ms**, remote-wait worst heartbeat **61 ms**.
- The post-build archived-Live audit correction passed **16 focused tests** in
  `ExplicitLiveGuard.xcresult`: 14 loading/state tests and two publication/navigation
  preservation tests. The app compiled successfully for the simulator with this
  final correction. The owner subsequently approved one additional final generic
  iOS build, which passed with this correction included.
- Early runs exposed compile/test assumptions and the lease edge case. Those
  failures were corrected and rerun; they are not counted as successful runs.
- Final authorized generic iOS Debug build: **BUILD SUCCEEDED**, unsigned,
  `generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO`, log
  `/tmp/cubeflow-competition-performance/authorized-final-generic-ios-debug.log`.
  This build covers the final archived-Live gate. Two generic-device builds were
  performed in total: the original successful build and this explicitly approved
  additional build. No production edits or test reruns followed the final build.
  Only the existing App Intents metadata-extraction warning was reported.
- `git diff --check` passes. No unrelated broad suite, commit, push or project
  configuration edit. Frozen Timer SHA1: `31859e9f86ed1007f52957c356ba874845d583d7`.

Changed areas: CompetitionService/resource and semantic stores; CompetitionTabView
loading/title/shared list-card; CompetitionNativeDetailTitle; PublishedCompetition
transport/observable stores/adapters/view; two published localizations; focused
Competition tests, UI navigation test, this report and evidence images. Inherited
China adapter/colors/navigation/identity/schedule and Timer work remain preserved.

Remaining acceptance: cold navigation on the owner's network and physical device;
physical long-title/collapse and rapid section switching in light/dark/Dynamic
Type; publication transition/retry under slow or failing network; actual ongoing
Live advancement/dialog/deep-link sessions and missing-color fallback; older
supported iOS. Timer hardware-touch validation is separate and not claimed here.
