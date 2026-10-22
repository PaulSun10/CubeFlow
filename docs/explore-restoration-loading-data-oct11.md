# Explore Restoration, Loading Feedback and Data Accuracy

2026-10-11. Continued the existing dirty worktree without restarting prior work. No commit or push. The external `project.pbxproj` change remains preserved (SHA-1 `0aadcf8c7dd61852886cb8babdfd4ca5ff2ad70f`). Timer, Smart Cube/BLE, title collapse, advancement, record integration and previously implemented competition performance work were not redesigned.

## Visual Authority and Restoration

The four owner-supplied HEIC screenshots were converted to PNG for inspection. Reachable Git history and reflog did not contain the older Explore implementation: the reachable Explore addition was already the newer version. This is therefore a screenshot-guided restoration of the existing native components, not a claim that an unavailable historical file was recovered. Existing WCA-generated localized record sentences were reused.

The approved dark screenshots are retained here: [Browse](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/owner-approved-browse-dark.png), [Recent Records](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/owner-approved-records-dark.png). Their current light counterparts are retained as [Browse](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/owner-current-browse-light.png) and [Recent Records](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/owner-current-records-light.png).

- Section headings: native `title2` bold (22 pt at the default text size), instead of `title3` semibold. Navigable headings use an adjacent, vertically centered `subheadline` semibold chevron (15 pt), with a 4 pt HStack gap and the existing 44 pt minimum hit height. Applied consistently to Recent Records, Coming Up, Discover and Stats. Hero/menu chevrons retain their prior caption sizing.
- Browse: rebuilt as plain text buttons on the page canvas, with no icons, chevrons or rounded enclosure. Regular native body text (17 pt), scaled 66 pt rows, 16 pt leading inset, 18 pt header-to-row spacing, and full content-width separators. All five existing destinations and accessibility identifiers remain. The reference photo contains trailing chevrons; their omission follows the owner's explicit correction, not an accidental mismatch. Interesting Competitions remains the fifth destination rather than the reference's old Highlights name.
- Recent Records: no enclosing card; centered standard WR/CR/NR badge in a 36 pt leading column, then a 10 pt gap. Primary subheadline (15 pt), result bold; secondary footnote (13 pt), with 4 pt interline spacing and 15 pt vertical padding. Measured two-line row height is 67.67 pt on this simulator, matching the approximately 68 pt reference pitch. Header-to-list spacing is 5 pt. Leading badge/header edge is 20 pt and text edge approximately 66 pt.
- Competition and provisional/source lines are absent only from the Home preview. Context stays available on the full Recent Records destination. Official/live merging, sorting, deduplication, status, localization and navigation are preserved. Badge geometry, colors and standard/compact distinction are unchanged.
- Colors use the existing adaptive page, primary and secondary semantics. The dark page is black; light mode uses the existing grouped canvas. No new color theme was introduced.

## Actual Before/After Screenshots

These are real simulator app screenshots, not generated mockups. All linked images were opened and inspected. Before captures use the previously installed implementation; after captures use the restored production views. Live data can update independently of layout. The operating system's navigation/tab chrome is deliberately preserved.

| Component | Before Light | After Light | Before Dark | After Dark |
| --- | --- | --- | --- | --- |
| Recent Records | [Before](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/before-records-light.png) | [After](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/after-records-light.png) | [Before](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/before-records-dark.png) | [After](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/after-records-dark.png) |
| Browse | [Before](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/before-browse-light.png) | [After](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/after-browse-light.png) | [Before](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/before-browse-dark.png) | [After](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/after-browse-dark.png) |

The after Browse screenshots show all five rows. The light Records screenshot was captured at the initial Home position after normal app launch; the dark Records screenshot comes from the successful focused UI run. Additional mounted SwiftUI fixtures use the reference record sentences for direct typography comparison: [Records light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/fixture-records-light.png), [Records dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/fixture-records-dark.png), [Browse light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/fixture-browse-light.png), [Browse dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/fixture-browse-dark.png). The fixtures are explicitly synthetic, never injected into Home's providers. Absolute top position in the cropped hosting fixtures differs because of safe areas; comparison used content-relative geometry. This is close visual restoration, not a pixel-identical claim across different OS versions and device chrome.

