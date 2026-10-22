# Unified Competition Results and CubingChina Live

Completed October 11-12, 2026, in the existing dirty worktree. This is the authorized presentation follow-on to [the October 11 native compatibility closeout](/Users/paulsun/Desktop/Projects/CubeFlow/docs/cubingchina-modern-live-oct11.md), not a restart of that work. No commit, push, backend, global competition scanning, or unrelated Explore change.

## Requirement Closeout

| Requirement | Implementation and evidence |
| --- | --- |
| Actual shared selectors/list | Official and modern China Live embed the original `PublishedEventSelector`, `PublishedRoundSelector`, and `CompetitionResultExperience`/table components. The selectors share one rounded box with a subdued divider. Glyph metrics, horizontal scrolling and selection behavior remain in their existing components. Competition primary navigation and Results/Champions/Podiums/By Competitor navigation are unchanged. |
| Personal Official rows | The same exact-valid-WCA-ID drawing-only treatment now applies to Official rows. No name matching, extra badge, font, rank or 34-point list-row change. Mounted pixel/metric checks cover matching, unmatched and missing identities. |
| Integrated Live header | The selected list contains the normalized event name, short ` - ` round title, known status, unique-registration recorded/expected count, fresh SSE viewers, and latest valid `updatedByOperatorAt`. Unknown/stale metadata is omitted. Metadata uses separate caption rows, not middle dots or an oversized summary card. |
| Verified sections | Results remains default. Non-empty validated Podiums, Records and Sum of Ranks become native menu destinations. Podiums/Records use the actual shared list and existing competitor loader. No individual-round scanning is used to discover these aggregates. |
| Native actions | Chat is the rightmost `.bottomBar` action; Settings is the single left action. Chat reuses the existing read-only content, loading/errors, SSE and website fallback in a native sheet. My Results reuses existing competitor/Profile/All Results content in a sheet. Official Results and verified photo links are secondary menu actions, not banners. |
| Dark shadow | A white-at-0.045 contrast shadow, radius 3, y-offset 2, gives a barely visible ambient lift against black. It adds no border and changes no fill. Light-mode shadow is clear; mounted light render is identical with/without this modifier, dark render differs. WCA Live's existing list decoration is unchanged. |
| All Results badge room | The shared All Results table keeps 36-point rows, fonts, rank cell, score text and existing border/fill. Numeric leading padding is 4 instead of 6. The rightmost score has 25 points of badge reserve, protecting the existing x=23 badge offset. Earlier columns reserve at least 6, increasing only when the next score's measured unused width cannot safely accommodate the badge. Header/value padding is identical. |
| Championship symbol | The unchanged 20-point orange symbol is centered against the first title line using baseline alignment and the existing fitted title font's line height. Font fitting, name width, other icons, popover and inline navigation title are untouched. Full competition mounts include a championship symbol. |

All Results keeps normal seven-by-seven Mean/Best and both WR badges visible at a 320-point screen width with its existing 22-point content padding. Very long two-score formats or enlarged text can exceed the available width: measured score widths and an explicitly horizontal-scrollable table prevent score/badge overlap instead of shrinking fonts or increasing row height. Long multi-blind and narrow light/dark renders are included below. Competitor names in the ordinary 34-point result list retain their existing tail truncation at narrow widths.

## Verified External Contracts

