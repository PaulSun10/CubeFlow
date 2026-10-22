# Explore and Spectator Ticket Refinements - October 11, 2026

## Scoped UI Changes

- Browse retains its plain background, 66 pt minimum rows, body typography, separators and existing horizontal insets. Each of the five rows now has a decorative trailing chevron; the heading still has none, and no leading icons were added.
- Coming Up retains the already-correct canonical event IDs. Its Cubing Icons glyphs increase from 14 to 18 pt at the default text size and use adaptive primary foreground. The parent ScaledMetric scales both the grid and the glyph; the child font is not independently scaled a second time. Natural wrapping, localized VoiceOver labels, readable unknown-event fallbacks and competition navigation remain intact. No shared glyph metrics changed.
- Tickets show a single centered title-size official availability reason when all products share that reason. Mixed states remain individual. No state is inferred from stock, a past date or the configured on-sale field.
- Product cards emphasize name, price and localized validity dates. Description and actual positive purchase restrictions remain readable; stock and sale timestamps are retained in a native Ticket details disclosure. The official website Link is immediately below the sales state, before the products, so it is visible without scrolling through four cards. It is a full-width bordered action using the existing adaptive ticket accent: light #00786F, dark #00D5BE. Purchasing remains external.
- Date-only ticket validity is parsed and displayed in the same calendar/time zone, avoiding conversion to the preceding day in western time zones. Invalid dates retain their original text. Ticket details is localized in English, Simplified Chinese and Traditional Chinese.

The reported Peru label was **Events: 17**, not an event named Event 17. The previous correction already passes the actual event list through the presentation and resolves it with the existing Cubing Icons registry. That correction was preserved rather than reimplemented. Peru's ordered IDs are:

```text
333 222 444 555 666 777 333bf 333fm 333oh clock minx pyram skewb sq1 444bf 555bf 333mbf
```

## Recent Records Source Audit

### Official Recognition and Publication

Both competitions have published results, with explicit official WR flags in their public competition-results responses and records listed on their official result pages:

| Competition | Official results_posted_at | Published WR achievements |
| --- | --- | --- |
| Guangzhou Grand Open 2026 | 2026-10-06T18:49:13.000Z | Xuanyi Geng, 3x3 single 2.51; Timofei Tarasenko, 5x5 average 33.19 |
| Beijing Autumn Rivalry 2026 | 2026-10-04T16:21:55.000Z | Timofei Tarasenko, 6x6 average 1:01.76; 7x7 single 1:27.47 and average 1:35.93 |

