# Explore Redesign, 2026-10-07

## Scope and Starting Evidence

Before editing, inspected Explore Home, composition, public-result models/services,
cache/load states, the competition browser, filters, detail routing, WCA Live result
routing and source history. Simulator Home and Rankings screenshots are retained in
`/tmp/cubeflow-explore-redesign/`.

Home repeated its WR hero in a fixed-height nested scrolling record list, embedded
results in sentences, and produced a hanging “average of” hero label. Ordinary
competition content was discarded without a verified WCA country. Stats and
Highlights were placeholders. No northernmost/southernmost implementation or
additional Interesting Competitions categories were found in current source or
Git history; this pass adds them without inventing an earlier implementation.

## Design and Boundaries

Native List/Section navigation, result-first typography, a deduplicated three-row
Home record preview and a separate full Recent Records feed. Competition identity,
region/event search/filtering, detail, map, registration and Live navigation remain
owned by existing CompetitionService/CompetitionBrowserView infrastructure.
Signed-out Home now offers worldwide upcoming competitions; authenticated region
selection is explicitly a WCA region, not inferred GPS proximity.

No Timer, BLE, CSP, algorithm, Scramble Detail, confetti or Data behavior is edited.
The deployment target remains iOS 15.

## Record Semantics and Source Limits

`ExploreResultPresentation.level` represents the achievement. `currentRank` is
independent optional metadata. Changing rank never changes achievement level.
No rank is derived from a bounded feed's order. Person/event/type/competition context
is typed rather than reconstructed by trimming a localized sentence.
Official history rows retain their recorded achievement tags even when surpassed.

The WCA Live backend explicitly documents and implements one **best** recent
result per record key, including ties, over a competition-start-date window
(default ten days). It can omit superseded results before CubeFlow ever sees them.
CubeFlow cannot recover these or assign current world ranks from that response.
The full feed explains provisional status and this limitation; official Records
remains the history destination. No fabricated archive/rank or provisional result
is presented as an official historical record.

Primary source inspected:
https://github.com/thewca/wca-live/blob/main/lib/wca_live/scoretaking.ex
(`list_recent_records`, `group_records`).

## Rankings / Records 403

Observed both requests return an HTTP 403 HTML document with `server: awselb/2.0`,
not the expected JSON. This occurs before JSON decoding. The official Rails routes
and controllers still define the same endpoints and do not require OAuth for them.
The exact AWS edge rule is not exposed; it cannot be responsibly diagnosed as a
particular WAF/IP/header rule from this response alone.

No credential, browser spoof, cookie/referrer trick, scraping or alternate protected
host is introduced. HTTP status is preserved as a typed failure. Native Retry and
an official-site link retain the selected query, while cached results survive a
refresh failure. Request identities/cancellation prevent stale queries from
replacing a newer selection or leaving a spinner indefinitely.

Sources:
https://github.com/thewca/worldcubeassociation.org/blob/main/config/routes.rb
https://github.com/thewca/worldcubeassociation.org/blob/main/app/controllers/api/v0/results/rankings_controller.rb
https://github.com/thewca/worldcubeassociation.org/blob/main/app/controllers/api/v0/results/records_controller.rb

## Real Historical Discovery / Stats Dataset

The WCA Software Team endorses Robin Engelbrecht's public results-export API:
https://docs.worldcubeassociation.org/knowledge_base/wca_data_overview.html
https://wca-rest-api.robiningelbrecht.be/

Generation uses public data, not copied implementation code. The generated resource
contains only aggregate counts and a few competition descriptions; no organiser or
delegate contact details. No additional third-party runtime network dependency is
introduced. Reproduce with:

```sh
node tools/Explore/generate-history-summary.mjs \
  faf544a5807aa78f1cfbf251f21d4b1eb301d61c 2026-10-04 \
  CubeFlow/Resources/ExploreHistorySummary.json
```

All 19 pages are read at one immutable Git commit; pagination, totals and unique IDs
must agree before writing. 18,830 distinct competitions; 17,886 completed and not
cancelled before 2026-10-04; 17,873 with valid, non-placeholder coordinates.
Country and year sums equal the completed count. Latitude is already in degrees.
Longitude is validated but no dateline/east/west extreme rule is invented.
Tied latitude extremes are retained; repeated locations are not silently deduplicated.
North: Svalbard 2025, 78.219248 degrees. South: Ushuaia Open 2026, -54.81537 degrees.

Stats shows completed competition counts by year/country/event, including historical
retired events. The most recent year is explicitly partial. Geographic discoveries
and Stats display their export date, scope, coordinate coverage and source links.
The snapshot is real but not live; regenerate it for a newer export before shipping
when appropriate. It is never used as a substitute for Rankings/Records.

Attribution: This information is based on competition results owned and maintained
by the World Cube Association, published at
https://www.worldcubeassociation.org/export/results as of 2026-10-04.

## Verification

Focused verification passed:

- 34 deterministic tests in ExploreCompositionTests, WCAExplorePublicDataTests,
  ExploreHistoryTests and ExploreRecentRecordStateTests.
- ExploreRenderingTests: six Light/Dark/accessibility-size module fixtures.
- ExploreNavigationTests: real-data Home, full Recent Records, Rankings, Records,
  Stats, Discover and the existing Competition browser, including back navigation.
  The legacy Competition-tab request also passed separately.
- Loading/empty/failure/cached-record distinctions, language changes during a
  coalesced request, record achievements versus current standing, HTTP 403 handling,
  retained official-site filters and pinned snapshot consistency are covered.

Actual Simulator screenshots were inspected in Light, Dark and accessibility-large
Dynamic Type. Home, full Recent Records, geographic maps, Stats and live 403 screens
were reviewed; title truncation and tinted filter labels found during review were
corrected. Competition-browser loading presentation was inspected. Existing deep
result IDs are tested, but registration, every competition-detail subpage and Live
person-page navigation were not independently exercised in this pass.

Evidence lives in `/tmp/cubeflow-explore-redesign/`: `navigation-light-images`,
`dark-images`, `large-images`, their manifests and focused test logs. Latest results:
`build/codex-phase46-closeout-tests/Logs/Test/Test-CubeFlow-2026.10.07_12-29-17-+0800.xcresult`.
Simulator text size and appearance were restored to large and Light.

The external `project.pbxproj` modification was explicitly approved by the user and
preserved unchanged (SHA-256
`f4d9286a0080f301113a3342630db4b579e9029ed4d453798d2552b5c4696575`).
Baseline hashes confirm unrelated existing dirty-worktree source is unchanged.
New Explore strings are translated in English, Simplified Chinese and Traditional
Chinese; other supported locales use the established fallback for new keys.

`git diff --check` and whitespace checks of all 19 touched/new Explore files passed.
The disk-space blocker subsequently cleared: 4.5 GiB was available on recheck.
No requested cache deletion was performed by this task.

Exactly one final unsigned generic iOS Debug build passed, exit status 0:

```sh
xcodebuild -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/codex-phase46-closeout-debug CODE_SIGNING_ALLOWED=NO build
```

Log: `/tmp/cubeflow-explore-redesign/final-ios-build.log`. The compiler target is
`arm64-apple-ios15.0`; the historical JSON and three updated localization resources
were copied into the device app. The only warning in this build was skipped
AppIntents metadata extraction because the app has no AppIntents dependency.
No second build, commit or push.