Observed against the [Beijing public archive](https://cubing.com/competition/Beijing-Autumn-Rivalry-2026/live) and its production clients on October 11. These are observations, not a third-party API stability promise. SSR's uninitialized-round placeholder is not evidence that the hydrated archive is unavailable.

| Public path under `https://api.cubing.com/competitions/<slug>/live` | Observed contract |
| --- | --- |
| [`podiums`](https://api.cubing.com/competitions/Beijing-Autumn-Rivalry-2026/live/podiums) | `{data: [{eventId, roundNumber, results, group?, groupIndex?}]}`. 27 Beijing groups: 18 event finals plus nine age/female/newcomer groups. Category positions/results are server-authored, not recalculated. |
| [`records`](https://api.cubing.com/competitions/Beijing-Autumn-Rivalry-2026/live/records) | `{data: [full result]}`; ten Beijing rows. Only explicit verified regional flags produce WR/CR/NR; AsR becomes CR. Personal/world-rank markers do not become regional records. |
| [`statistics/sum-of-ranks`](https://api.cubing.com/competitions/Beijing-Autumn-Rivalry-2026/live/statistics/sum-of-ranks) | `{data: [{competitor, gender, sum, count, ranks, enteredEventIds}]}`; 362 Beijing rows. No overall position field. Native UI preserves server order and sum, displaying ranks only for server-declared entered events; it does not invent an overall ordinal. `/live/sum-of-ranks` is not the endpoint. |
| [`podium-group-filters`](https://api.cubing.com/competitions/Beijing-Autumn-Rivalry-2026/live/podium-group-filters) (research) | Nine Beijing category definitions with registration membership. Age `under` distinguishes the two directions. Native groups use received results; no age or registration-membership calculations are introduced. Unknown group types/indices stay website-only. |
| Competition Nuxt `liveStreams` | Semantic `title/url` metadata contains the verified [photo stream](https://live.photoplus.cn/live/47488695). Links require HTTPS, a host, and no embedded credentials. No Nuxt table index or provider hostname is hardcoded. |

The existing [API adapter](https://cubing.com/_nuxt/CFoDJUKa.js), [Live route](https://cubing.com/_nuxt/Bjba_olE.js), [table](https://cubing.com/_nuxt/CMDX1bvQ.js) and [result rules](https://cubing.com/_nuxt/DRrMchlL.js) were inspected. Header count groups by registration and counts any performed nonzero attempt, including DNF/DNS. Last updated uses operator-update time, not later ranking/cache updates. Viewer freshness uses envelope `occurredAt` when present, receipt time otherwise, with a 45-second lifetime; malformed/future values are hidden and stop/disconnection clears the observation.

New aggregate DTOs validate result competition/round identities, duplicate IDs, categories and bounds. Sum of Ranks is scoped by the verified competition endpoint and checked against its event set; its response has no separate competition ID. The three aggregate GETs have independent availability and shared cancellation/generation guards; metadata revisions coalesce refreshes. Original selected-round REST, SSE reconciliation, reconnect, archives, WCA transport, legacy extras and website fallback remain intact. Live-only cache becomes v4 for newly retained photo metadata; older optional-model decoding remains compatible.

## Deferred

Forecast is **not implemented**. Production has no separate Forecast REST dataset: the client predicts unfinished AO5/MO3 averages, sorts/reranks them, marks approximations, and applies cutoff/advancement rules. Observed AO5 behavior uses the mean for one/two attempts, median for three, interior-two mean for four, and normal trimmed mean for five. MO3 uses performed attempts; negative outcomes affect prediction. Cutoff failure suppresses projection. Client rounding changes above ten minutes. Tie/best ordering and confirmed/projected advancement interact with expected entrants and round rules.

Those facts are documented, but prediction/advancement parity across partially performed live rounds, combined rounds, cutoffs, ties and rounding boundaries is not validated by the finished archive fixtures. No approximate toggle or guessed advancement calculations ship. Chat posting/authentication and unverified category filters also remain deferred. Existing advancement colors are preserved without a new legend.

## Verification

**36 focused tests passed, zero failures**, after the final production changes: `CubingChinaModernLiveTests`, `CubingChinaLiveHTTPTests`, `CubingChinaModernLivePresentationTests`, `CubingChinaUnifiedResultsTests`. Coverage includes original revision/lifecycle/archive/chat/fallback behavior plus aggregate contracts/paths, identity/category validation, record provenance, viewer aging/stop, timestamps, compact badge bounds, long scores, light/dark rendering, sheets and native bottom-toolbar geometry. Five Sum of Ranks rows are retained in the sanitized deterministic fixture; the public endpoint's full 362-row size was researched, not fabricated in tests.

The initial focused run exposed three issues: podium age-above categories were omitted, the toolbar assertion incorrectly required `UIToolbar` despite iOS 26's native `_UIModernBarButton` implementation, and a previously navigation-less deep-link mount no longer represented the real Live parent. Categories and the test mounts/assertions were corrected. The final deep-link test verifies selection and on-demand All Results in the real navigation container. No readiness or transport guard was weakened.

Final test log: `/tmp/cubeflow-unified-results-goal/verified-focused.log`. Result bundle: `/tmp/cubeflow-explore-final-refinements/DerivedData/Logs/Test/Test-CubeFlow-2026.10.12_00-09-02-+0800.xcresult`. No broad suite ran.

**One unsigned generic iOS Debug build succeeded**, exit 0, after all production edits. Log: `/tmp/cubeflow-unified-results-goal/final-generic-ios-debug.log`. Only warning: skipped AppIntents metadata extraction because there is no AppIntents.framework dependency. App deployment target remains iOS 15. No production code changed after this build. Tracked and touched-untracked whitespace checks pass. Frozen Explore module, Competition Filter, global Recent Records merge, and external project file match starting hashes; project SHA-1 remains `0aadcf8c7dd61852886cb8babdfd4ca5ff2ad70f`.

Mounted screenshots are the real SwiftUI/UIKit tree with deterministic public fixtures, not mockups. Inspected:

- [Official light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/full-published-official-light.png), [Official dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/full-published-official-dark.png): shared selectors, exact-ID row and centered championship icon.
- [Live light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/unified-live-light-430.png), [Live dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/unified-live-dark-430.png), [Live narrow](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/unified-live-light-320.png): actual selectors/list and native bottom actions.
- [Complete narrow header](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/header-complete-true.png): known status/count, fresh viewers, operator timestamp on separate restrained lines. Viewer value is a deterministic test input, not a claimed production count.
- [Podiums](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/native-podiums.png), [Records](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/native-records.png), [Sum of Ranks](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/native-sum_ranks.png).
- [Chat sheet](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/native-chat.png), [My Results sheet](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/native-my_results.png).
- [All Results narrow light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/all-results-narrow-light.png), [dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/all-results-narrow-dark.png): protected WR badges and long multi-blind score.
- [Dark shadow off](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/shadow-off-true.png), [on](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/unified-results-oct12/shadow-on-true.png): faint contrast lift; light on/off renders are identical.

## Physical Checks And Next Step

1. Open Beijing/Guangzhou through ordinary entry: Official stays default; explicit Live remains separate. Switch events/rounds, tap rows/All Results and the Official Results action; check no stale card after leaving.
2. With a real exact signed-in WCA ID, verify subtle personal rows and My Results sheet. Sign out/unmatched identity must remove the shortcut/treatment without moving rows.
3. Exercise Chat/Settings at the bottom, read-only errors/website handoff, photo link, background/resume and network interruption. Confirm real SSE edits/removals/chat updates and stale viewer disappearance during an active competition.
4. Verify iOS 15, compact phones, large Dynamic Type, VoiceOver, longer localized names and championship titles. Confirm badge protection and horizontal table access where long scores cannot physically fit. Simulator rendering is not physical acceptance.

Next Step: physical acceptance of this unified presentation. Before any Forecast follow-on, build deterministic parity fixtures for the observed prediction/cutoff/tie/rounding/advancement behavior; preserve authoritative results separately from projections. No further native transport rebuild, global record-discovery change or bulk scan is proposed here.
