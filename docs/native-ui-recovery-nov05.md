# Native UI Recovery and Competition Report - November 5, 2026

## What Changed

| Area | Confirmed cause and correction |
| --- | --- |
| Data Select / X | The previous pass replaced the two conditional button identities inside the native toolbar item with one button and swapped its label. Restored the historical conditional button structure (reference: `da9ad58d6`), retaining the native transition and hidden bottom-bar background. No transition duration, masking, or delay was added. |
| Selection and Delete | The checkmark used a custom stroked shape. It now uses the 24-pt system `checkmark.circle.fill`, with native symbol replacement and no effect under Reduce Motion. Data's Delete had a shared toolbar background around its own control; the separate bottom item opts out of that background and uses the same system-red prominent Glass configuration as Solve Detail. |
| Line Chart | The old time-series view gave the raw solves and trend little visual separation and needed a scan for nearest-date inspection. The new Swift Charts plot uses solve order, seconds labels, a teal Ao5 trend, muted raw points, and orange PR markers. The inspector gives the exact date, time, penalty, Ao5, and Ao12. At large sizes, up to 192 buckets keep the raw extrema, trend endpoints/extrema, and a record representative; exact selection still uses every solve. Invalid Ao5 runs are not connected. The histogram is unchanged. |
| Explore All Results | Provider ranks can be equal or missing, and group/dictionary iteration did not define a total order. Grouping now uses stable event IDs, then available provider rank, the existing canonical event order, and the raw ID. Round order has stable tie-breakers. Appearance and response arrival order no longer choose a winner in a tie. |
| My Competitions | The old directory parser only read legacy HTML rows. The modern page serves Nuxt records, and a nonempty cache of detail-derived names was incorrectly treated as an already-loaded directory. The app now reads modern and legacy responses, matches canonical WCA IDs, and distinguishes cached directory freshness from detail hints. Missing known China competitions can use a coalesced, cached lookup for their year. The list does not need to open detail first. Only the participation mark's inner glyph changes (11 to 8 pt; 20-pt outer control retained). |
| Result cards | The round card exposed a second Highlight action and reserved a fixed-height header. The share button now sits beside the unchanged X, on the same native overlay, with room reserved horizontally for the title. The round action produces a Highlight; expanded All Results produces a Report. This also avoids placing the native share shadow over the first row. The native host now forwards the actual competition context to the report. |
| Battle | The redundant status footer was emitted for touch input as well as other input methods. Only the touch footer is removed. Readiness, timing, manual input, scoring and Smart Cube panels are unchanged. |