## Truthful Loading Feedback

The existing session coordinator now exposes one actually pending resource through `currentWork`. The existing refresh control shows a compact spinner and localized stage, such as Loading About, Loading Competitors, Loading Spectator Tickets, Loading Scrambles, or Checking results. Its accessibility value tracks that same stage and returns to Not Loading only when genuine pending work finishes.

A fixed fraction was intentionally not used. Tickets, publication-dependent Scrambles, historical destinations and psych resources can be discovered dynamically; caches, refresh generations and cancellation also affect the work set. A denominator presented before discovery would be misleading. No progress percentage or completed-section count is fabricated. Info still mounts independently; the coordinator's ownership, refresh, cache lifetimes and cancellation behavior are unchanged.

## CubingChina Navigation and Tickets

Published China Info order is About / Regulations / Schedule / Travel / Competitors / Register / Spectator Tickets. Tickets remain conditional on the actual `showTickets` flag. Prepublication primary lifecycle and ordinary international WCA navigation remain unchanged.

The public server-rendered [Beijing ticket page](https://cubing.com/competition/Beijing-Autumn-Rivalry-2026/ticket) supplied four products (IDs 38-41), fees in cents, valid dates, sale timestamps, stock and explicit purchase restrictions. At the audit snapshot, configured `status` was on-sale, but computed `available` was false and `unavailableReason` was sale-ended. The response's computed reason, not a guess from stock or the configured status, supports displaying Sales have ended. English, Simplified Chinese and Traditional Chinese now include that translation; unknown reasons retain a neutral official-site fallback.

The actual Beijing products had `purchaseLimit: 0`. Zero, negative or missing limits are omitted rather than displayed as an unsupported restriction. Explicit positive limits are retained and tested. This does not invent a meaning such as unlimited for zero. Missing detail text now directs users to ticket details and purchasing on CubingChina, rather than claiming the information is unavailable. The existing official action always remains present; there is no in-app sale flow. Ticket semantic color is unchanged.

The [Guangzhou ticket page](https://cubing.com/competition/Guangzhou-Grand-Open-2026/ticket) had no ticket products and `showTickets: false`. Venue-admission `entryTicket` is not treated as evidence of a sales section. Mounted [light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/fixture-tickets-light.png) and [dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/fixture-tickets-dark.png) fixtures verify Sales have ended, absence of Purchase Limit 0, and the official action. Their description/name are synthetic display fixtures, not an assertion of verbatim official product copy.

## Combined and Coming Up Event Labels

The Results mapper had appended Combined for legacy cutoff round codes. WCA's [RoundType model](https://github.com/thewca/worldcubeassociation.org/blob/main/app/models/round_type.rb) pairs cutoff/non-cutoff types as c/f, d/1, e/2, g/3 and h/0; its [official English locale](https://github.com/thewca/worldcubeassociation.org/blob/main/config/locales/en.yml) uses the ordinary round titles. Published labels now use those titles without the internal Combined suffix. Raw type IDs, cutoff/result format, ordering, attempts, record status and advancement logic are retained. This is unrelated to Smart Cube Combined mode.

The owner identified the reported Event 17 location as Explore / Coming Up / Peru Nationals 2026. The actual before screenshot displays **Events: 17**. It was a quantity, not an event ID or a Nuxt reference index: `ExploreCompetitionCandidates.item` reduced `CompetitionSummary.eventIDs` to `eventCount`, and the carousel rendered that count string.

The [official Peru API response](https://www.worldcubeassociation.org/api/v0/competitions/PeruNationals2026) supplies these 17 canonical IDs:

```text
333 222 444 555 666 777 333bf 333fm 333oh clock minx pyram skewb sq1 444bf 555bf 333mbf
```

The presentation now carries the actual ordered IDs. Coming Up renders the existing Cubing Icons font through `CompetitionEventGlyph` in a compact wrapping grid, with localized event names for VoiceOver. Unknown IDs keep a readable text fallback; genuinely count-only inputs retain an honest quantity fallback. There is no numeric-index-to-event guess, new network request, cache migration, glyph offset or shared font-metric change. Card dates, identity, location and navigation remain intact. The actual [light Home](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/after-coming-up-light.png) and [dark Home](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/after-records-dark.png) show all 17 icons across two rows; UI assertions also confirm Clock's spoken name and absence of Events: 17. The separate Nuxt-reference regression remains a guard against confusing reference index 17 with an event ID, not the claimed cause of this Home label.

## Final Measured Performance Review

One actual browser-to-detail UI method measured all three competitions, first with the existing DEBUG fresh-first-detail refresh flag and then immediate reopen. This bypasses the app's section/HTML content caches on that first opening; it is not a claim of a cold DNS/TLS connection, empty OS caches, or production device timing. Intervals include XCTest tap/idle synchronization and approximately one-second predicate polling. Screenshot capture happens after each timing interval.

| Competition | First Useful Info | Whole Session Idle | Post-Info Tail | Reopen Useful Info | Reopen Idle |
| --- | ---: | ---: | ---: | ---: | ---: |
| Guangzhou Grand Open | 5.84 s | 6.91 s | 1.07 s | 1.91 s | 3.00 s |
| Beijing Autumn Rivalry | 5.19 s | 9.26 s | 4.07 s | 1.93 s | 3.00 s |
| Toronto Weeknights I | 1.73 s | 2.81 s | 1.08 s | 1.90 s | 2.98 s |

Retained [UI timings](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/review-ui-timings.txt) and [resource/network phases](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-restoration-oct11/review-summary-phases.txt) support the following conclusions:

- Guangzhou's six China detail HTML resources each issued one observed fresh request. Last section was Competitors, 5.50 s from its resource start; session completion was 5.68 s from coordinator start. China parsing logged 12-23 ms off-main, versus multi-second response times.
- Beijing's explicit ticket capability was discovered with About. Its subsequent ticket request took 2.58 s, explaining the remaining internal tail: useful Info at 3.96 s and all sections at 6.63 s from coordinator start. The ticket transaction logged about 1.11 s server time and 1.27 s transfer, on a reused connection. No speculative ticket fetch was added before the capability flag was known.
- Toronto Info/Schedule shared one observed WCA HTML transaction over reused HTTP/2. Info completed at 0.79 s; the whole coordinator at 1.43 s, including genuinely gated published Scrambles. Its favorable network conditions in this sample are not a new software speedup.
- Published Results/Scrambles decode/model work was tens of milliseconds for China and a few milliseconds for Toronto, much smaller than network intervals. Their first reads were misses and immediate reopen Results were hits. Warm coordinator completion was 0.19-0.25 s. Routine detail-body construction traces were sub-millisecond after the initial construction.

No additional transport/cache/scheduling rewrite was justified by this sample. The demonstrated remainder is primarily network response/transfer plus legitimate resource discovery, not slow JSON parsing or a duplicate WCA Info request. Beijing's whole-session sample is slower than the owner's approximately five-second observation; this is disclosed, not presented as an improvement. Current measurements do not prove a causal explanation of the historical 25-second occurrence. The previous demonstrated China Competitors concurrency correction is preserved and documented separately in [the loading-tail report](/Users/paulsun/Desktop/Projects/CubeFlow/docs/competition-loading-tail-oct11.md).

## Verification

- Initial focused run: 33 tests passed (loading lifecycle, stage presentation, navigation order, ticket fields/status, cutoff round titles, semantic reference resolution, official/live merge, and mounted light/dark rendering).
- Final Explore verification: 19 composition tests, two rendering methods, and the actual Home UI method passed. Includes canonical Peru ID propagation, all 17 glyph mappings, wrapping/large text/unknown fallback, and the restored row geometry.
- Final light and dark full-Browse Home UI checks passed. The dark repeat used test-without-building. These additionally check no Browse images, 66 pt minimum rows, adjacent header geometry, Peru's accessible Clock name and absence of the old count label. The three-competition performance UI method passed.
- One intermediate rendering assertion failed because 67.6667 pt was just below a strict 68 pt boundary. It was replaced with the tighter reference-height check `68 +/- 0.5 pt`, accounting for one physical pixel. The final render run passed. The mixed intermediate result bundle remains recorded as failed; its two UI methods and ticket fixture passed. No production dimension was changed to conceal that test failure.
- `git diff --check` and explicit whitespace checks for touched untracked source/test/string files passed. The project file hash is unchanged.
- Final unsigned generic iOS Debug build passed (`BUILD SUCCEEDED`, exit 0). This is the one newly approved final generic build, not a reused older result. No second generic build was needed. Log: `/tmp/cubeflow-explore-goal-audit/final-generic-ios-debug.log`.

```sh
xcodebuild build -project CubeFlow.xcodeproj -scheme CubeFlow \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /Users/paulsun/Library/Developer/Xcode/DerivedData/CubeFlow-goanodogbuagehdsqrslicdbjmha \
  CODE_SIGNING_ALLOWED=NO
```

Result bundles and detailed logs are under `/tmp/cubeflow-explore-goal-audit/`: `FocusedRestoration.xcresult`, `FinalFocusedUI.xcresult`, `FinalExploreVerification.xcresult`, `FinalHomeLight.xcresult`, and `FinalHomeDark.xcresult`. No broad unrelated suite was run. Verification used the iPhone 18 Pro / iOS 27 simulator with Xcode beta; iOS 15 compatibility is retained in the APIs/deployment target, not newly physically certified by these simulator runs.

## Files Changed in This Goal

- `CubeFlow/Views/iPhone/Explore/ExplorePresentationStyle.swift`, `ExploreModuleView.swift`, `ExploreView.swift`: reference typography, chevrons, rows, preview metadata and Coming Up glyph presentation.
- `CubeFlow/Models/ExploreComposition.swift`, `CubeFlow/Views/Shared/ExploreCompetitionProvider.swift`: carry canonical competition event IDs into the presentation; preserve pre-existing dirty record integration.
- `CubeFlow/Views/Shared/CompetitionSectionLoading.swift`, `CubeFlow/Views/iPhone/CompetitionTabView.swift`: truthful pending-stage presentation and China published Info order.
- `CubeFlow/Views/Shared/CubingChinaTickets.swift`, `CubeFlow/Views/iPhone/PublishedCompetitionView.swift`: supported purchase restrictions and official cutoff round titles.
- `CubeFlow/en.lproj/CompetitionPublished.strings`, `CubeFlow/zh-Hans.lproj/CompetitionPublished.strings`, `CubeFlow/zh-Hant.lproj/CompetitionPublished.strings`: loading stages, neutral ticket guidance and sale-ended status.
- `CubeFlowTests/CompetitionRefinementTests.swift`, `CubingChinaDetailTests.swift`, `PublishedCompetitionIntegrationTests.swift`, `ExploreRenderingTests.swift`, `ExploreCompositionTests.swift`, `CubeFlowUITests/CompetitionPerformanceTests.swift`: scoped state/data/rendering/real navigation coverage.
- This report and its evidence assets. Other pre-existing dirty files are preserved, not attributed to this goal.

## Remaining Physical Acceptance

Check Explore in both appearances at the owner's normal and larger text sizes, including Browse taps and centered record badges. Confirm Peru's Coming Up card icons and VoiceOver event names while preserving its competition-detail destination. On the affected device/network, open/refresh Guangzhou, Beijing and Toronto and observe both useful Info and the final truthful loading stage. Check Beijing's ticket status and official action without making a purchase. Different live data, networking, OS rendering and accessibility behavior still require device acceptance; no hardware validation is claimed here.
