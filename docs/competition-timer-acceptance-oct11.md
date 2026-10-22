# Competition, Timer and Explore Acceptance Pass - 2026-10-11

## Status and Preservation

**Later clarification and correction:** the owner confirmed the original 25 seconds concerned the loading indicator after Info appeared, not first-visible Info. The [loading-tail follow-up](competition-loading-tail-oct11.md) supersedes that measurement interpretation and the cold China Competitors scheduling described below; other completed work and evidence remain applicable.

This pass extends the existing dirty worktree; it does not replace the October 8/9 work. No commit, push, reset, project-file change, Smart Cube/Combined change, or timing-rule change was made in this pass. The restored original adaptive body Large Title, native inline title/collapse, complete provider-specific Info and existing navigation remain in place.

Loading ownership, dynamic Timer hit routing, native spectator tickets and the requested Explore/Results/Scrambles refinements are implemented. **The reported 25-second Guangzhou delay was not reproduced, and a substantial initial-load speedup is not established.** This limitation is not hidden by a loading indicator or a warm-cache benchmark.

## Real Guangzhou Navigation Measurements

Measurements use `CompetitionPerformanceTests.testGuangzhouTapToUsefulInfo`: real Explore search, the real competition row, then the mounted native Info document. The fresh-load diagnostic forces the first detail load to bypass CubeFlow's parsed caches without deleting user caches. Reopening uses the normal cache path. Measurements include XCTest tapping, app-idle synchronization and existence polling; they are not frame-accurate instrumentation.

| Measurement | Before | After run 1 | After acceptance repeat |
| --- | ---: | ---: | ---: |
| Fresh tap to useful mounted Info | 4,971.74 ms | 3,868.35 ms | 4,844.86 ms |
| Immediate reopen to Info | 2,037.55 ms | 1,983.52 ms | 1,909.08 ms |
| Whole coordinated lifecycle, busy to idle | Not measured | Not measured | 9,290.59 ms |
| Prepared Results tab to result row | Not measured | Not measured | 1,582.14 ms |
| Prepared Scrambles tab to scramble | Not measured | Not measured | 1,534.17 ms |

The whole-session measurement includes screenshot capture and automation waits, not just isolated network time. Info appears independently before that session finishes. Results and Scrambles were already loaded before their tabs were opened.

The first faster run cannot be attributed entirely to code. The repeat is close to baseline, confirming meaningful network variance. No claim of a 25-to-4-second fix or a consistent 22% speedup is justified.

### Measured Cost and Root-Cause Limits

- Baseline About HTML: 3,485 ms network, 257,079 decoded bytes; China parsing worker 18.67 ms; first useful data at 3,684 ms.
- After run 1 About HTML: 2,224 ms network; worker 16.84 ms; first useful data at 2,439 ms. Its URLSession metrics reported HTTP/1.1, a new connection, DNS 1 ms, connection 755 ms, TLS 391 ms, server wait 769 ms and transfer 647 ms. These phases are diagnostic, not an additive explanation of the entire UI measurement.
- Other after-run HTML requests were approximately 2.7-4.1 seconds. Competitors required a roughly 2.15 MB decoded response for 508 people; its parsing worker was approximately 44 ms. The first cold competitors request in the baseline was cancelled by navigating back, rather than evidence of a parsing stall.
- Baseline official Results fetched in about 1,610 ms, decoded in 33 ms and modeled in 25 ms. Scrambles fetched in about 640 ms, decoded in 15 ms and modeled in 16 ms.
- Traced SwiftUI body-construction samples were sub-millisecond. Rich-document and provider parsing use the existing off-main workers. Body construction is not a measurement of all layout/GPU work. Older `detail-first-visible` timestamps are lifetime-relative and cannot substitute for the UI navigation benchmark.

The observed initial-load critical path is remote About delivery, followed by native document mounting and automation overhead, not a 25-second MainActor parse. The exact cause of the user's 25-second occurrence remains unknown: this pass has no contemporaneous trace of that occurrence. DEBUG network and navigation diagnostics now make a future occurrence attributable without assuming the symptom was fixed.

The official website and CubeFlow do not request identical data: the website has a Nuxt shell/client flow; CubeFlow preserves native content parsed from provider pages plus official WCA publication data. A direct public competition-API probe returned about 19 KB compressed but still took about 3.52 seconds here, including 3.07 seconds before the first byte. Switching endpoints alone is not demonstrated to meet the website's reported one-second experience. No speculative provider rewrite was introduced.

