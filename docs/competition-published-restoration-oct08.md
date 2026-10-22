# Competition Detail: Final Integration And Provider Restoration

2026-10-08. Current dirty worktree, checkpoint
`c551de97919551e2ef1051a2ba45adbef16f1836`. No commit or push.
This report supersedes the earlier separate Published Competition shell design.

## Architecture And Identity Findings

CompetitionDetailView remains the sole competition detail page. Its original
header, separator, ScrollView, navigation primitives and Info presentation are
retained. Published primary destinations are exactly **Info / Results / Scrambles**.
Register and Competitors disappear only after nonempty validated official results.
Unpublished, unknown, loading and failed lookups retain the original navigation.
Explicit existing Live deep links/transports remain supported, without adding Live
to the published primary tabs or implementing reconciliation.

China Info uses the product-owner-approved compact secondary strip for Main Page,
Regulations, Schedule and Travel. These invoke the existing content branches, not
new secondary pages. The original Info branch is unchanged apart from resolving
its existing title through the currently selected Info section. Source comparisons
confirmed the original WCA header, China header, separator and WCA Info content
are unchanged. The previous image-only-document and relative-image fixes remain.

The old integration never added published destinations to the original China tab
registry. It instead swapped the whole page for a separate shell. Regional-only
identity waited for the complete Info fetch; official-host detection returned
CompetitionSummary.id rather than extracting the actual official URL ID. That
could misroute/reject a regional identifier, and the task identity changed when
Info acquired its WCA ID. These are verified integration defects, not proof that
Beijing's official data is absent or malformed. The precise failing branch of the
original physical-device run was not captured and is not retrospectively proven.

New identity resolution prefers an actual official WCA competition URL path, then
explicit canonical metadata. WCA API summaries now retain wcaCompetitionID through
localization and cache round trips. Regional-only entries use the embedded public
wcaCompetitionId from About, sharing the existing in-flight HTML request, without
waiting for Regulations, Travel, Schedule or Registration. No slug conversion,
name-based heuristic or Beijing hardcoding is used.

Regression identities:
- WCA: `BeijingAutumnRivalry2026`
- CubingChina: `Beijing-Autumn-Rivalry-2026`