Guangzhou's API contains 2,676 results, including seven rows with official regional record flags. Beijing's contains 1,938 results, including nine such rows. A result row can contain both single and average records. These are not unratified Live-only claims. Sources: [Guangzhou official results](https://www.worldcubeassociation.org/competitions/GuangzhouGrandOpen2026/results/all), [Beijing official results](https://www.worldcubeassociation.org/competitions/BeijingAutumnRivalry2026/results/all), and each competition's public `/api/v0/competitions/<WCA ID>` and `/results` responses.

### Observed Missing Source

The exact app-equivalent request, including Accept application/json and User-Agent CubeFlow iOS, to `https://www.worldcubeassociation.org/api/v0/results/records?region=world&show=history&gender=All` returned **HTTP 403**, an awselb/2.0 HTML response, on October 11 at 04:00:54 UTC. The earlier request and ordinary current/history variants also returned 403. The request fails before JSON decoding; it is not evidence of an empty official record history.

WCA Live's public GraphQL `recentRecords` query returned 55 records successfully (54 NR, one CR). Neither target competition occurs in that response. That observed global feed cannot supply these achievements. This is not evidence that their competition-specific Live results have disappeared, nor that completion determines the correct source. Consequently this environment supplies only Live records to the merge when official history fails, explaining the observed absence despite published recognition.

This proves the current availability limitation from this network, not the historical cause on every physical device. It does not establish why WCA's edge refuses this endpoint, or whether the inaccessible history payload is fresh. No attempts were made to circumvent that restriction, fabricate achievements, hardcode these competition IDs into production or substitute provisional data as official.

### Cache, Sorting, Filtering and Deduplication

- `ExploreRecentRecordsProvider` uses the v2 merged cache. The inspected simulator had only a legacy v1 Live cache (27 records, neither target, no official results), which v2 does not read. No v2 snapshot was present. A successful Live response paired with failed official history is deliberately not saved as complete success.
- `ExploreStore` normally uses a 15-minute TTL. A partial-source response is marked failedWithCache, which does not suppress retries inside that TTL. Existing official cached records are retained when available. A forced refresh bypasses the local TTL; it cannot bypass the source's HTTP 403 or server-side publication cache.
- Official records sort by descending competition start date and then descending result ID, bounded to 60 entries. Live preserves its supplied order and precedes official-only entries; no unsupported cross-source timestamp is invented. Home then shows three preview rows and excludes an achievement used as the hero. The See All list is not limited to three.
- Valid single/average achievements require positive values and an explicit official record flag. The world history query supplies WR history, not all national/continental histories. WCA's [records controller](https://github.com/thewca/worldcubeassociation.org/blob/main/app/controllers/api/v0/results/records_controller.rb) confirms that scope and its auxiliary-data timestamp cache. CR/NR Live entries retain their provisional status.
- Deduplication uses competition WCA ID, event ID, person WCA/live ID, result type and value. An official duplicate supersedes the identical provisional achievement only. Different results and single/average achievements remain distinct. No evidence showed this path removing either competition's records; their official history response never reached it in the observed request.

### Three Sources, Separate Discovery and Loading

The existing global discovery provider combines WCA Live's single `recentRecords` query with official WCA world record history. It has **no CubingChina Live global record provider**. It does not fetch individual competitions to discover records.

The checked `cubing.com/live` and `/live/<target slug>` routes returned JSON HTTP 404 responses. Their v1 counterparts returned archived, read-only HTML: the index had no competitions and the target pages had no `live-container` payload. The current [Guangzhou](https://cubing.com/competition/Guangzhou-Grand-Open-2026) and [Beijing](https://cubing.com/competition/Beijing-Autumn-Rivalry-2026) pages expose published Results. These observations do not prove that all archived Live routes are unavailable. They do show that the examined routes are not a validated global CubingChina Live record index. [CubingChina's records page](https://cubing.com/results/records) is an official WCA-results mirror, not a Live feed; its default China/current scope is not a substitute for global recent history.

On-demand competition loading remains independent. Official results are loaded for one opened competition, and Live links retain their explicit source. No bulk competition scanning, backend, hardcoded target competition IDs, inferred achievements or provisional-to-official promotion was added. A broader global solution first needs a validated aggregate source with known geographic/history coverage, record metadata, refresh policy and availability; scanning all competitions would impose excessive traffic and still not prove global completeness.

New focused tests guard the HTTP-error distinction and immediate retry after partial official-source failure. The targets will remain absent from this Home provider while official history is blocked, Live's global feed omits them and no validated alternative global source exists. No speculative data rewrite was made to hide this limitation.

### Demonstrated Routing and Badge Corrections

- Official Recent Records previously retained only the competition ID in navigation. The result's event and round were discarded, so taps opened Info. `ExploreItem` now carries a `PublishedCompetitionResultDeepLink` with the exact official result ID, competition ID and canonical event ID. The lookup passes it into `CompetitionDetailView`; when official publication arrives, Results opens and the matching result resolves its actual `roundKey`. No round number or Live identifier is guessed. An explicit official result requests publication validation even if the summary's end date has not elapsed; dates do not establish publication. The target is consumed once so later user navigation is not forced back. Missing/mismatched targets show the existing unavailable state instead of an unrelated default round.
- Explicit WCA Live deep links could be overridden by the CubingChina Live branch merely because the competition was in China and that content existed. Provider selection now honors the explicit WCA Live source, including its loading state, failure/provenance label and external website action. The website action reuses the existing canonical WCA Live competition URL builder rather than synthesizing a CubingChina URL for a WCA view. Existing publication recovery already retains explicit Live navigation after publication; no end-date-only source decision was introduced.
- Beijing's real official API uses `AsR` for continental records. The normalizer previously recognized only abbreviated codes such as `AS`, dropping that verified metadata. It now accepts WCA's actual `AfR`, `AsR`, `ER`, `NAR`, `OcR`, `SAR` markers, alongside the existing supported aliases and explicit CR. This is validated against WCA's [continent record names](https://github.com/thewca/worldcubeassociation.org/blob/main/lib/static_data/continents.json) and the public result fixtures. Unknown/nil/PB/PR metadata does not become an official record.
- The existing official result rows and event/round selectors already consume the decoded regional flags. Their aggregation now preserves the corrected continental markers and selects only the highest available explicit level, WR > CR > NR. For example, Beijing 7x7 first round carries CR; its final and event selector carry WR. Beijing 4x4 carries NR. Guangzhou 3x3 and 5x5 carry WR, Clock carries NR. Times/ranks are never used to infer records.
- The shared WCA result badge view applies the same marker normalization and existing geometry/colors across official Results and WCA Live. Personal-record styling remains separate and unchanged. The examined legacy CubingChina Live model/fixtures do not establish a verified regional-record field: they expose scores/attempts and competitor data, not a proven record-marker contract. No guessed field or time-based badge was added there. Full three-source parity remains dependent on verified CubingChina Live metadata.

Production paths: `ExploreComposition.swift` -> `WCAExplorePublicDataService.recentRecordsCandidate` -> `ExploreItemDestination` / `ExploreCompetitionLookupDestination` -> `CompetitionDetailView` -> `PublishedCompetitionResultsContent`. Record normalization/aggregation lives in `PublishedCompetition.swift`; the shared badge lives in `CompetitionTabView.swift`.

## Verification

The first invocation reused old binaries and omitted the newly added tests; it is not counted as evidence for the current changes. A fresh isolated DerivedData directory was used for definitive verification without changing the project file. One simulator test compilation caught a new main-actor default-argument error; it was repaired before the passing runs and before the generic device build.

| Focused run | Result | Coverage |
| --- | --- | --- |
| FreshFocusedVerification | 12 passed, zero failed/skipped | Merge/error/retry, ticket state/date semantics, Coming Up and restored layout rendering, ticket hierarchy, actual Home UI in light mode |
| DarkHomeComposition | 20 passed, zero failed/skipped | 19 composition cases plus actual Home UI in dark mode |
| RecordRoutingVerificationFixed | 36 passed, zero failed/skipped | Official fixture flags/precedence/target resolution, published models, merge propagation, 11 WCA public-data/deep-link cases, mounted official target in both appearances and ticket hierarchy at normal/larger text |
| RecordSourceFinal | 11 passed, zero failed/skipped | Final source precedence/publication request policy, canonical Live URL, merge/target propagation and mounted target in both appearances after the final source corrections |

These are overlapping focused runs, not 79 distinct tests. No broad unrelated suite was run. The fixtures preserve 16 explicit record-bearing official rows from the two public competition APIs; production does not use the fixture IDs or scan those competitions for discovery.

`git diff --check` passed for tracked changes; the touched untracked source/test/localization/report files also passed whitespace checks. The externally changed project file remains byte-identical throughout this goal (SHA-1 `0aadcf8c7dd61852886cb8babdfd4ca5ff2ad70f`).

### Screenshots Inspected

The actual Home UI captures verify the full Coming Up card without clipped glyphs, natural 8 + 8 + 1 wrapping, correct localized event names and the retained two-line record layout. Browse has all five trailing chevrons, none on its heading and no leading icons. Ticket snapshots show the centered sales state, visible official action and wrapping at Accessibility 2 size. Mounted published snapshots confirm that publication arriving after mount opens Results, selects 7x7 **First round** rather than the default final and retains correct row/selector badges after the navigation target is consumed.

| Screen | Light | Dark |
| --- | --- | --- |
| Home: Records and Coming Up | [Light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-final-refinements-oct11/home-records-coming-up-light.png) | [Dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-final-refinements-oct11/home-records-coming-up-dark.png) |
| Browse | [Light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-final-refinements-oct11/browse-light.png) | [Dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-final-refinements-oct11/browse-dark.png) |
| Official target and badges | [Light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-final-refinements-oct11/official-record-target-light.png) | [Dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-final-refinements-oct11/official-record-target-dark.png) |
| Tickets | [Light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-final-refinements-oct11/tickets-light.png) | [Dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-final-refinements-oct11/tickets-dark.png) |

[Tickets at larger text](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/explore-final-refinements-oct11/tickets-large-text.png). All screenshots are simulator evidence, not a claim of physical-device acceptance.

### Final Build

**BUILD SUCCEEDED**, exit 0. Exactly one final generic-device build was run for this goal, after the source corrections and focused verification:

```sh
xcodebuild build -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/cubeflow-explore-final-refinements/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''
```

The asset compiler confirms minimum deployment target 15.0. Build evidence: `/tmp/cubeflow-explore-final-refinements/final-generic-ios-debug.log`. No second generic build was needed.

## Physical Acceptance

Check Coming Up and Browse at normal/larger text sizes in both appearances, including spoken event names and unchanged navigation. On the actual device/network, refresh Recent Records and confirm whether official history is accessible; simulator tests cannot establish that external availability. Tap an official record and check its matching event/round; tap a provisional WCA Live record from a Chinese/published competition and confirm it stays in WCA Live. Check Beijing's CR 7x7 first-round badge and WR final/event badge without inferring records on unflagged rows. In Beijing's Spectator Tickets section, check the shared ended status, immediately visible official action, four products, retained restrictions and date/details disclosures, then verify the action opens the official website without making a purchase.

No commit, push, project-file rewrite, Smart Cube/Timer change or unrelated competition redesign was performed in this pass.