Sources: [official Guangzhou page](https://cubing.com/competition/Guangzhou-Grand-Open-2026), [public competition API](https://api.cubing.com/competitions/Guangzhou-Grand-Open-2026).

### Follow-up Critical-Path Audit

After the final app build, a read-only follow-up checked two possible optimizations rather than applying them speculatively. Production source was not changed and the successful app build remains applicable.

- Decoding the retained About SSR state confirms that it repeats organizer Information, Regulations and Travel documents, but contains **no Schedule or registration/Competitors rows**. The section pages also contain automatic rendered content. Passing About HTML to the existing section parser would mix About sections into other destinations; using only its embedded documents would omit automatic sections. This is not a safe wholesale replacement for the existing complete section loads.
- A Foundation/URLSession probe on the same Mac compared fresh sessions, matching mobile User-Agent and English locale, with About alone, five concurrent section requests, and five concurrent requests with elevated About task priority. Requests bypassed local HTTP cache; condition order was reversed in repetition two. Every response was HTTP 200 with the expected decoded length and HTTP/1.1 transport.

| About response time | Repetition 1 | Repetition 2 |
| --- | ---: | ---: |
| About alone | 3,429 ms | 1,708 ms |
| Five concurrent sections | 1,737 ms | 2,534 ms |
| Concurrent, About priority 1 / others 0.25 | 2,526 ms | 2,443 ms |

These are service-only diagnostics, not new user-visible performance measurements. They do not demonstrate a consistent contention or priority benefit. Serializing the other sections or adding a new priority transport would therefore be an unsupported change, not a verified fix.

The UI benchmark explicitly disables top-cuber previews, but the current product default is also false. The selected Info loading gate checks only its own pending resource and empty Info blocks; it does not wait for publication, Rules, Schedule or Competitors. Neither finding explains the unreproduced 25-second event.

The remaining diagnostic input is what stayed unavailable during that original event: Info content, the navigation transition, or only the refresh/loading indicator after Info became visible. The owner was asked to distinguish these paths. Evidence: `/tmp/cubeflow-oct11/followup/network-contention.swift` and `network-contention.log`.

## One Coordinated Loading Lifecycle

- `CompetitionLoadingLifecycle` owns one competition/language/generation and pending detail, publication, scrambles and psych work. The existing refresh button reflects the entire operation; the separate publication toolbar spinner is gone.
- Appropriate Info/Schedule and China Regulations/Travel/Register work starts concurrently with publication checking. Known China Competitors/Tickets can join immediately; otherwise their proven availability schedules them as soon as Info arrives.
- Official publication is checked before requesting Scrambles. Published archives do not make an unnecessary implicit Live request; explicit Live destinations retain their previous behavior. Unknown/unpublished competitions retain Live discovery.
- Each completed resource merges independently into the visible detail. Info does not await Rules, Competitors, publication or Scrambles. Parent-coordinated Scrambles never starts a second child-owned load.
- Existing request leases coalesce identical resources, keep another consumer alive when one navigates away, and cancel underlying work after the last consumer leaves. Competition, language and generation checks reject stale completion after refresh/navigation.
- Explicit refresh bypasses parsed caches and HTTP cached data; normal HTML requests use protocol caching rather than unconditionally ignoring HTTP cache. Section TTLs remain 15 seconds for Live, 60 seconds for Competitors/Tickets and six hours for static sections. Tickets are not persisted as an authoritative purchase state.
- Psych preview work joins the same pending set, is deduplicated within a generation and refreshed with it. Finishing detail/publication does not falsely clear still-pending psych work.
- Availability and failures stay source-specific; loading ownership does not redefine official publication or make unavailable destinations appear.

Main files: `CompetitionSectionLoading.swift`, `CompetitionTabView.swift`, `CompetitionService.swift`, `PublishedCompetitionView.swift`, `CompetitionLoadingTrace.swift`. Existing request pools, parsing adapters and publication/scramble stores are reused.

## Spectator Tickets

Official availability is **`showTickets == true`**, not `entryTicket`. Guangzhou's public state has `showTickets: false` despite `entryTicket: true`, so it must not gain an invented ticket destination.

The native ticket model reads the public ticket data already present in the official Nuxt response: localized name/description, integer-cent CNY fees, payable fee, validity dates, stock, sale window, purchase limit, competitor-only restriction and unavailable reason. Unknown availability reasons fall back to official-site guidance rather than guessing sale eligibility.

Unpublished China competitions expose the available Spectator Ticket entry in primary navigation; published competitions preserve it inside Info. International competitions do not acquire a China-only entry. Purchasing opens the official `/competition/<slug>/ticket` website. There is no in-app checkout or payment system.

The existing ticket teal is preserved: light foreground `#00786F`, dark foreground `#00D5BE`, selected background `#009689`, selected white text. These are the current official site's teal-family semantic tokens, not competitor-registration slate. Scrambles retains CubeFlow's sky accent: foreground `#0069A8` / `#00BCFF`, selected fill `#0069A8` / `#0077A8`. Primary unselected China rows remain adaptive primary text; secondary Info colors and ordinary international styling are unchanged.

Source: [official Guangdong ticket page](https://cubing.com/competition/Guangdong-Open-Revival-Rival-2026/ticket). Parser and availability fixtures cover the observed schema, including disabled entry and unsafe slug handling.

Files: `CubingChinaTickets.swift`, `CubingChinaTicketsContent.swift`, provider/content/navigation integration and English/Simplified/Traditional Chinese strings.

## Dynamic Timer Touch Routing

The remaining regression was the header's rectangular hit surface reserving empty space above the timer. The earlier Cards-statistics fix is preserved, but it alone did not release empty header space.

Timer mode now collects anchors for the actual rendered input/event selectors, scramble control, next-scramble button and applicable settings control. A measured union of those control rectangles owns only their real areas; the existing visible-header mask still clips the scramble. The underlying Timer gesture surface fills usable content, including gaps above the digits and between controls, without extending into system navigation/status/tab bars.

There is no fixed top reservation, scramble-height estimate or per-event hit rectangle. Changing layout/text updates the measured union. Other input modes keep their original full-header hit region. Hold, inspection, penalty, confirmation, persistence and Smart Cube/Combined gesture semantics were not changed.

Real UI tests start/stop in upper blank space and between selectors for Classic, Split and Cards, each in Scroll and Shrink Font mode. Event-menu and scramble-detail interactions do not start the timer. Tests cancel the resulting solves rather than adding records. The initial UI-test failure was an incorrect test expectation of `Done`; the existing sheet's actual button is `Close`. The expectation was corrected, not the production sheet.

Limit: the simulator's TNoodle bridge produced its existing unavailable/error text; these tests exercise real hit routing and geometry but are not proof of successful long-scramble generation. Deterministic geometry fixtures additionally cover long/wrapped scramble rectangles.

Files: `TimerScrambleViewport.swift`, `TimerTabView.swift`, `TimerDynamicHitRegionTests.swift`, `TimerTouchReliabilityTests.swift`.

## Explore, Records, Results and Scrambles

- Heading chevrons are immediately after their titles. Browse has no header chevron or enclosing surface; individual options and dividers sit on the page background. Hero navigation remains intact.
- Recent record rows reuse existing record badges and result formatting: badge on the far left, event/type plus bold result, competitor/country, competition and explicit source status.
- WCA Live provisional records and official WCA world-record history are merged by competition/event/WCA person/result type/value. Official data wins an identical achievement; distinct types/values remain separate. Official items use official result navigation, never fabricated Live IDs.
- The official history feed currently covers WR history, not every country's NR/continent CR history. Live still supplies its actual WR/CR/NR records. The WCA controller's region semantics do not justify calling the world feed an all-country record feed. Partial source failure retains relevant cached source data, reports a degraded cache state and does not persist a partial response as fully fresh success.
- Events use a 36-point base compact rounded rectangle with existing measured Cubing Icons ink-centering, plus a minimum 44-point hit region. Rounds/groups use compact rounded rectangles instead of large capsules. Dynamic Type and horizontal scrolling remain supported. Font registration occurs before glyph measurement.
- Event and round badges use actual official record tags, with WR > CR > NR priority. Upper-right reserved badge space avoids clipping and glyph overlap. No record is inferred from a raw time.
- Result rank-leading inset changes from 10 to 7 points; last-column trailing inset from 22 to 25; attempt detail aligns at 65 rather than 68 points. Existing badge geometry and competitor navigation remain unchanged.
- Champions/Podiums gain Best/Average labels without replacing their layouts.

Sources: [official WCA records controller](https://github.com/thewca/worldcubeassociation.org/blob/main/app/controllers/api/v0/results/records_controller.rb), [WCA Live source](https://github.com/thewca/wca-live). Protocol/data/presentation facts were inspected; no GPL implementation was copied.

### Advancement: Supported Evidence Only

Published results mark confirmed advancement only when a person appears in the next official main round of the same event. Final and B-final handling is explicit; absence from later results is not proof of elimination, and raw ranking is not used to fabricate possible advancement.

The existing WCA Live implementation actually uses green for confirmed and yellow for questionable advancement, not the requested description's green/blue. It is preserved. The existing China Live feed has no authoritative advancement flags. The inspected newer public China results API contained an `advancementStatus` field, but **all 223 Guangzhou 2x2 round-one rows had an empty value**. Those empty fields cannot support additional indicators. No China Live provider rewrite or guessed advancement was added.

Sources: [China Live rounds](https://api.cubing.com/competitions/Guangzhou-Grand-Open-2026/live/rounds), [China 2x2 round-one results](https://api.cubing.com/competitions/Guangzhou-Grand-Open-2026/live/results/222/1).

## Actual Rendered Screenshots

Screenshots are actual SwiftUI/simulator output, not mockups. Hosted fixture screenshots below use explicit sample data for deterministic rendering; the Guangzhou and Explore navigation screenshots use real public data.

| Evidence | Screenshots |
| --- | --- |
| Real Explore headings/records and Browse | [Records](assets/competition-acceptance-oct11/explore-records.png), [Browse](assets/competition-acceptance-oct11/explore-browse.png) |
| Results selectors and unclipped badges, hosted fixture | [Light](assets/competition-acceptance-oct11/results-light.png), [Dark](assets/competition-acceptance-oct11/results-dark.png), [Accessibility size](assets/competition-acceptance-oct11/results-accessibility.png) |
| Native tickets and official-site link, hosted fixture | [Light](assets/competition-acceptance-oct11/tickets-light.png), [Dark](assets/competition-acceptance-oct11/tickets-dark.png) |
| Scrambles selectors, hosted fixture | [Light](assets/competition-acceptance-oct11/scrambles-light.png), [Dark](assets/competition-acceptance-oct11/scrambles-dark.png) |
| Real Guangzhou navigation | [Info](assets/competition-acceptance-oct11/guangzhou-info.png), [Results](assets/competition-acceptance-oct11/guangzhou-results.png), [Scrambles](assets/competition-acceptance-oct11/guangzhou-scrambles.png) |
| Timer Cards/Shrink layout after interaction test | [Timer](assets/competition-acceptance-oct11/timer-cards-shrink.png) |

Inspected light/dark selector and badge rendering, glyph centering, accessibility-size scrolling, ticket presentation, record hierarchy and actual Browse/heading placement. Sample data is not evidence that a ticket sale is currently open or that fixture records occurred in Guangzhou.

## Focused Verification

Xcode 27.2 beta, booted iPhone 18 Pro simulator/iOS 27; app deployment minimum remains iOS 15. Existing DerivedData was reused. No broad suite or signing/device-state cleanup was performed.

| Result bundle under `/tmp/cubeflow-oct11/` | Passing focused coverage |
| --- | --- |
| `GuangzhouBaseline.xcresult` | Real initial/reopen navigation baseline |
| `TimerDynamicCorrected.xcresult` | One real UI method covering six arrangements/display-mode combinations, plus two geometry tests |
| `FocusedFinal.xcresult` | 25 unit/mounted tests plus one real navigation UI method |
| `AcceptanceFinal.xcresult` | Two real navigation/Explore UI methods plus five geometry/mounted render tests |
| `FinalLoadingGuards.xcresult` | Eight refinement/record-merge tests after final known-resource and partial-source guards |

These include 33 distinct passing test methods across the final focused runs; reruns are not counted as new coverage. Loading coverage includes publication/scramble ownership, refresh generations, request coalescing/cancellation, independent merges and the archived-Live gate. Refinement coverage includes ticket schema/availability, official selector badge priority and next-round membership. The previously passed 47-test historical run is not counted as newly rerun.

Two intermediate focused test builds exposed compile errors during implementation (misplaced content property; omitted required round argument). Both were fixed before the successful focused runs. No production failure is concealed as a pass.

- `git diff --check`: passed before the final generic build; new source/document files also receive no-index whitespace checking.
- Final unsigned generic iOS Debug build: **BUILD SUCCEEDED**, exit 0. Ran once with `xcodebuild build -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /Users/paulsun/Library/Developer/Xcode/DerivedData/CubeFlow-goanodogbuagehdsqrslicdbjmha CODE_SIGNING_ALLOWED=NO`. Log: `/tmp/cubeflow-oct11/final-generic-ios-debug.log`. No further source changes or repeat build followed.

## Remaining Acceptance Checks

1. Reproduce the reported 25-second navigation on the affected network/device with DEBUG loading/network diagnostics; compare fresh and repeat opens without presenting network variance as a code speedup.
2. On physical iPhone, repeat short/long/wrapped scrambles in Scroll/Shrink across Classic/Split/Cards. Verify top blank-space press/release, controls, long hold and inspection remain correct; verify genuine TNoodle scrambles, not the simulator bridge error.
3. Open a currently ticket-enabled China competition; verify native values and the official-site link, including login restrictions and off-sale state. No purchase was attempted in this pass.
4. Check small devices, iOS 15, VoiceOver and large text; native inline collapse, all Info secondary sections, refreshed publication transition, event/round scrolling and competitor-card navigation.
5. Validate merged official/provisional record navigation and degraded-source retry with real availability changes. Additional China Live possible-advancement indicators remain unsupported until an authoritative source/rule implementation is established; they are not silently invented.

The initial-loading performance goal remains only partially met. This report records the completed corrections and the measured limitation explicitly, rather than claiming the original 25-second failure is resolved.