[Official WCA publication](https://www.worldcubeassociation.org/competitions/BeijingAutumnRivalry2026)
and [current CubingChina results](https://cubing.com/competition/Beijing-Autumn-Rivalry-2026/results)
were checked live. Complete WCA JSON contained 1,938 validated results. Empty
successful responses mean unpublished; missing identity is unknown; transport or
decoding failure is failed, with quiet retry. Failed refresh preserves a valid
published snapshot. Generation checks prevent cancelled/superseded work from
publishing stale state. End dates gate traffic only, never prove publication.

## Current CubingChina Content Audit

Live Beijing downloads: About 204,423 bytes; Regulations 101,599; Schedule 282,803;
Travel 95,983; Registration 125,822; Competitors 2,662,178. All returned HTTP 200.
The production adapter mapped:
- About: six blocks, including organizer-authored content, fees, venue and team.
- Regulations: two blocks, retaining nested rules/check-in/organizer policy.
- Schedule: three Shanghai-local days, 48 activities, 2/3/1 rooms respectively.
- Travel: organizer rail/airport instructions plus Venue overview and map location.
- Registration: public ended/registration-closed status.
- Competitors: 370 regional registrations, including non-WCA/custom-event entries.
  Official published result participation remains WCA-authoritative.

A concrete previously missed defect was found in
[Beijing Travel](https://cubing.com/competition/Beijing-Autumn-Rivalry-2026/travel):
the Travel heading and organizer text are outside the automatic Venue section.
The earlier semantic adapter returned Venue immediately and dropped the actual
rail/airport guidance. It now merges missing embedded organizer blocks with
semantic sections, without duplicating text already rendered. The restored
organizer block contains 806 characters of rail, subway, taxi and airport guidance.

Nuxt/devalue indices are resolved rather than treated as fixed schema offsets.
Semantic extraction preserves headings, introductory text, lists, tables, links,
images and arbitrary organizer sections. Locale cookies are restricted to current
CubingChina detail requests. Legacy HTML parsers remain valid fallbacks. Section
failures are isolated and offer a quiet section-source link; no parser diagnostics
are displayed. The detail cache namespace is now provider-aware v10, preventing
reuse of incomplete v9 Travel or cross-provider Info. No cache files were deleted.

Canonical fields route directly to the original native destinations:
overviewBlocks -> Info/Main Page; regulationBlocks -> Regulations;
scheduleDays -> existing Schedule; travelBlocks/mapLocations -> Travel;
registerBlocks -> original Register before publication; competitorPreviews ->
original Competitors before publication. Native semantic parsing tests verify that
tables, images, links and travel text survive beyond the provider adapter. Actual
SwiftUI snapshots verify Info/Regulations/Travel destination rendering with compact
fixtures; they are not screenshots of every complete live organizer document.

## Published Content

Official WCA JSON remains the final authority. Current CubingChina's Winners,
Podiums, All Results and By Competitor interactions inform the native organization,
not website CSS. Results defaults to ranked results, with explicit discoverable
Results / Champions / Podiums / By Competitor modes. Event icons and actual
available round chips share one compact control area. Canonical historical round
order is retained; B Final is not the medal final.

Dense lazy rows show authoritative rank, full competitor name, best, average or
mean when present, performed attempts and existing compact WR/CR/NR badges.
Trailing zero/unperformed cutoff attempts are omitted; DNF/DNS remain. Ao5, Mo3,
best-of formats with official means, FMC and multi-blind use the existing formatter.
Champions and podiums use official final ranks, including ties, not fastest best.
Search covers names and WCA IDs; a participating authenticated profile is promoted.
Person results group by event/round and retain existing WCA profile navigation.

The icon defect was an explicit white foreground on every glyph. Published-only
selectors now use white when selected and adaptive primary when unselected,
including the glyph's own Text and legacy capsule surface. Local cell bounds scale
with Dynamic Type to avoid clipping. Shared glyph mappings, measured metrics,
fonts and other event selectors are unchanged. No disabled events are exposed.

Scrambles are an inline destination using the parent's scroll/refresh lifecycle,
not a nested List or separate page. Event/round/group, normal/extra grouping and
exact official text remain. Supported scrambles open the existing Scramble Detail;
unsupported/multipart formats retain selectable text. Refresh reloads the scramble
resource without resetting event/round/group selection. Results never wait for
Scrambles, and historical Info remains usable while Results loads.

## Measurements

Benchmarks used the production result models/service outside the repository;
complete datasets were not bundled. Network samples are single observations, not
controlled proof of network speed improvement. iOS state/render timings use
injected deterministic fixtures; render timing is the first SwiftUI row onAppear,
not physical screen latency.

| Phase | Toronto Weeknights I 2026 | Beijing Autumn Rivalry 2026 |
| --- | ---: | ---: |
| Official rows / bytes | 106 / 37,745 | 1,938 / 709,842 |
| Initial HTTP 200 download | 846 ms | 5,312 ms |
| After HTTP 200 network sample | 979 ms | 3,096 ms |
| Before offline decode / model | 1.80 / 4.44 ms | 13.54 / 7.72 ms |
| After offline decode / model | 0.97 / 5.85 ms | 13.29 / 7.60 ms |
| After live-service decode / model | 0.77 / 0.44 ms | 12.90 / 6.05 ms |
| Before: ten warm model rebuilds | 3.75 ms | 63.71 ms |
| After: ten cached snapshot accesses | 0.148 ms | 0.116 ms |
| iOS first row, warmed host, matching fixture sizes | 27.81 ms | 21.97 ms |
| Scrambles HTTP 200 network | 208 ms | 653 ms |
| Scrambles bytes / rows / sets | 16,968 / 70 / 10 | 166,903 / 618 / 92 |
| Scrambles decode / grouping | 0.35 / 0.11 ms | 2.13 / 0.75 ms |

Canonical identity resolution in the iOS fixture was 0.35 ms; published-state
assignment was approximately 0.05-0.06 ms. Regional-only live About download took
446 ms and its native-ID extraction took 11.91 ms in a separate adapter probe.
First cold SwiftUI host startup took 187 ms; subsequent dark/accessibility hosts
were approximately 15 ms. These phases are measured separately and must not be
summed into a claimed physical end-to-end acceptance result. There is no comparable
before first-frame measurement of the old shell.

The measured improvement is eliminating repeated canonical model rebuilding on
cache hits, not radically accelerating cold JSON parsing or the network. Results
have bounded 12-snapshot caching, coalesced in-flight requests and indexed event
rounds. Positive results live for one hour; empty snapshots for 60 seconds.
Scrambles retain a separate bounded eight-entry cache. Both services already use
actor-side processing; this pass does not claim to fix a nonexistent main-actor
result JSON decode. No polling was added. DEBUG logs expose identity, HTTP/bytes,
decode/model, published-state assignment and selection-to-first-row timing.

## Verification And Scope

Focused suites: PublishedCompetitionTests, PublishedCompetitionIntegrationTests,
CubingChinaDetailTests, CompetitionScheduleClockTests. Final run: **39 passed,
zero failures**, iPhone 18 Pro / iOS 27 simulator. Earlier contrast assertions were
corrected to compare color components instead of UIKit color-space object equality.
An initial off-scene snapshot attempt produced black images and was rejected;
final captures use the actual foreground UIWindowScene and were visually inspected.

Verified rendering: original China Info/header/separator, inline Results and
Scrambles, secondary Regulations/Travel, global Results, selected/unselected glyphs
in light/dark, and accessibility Dynamic Type. Tests use small deterministic
fixtures and real production SwiftUI components through a DEBUG-only rendering
initializer, not a replacement page. Full physical-device live loading, interactions,
remote-image network behavior, very long names/rare formats, older iOS appearance
and authenticated-user navigation still require device acceptance.

Schedule NOW logic and view remain unchanged in this correction. Existing tests
cover absolute-time alignment, out-of-range suppression and overlap lanes. No
Timer/Data/Alg/BLE/Smart Cube/CSP, accepted diagrams, glyph metrics, Live transport,
subscription, advancement, project configuration or deployment target changes.
Original generated `build/` output (5.4 GB) is preserved.

Files changed in this correction: CompetitionService.swift,
CompetitionPublishedIdentity.swift, PublishedCompetition.swift,
CubingChinaDetailAdapter.swift, CompetitionTabView.swift,
PublishedCompetitionView.swift, the three CompetitionPublished string tables,
PublishedCompetitionTests.swift, PublishedCompetitionIntegrationTests.swift,
CubingChinaDetailTests.swift and this report. The inherited schedule files/tests
remain unmodified.

`git diff --check` and additional untracked-source whitespace checks passed.
Final unsigned generic iOS Debug build: **passed**, first and only final build,
`CODE_SIGNING_ALLOWED=NO`, app minimum still iOS 15.0. Only warning: skipped
AppIntents metadata extraction because the app has no AppIntents dependency.
Evidence/logs, complete temporary provider downloads and snapshot attachments:
`/tmp/cubeflow-competition-integration/`; DerivedData is reused at
`/tmp/cubeflow-competition-check/DerivedData`. No commit or push.