The native circle-to-checkmark transition is supported by the symbol replacement
APIs discussed in [Apple's UIKit WWDC25 session](https://developer.apple.com/videos/play/wwdc2025/243/?time=1087).
On older supported versions the checkmark still uses the native symbol, without
requiring the newer effect. The line chart uses Swift Charts on iOS 16+ and
retains the existing unavailable fallback on iOS 15.

## Report Design and Export

One continuous image, with a subdued identity banner, real competition name,
available location/date, competitor identity, event bands and all rounds.
Uses available competition artwork already supplied by CubeFlow or a native
text banner. No page labels or top rule. Attempts and summary times are both
21 pt, with regular attempts and semibold summary values. Labels and attempts
can wrap. The existing standard record badge renders next to the relevant
number, including the distinction between the signed-in user's PR and other
PRs. Official round types and full event structures enable the local
first/second/final labels where appropriate; otherwise source labels are
preserved. A qualifying or combined round is not guessed from its ordinal.

Design research: [CubingChina's per-competitor table](https://github.com/CubingChina/cubingchina/blob/33ceab1efd8b7e1d0596cebe7e7af047142ded74/protected/views/results/c/byPerson.php),
[event and round certificate layout](https://github.com/CubingChina/cubingchina/blob/33ceab1efd8b7e1d0596cebe7e7af047142ded74/protected/cert/CertAc2016.php),
and [certificate renderer](https://github.com/CubingChina/cubingchina/blob/33ceab1efd8b7e1d0596cebe7e7af047142ded74/protected/cert/ResultCert.php).
The server groups results by event and official round, uses separate
backgrounds and event assets, and captures a rendered template for download.
The hierarchy informed the layout, not the implementation. No source code,
logos, artwork, fonts, or data collection was copied.

The exporter lays out once, renders strips of at most 384 px on an actor, and
writes the [standard PNG stream](https://www.w3.org/TR/png-3/) incrementally.
One output URL is leased for native Share and
[Photos file import](https://developer.apple.com/documentation/photos/phassetcreationrequest/addresource(with:fileurl:options:)).
Preview-only files load as needed with no page breaks. A failed or cancelled
export removes partial files; the lease keeps the exported file available
until the consumer releases it. The actor serializes heavy rendering for
concurrent export requests. Artwork is downloaded to a file, checked against a
16 MiB decode-input cap, and downsampled to 1,680 px. The cap is not a network
transfer cap.

The canvas is 840 logical points wide and prefers 2x. Resolution decreases
only as needed down to 1x, with guardrails of 48 million pixels and 65,535 px
in height. These are CubeFlow's limits, not claims of universal Apple or share
extension support. Larger reports fail explicitly without truncation or
pagination. A separately approved text/vector export could serve extreme
reports; it is not substituted silently.

Fixtures exercise multiple events, three named Chinese rounds, 512 rows with
duplicate provider IDs and varied result formats, excessive text and attempt
wrapping, and explicit rejection of a 4,000-row report. These PNGs were created
and decoded with the final source:

| Fixture | Image size | Encoded size | Observed export range (two runs) |
| --- | --- | --- | --- |
| Single event and round | 1,680 x 824 | 81,363 bytes | 12.2-13.6 ms |
| Multi-event, 68 rounds | 1,680 x 14,570 | 2,092,728 bytes | 377.0-390.2 ms |
| Large and near the pixel guardrail, 512 rounds | 880 x 53,876 (47.41 MP) | 7,588,259 bytes | 1,109.2-1,202.5 ms |

The 512-row test checks all source indices, actual ImageIO thumbnail decoding,
continuous preview-tile height, and share file retention. Layout tests verify
every rank/round and wrapped attempt token, and short raster captures verify
the readable appearance. This does not establish physical Photos or
share-extension acceptance. The table records observations from the 12:04 and
14:54 simulator runs, not latency percentiles.

## Performance Evidence

Xcode 27.2, arm64 iPhone 17 Pro simulator, iOS 26.5, Debug. Timings below
are wall time, not CPU time or frame deadlines. Workloads are in
`NativeUIRecoveryTests` and `CompetitionPagedExportTests`.

| Workload | Reference | Current |
| --- | --- | --- |
| 72 all-selected checks across 10,000 visible solve IDs (five batches) | Set creation/equality, mean 83.56 ms (81.62-85.22) | Early-exit membership scan, mean 26.94 ms (26.21-27.78), 67.8% less wall time |
| 256 exact inspection queries in 8,000 solves (five batches) | Nearest-date full scan, mean 194.54 ms (192.37-196.46) | Ordinal access, mean 0.058 ms (0.057-0.060); separate history construction off-main, 116.15 ms |
| Column planning for 68 rows / 17 events (five batches) | Recalculate whole-card columns per event, mean 28.31 ms (28.12-28.62) | Plan once, mean 1.66 ms (1.62-1.69), 94.1% less wall time |
| 512-row export | Prior design: eight page images, largest bitmap 46,972,800 bytes, about 878 ms (one observation) | One continuous image, largest strip 2,580,480 bytes, 1,109-1,203 ms (two final-source observations) |

The new report trades extra encoding/preview work for a single file and
roughly 18x less maximum individual rendering bitmap storage in these
fixtures. The scanline staging buffer adds approximately one strip's storage;
this is not a bound on total process RSS. The awake rerun's process high-water
mark was 640,401,408 bytes both before and after the export. That preexisting
high-water measurement cannot isolate the export's peak. The old/new outputs
are different; no latency improvement is claimed. Tests verify drawing is
off-main. No P95/P99 or energy claims are made from these small samples.
The exporter already draws only commands intersecting each strip. Long previews
encode separate small tiles to avoid full-image decoding on scroll. No further
encoder tuning was applied without a comparable, measured win that preserves
preview decoding, cancellation, and PNG completeness.

Production report row formatting now runs only on share, not in the body of
each visible results group. Drawing reuses text resources within each strip.
The preview no longer prepares a fallback export and then repeats it after
artwork arrives. A public directory probe on November 5 found 100 current
entries (91 from 2026 and nine from 2025), with 35 entries for the tested 2024
year scope. See [current directory](https://cubing.com/competition?lang=zh_cn&year=&type=WCA)
for the provider; not all provider archive rows are guaranteed to be present.
Known matching names are reused, and duplicate in-flight lookups coalesce
by scope. If an archive response lacks a name, its authoritative source name
remains available.

### Wider Review

- Timer: preserved foreground/prefetch scheduling, reserved scramble reuse,
  persistence and the native Solve Detail action. No launch change justified.
- Smart Cube and Guidance: preserved the canonical feed, on-demand renderer
  and first-deviation solver path. Existing stress and mounted tests cover
  rapid turns, rendering idle, device switching, supersession and restoration.
  No new device latency, cadence or power claim.
- Data: removed the measured selection and inspection work. The Session
  button presents a native sheet that mounts a new List and toolbar. Its
  separate background count query completed in 22.62 ms for the 1,000-solve
  fixture without firing solve relationships. That measurement does not
  isolate native sheet or list-mount latency, so the remaining physical
  Session stutter is not claimed fixed. Stable scroll ownership is retained.
- Algs: retained deferred tab and existing search indexes/cache. Current
  suite exercises cold and warm first entry and indexed search. No evidence
  warranted eager prewarming or another search rewrite.
- Explore: deduplicated scoped catalog work and hoisted repeated result
  layout. No change to public API rate limits, browser scroll physics, or
  Results navigation.
- Sharing: bounded buffers and temporary files; verified large and cancelled
  reports. Whole-export timing includes layout, drawing and encoding, not
  waiting for the external share destination.
- Battle: no timer scheduling, observation or renderer changes; mounted
  mixed-input tests exercise independent players and two live models.
- App launch: no artificial splash, eager tab mounting, or startup
  optimization claimed. Tab snapshots and Timer availability are regression
  signals, not an isolated launch or first-frame speed comparison.

## Simulator Artifacts

Under `build/native-ui-nov05/`: `data-delete-1.png`, `data-delete-2.png`,
`solve-detail-delete.png`, `line-chart-1.png`, `line-chart-2.png`,
`all-results-order-{0,1,2}.png`, `my-competitions-zh-{Hans,Hant}.png`,
`report-single-round.png`, `report-sample.png`, `report-zh-Hant.png`. Inspected real mounted surfaces
and the rendered report PNGs. Test fixtures are synthetic, not personal data.
Across four rapid programmatic selection transitions, native bars exposed
13 light and 14 dark distinct geometry/opacity signatures out of 16 samples
each. That confirms native transition activity, not an end-to-end physical
tap latency or proof of no flash on every frame.

## Verification and Acceptance

Pre-final focused pass: 19 passed, 0 failures, 0 skips. Includes actual SwiftUI
mounts, cold Chinese names with a partial cache, both chart appearances,
production PNG decoding and file lease, cancellation, round names, stable
group ordering and mixed Battle input. Localization validation passed for
19 catalogs, and all 60 strings files passed plist syntax validation.

The 1,181-test green run predates the final `@MainActor` annotation on the
round formatter and the single-/multi-round PNG test. Do not use it as the
final count. The first run on the final source (`full-verified.xcresult`)
reported 1,173 passed, 3 host crashes, 6 skipped. All three crash stacks
terminate in Core Audio's `AURemoteIO` RPC timeout from the existing Ready
sound prewarm. Host power logs record clamshell sleep at 12:11:07, followed
by the first abort at 12:11:36 and subsequent sleep/wake cycles during the
two other aborts. The affected assertions were not removed, and no audio,
Timer, or Smart Cube code was changed to make the rerun pass. The bounded
stack/power evidence is in `simulator-audio-interruption.txt`.

The unsigned generic iOS Debug build on final source passed
(`generic-verified.log`). Both bundle metadata and Mach-O specify iOS 15.0.
No Swift compiler concurrency diagnostics remain in this build. Existing
TNoodle release-evidence notices and the AppIntents metadata notice are
unrelated to these changes. Compilation does not replace iOS 15 runtime
acceptance.

Final full application regression (`full-awake.xcresult`): **1,182 total,
1,176 passed, 0 failed, 6 skipped**. This includes 825 XCTest cases
(819 passed, six skipped) and 357 Swift Testing cases (all passed). The
skips are five real-Keychain cases unsupported by the unsigned host and one
opt-in real-provider probe. Reused the already compiled final simulator
artifact after restarting the same simulator and holding a temporary idle
sleep assertion. All three previously crashed tests passed in the complete
run with the original assertions and audio behavior. The final run also
passed the ten native UI recovery tests, eight report/export tests, and two
mounted mixed-input Battle tests.

Focused XCUITest on the same final simulator build
(`ui-verified.xcresult`): **6 passed, 0 failed, 0 skipped**. The native app
tests covered the dimmed Competition Detail Back, official By Competitor
record badges and independent solve scrolling, Sum/Round Result Card
navigation, Explore-to-Browser Back, measured application launch, and
Timer controls after three cold launches. The Data control appearance,
Chinese name publication, export preview data and decoded raster, and
Battle panel evidence come from mounted tests and inspected screenshots,
not additional end-to-end XCUITests. Photos and third-party share
destinations were not exercised.

The five `XCTApplicationLaunchMetric` samples were 1.547, 1.507, 1.513,
1.509, and 1.609 s (1.537 s mean; 2.53% relative standard deviation).
The three cold relaunch-to-Timer-control XCTest observations were
5.554, 5.591, and 5.251 s and include XCTest startup and accessibility
polling. The prior pass measured 2.165 s mean on a separate run with
15.23% relative standard deviation. These are not a controlled
before/after launch speed comparison; no launch code changed in this pass.

Final resource checks: 19 localization catalogs, 60 strings plist
checks, app bundle resource presence and PNG decoding, and both
working-tree and staged whitespace checks passed.

Physical acceptance still needed: rapid Select/X and checkmark drawing in both
appearances (including Reduce Motion); Data Delete and Session menu feel;
fresh Chinese My Competitions against live provider coverage; Photos/share of
a tall image; actual cold-launch black frame and Smart Cube cadence/latency
with paired devices. No physical device was operated.

No commit, push, reset, or deployment. Branch `main` remains at
`82b455c39`, with 81 modified tracked entries, 72 untracked entries, and no
staged changes. Previous dirty changes are preserved. The continuation
changed only this report and ignored verification artifacts.

## Source Map

- Data: `DataTabView.swift`, `SolveManagementViews.swift`,
  `SessionNativeActionStyle.swift`, `SessionPerformanceLineChart.swift`.
- Competition presentation: `CompetitionTabView.swift`,
  `CompetitionNativePresentation.swift`, `PublishedCompetitionPresentation.swift`,
  `WCAMyResultsView.swift`.
- Chinese names: `CompetitionService.swift`, `CubingChinaDetailAdapter.swift`,
  `CompetitionSummaryCache.swift`, and the My Competitions view model.
- Sharing: `CompetitionSharing.swift`, `CompetitionReportImage.swift`,
  `CompetitionPagedExport.swift`, `CompetitionSharePreview.swift`.
- Battle: `TimerLocalBattleView.swift`.
- Tests: `NativeUIRecoveryTests.swift`, `CompetitionPagedExportTests.swift`,
  `PhysicalRecoveryPresentationTests.swift`, `BattleMixedInputTests.swift`.
- English, Simplified Chinese, and Traditional Chinese `Localizable.strings`.
