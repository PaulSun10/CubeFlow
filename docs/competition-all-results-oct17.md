# All Results Horizontal Solve Access: Implementation and Verification Status

This follows the completed Top Cubers/Filter phase described in
`competition-chip-filter-oct17.md`. That phase's 22 distinct passing focused
checks and unsigned build predate these additional table changes. They are not
build/test verification of the new table source.

## Rendering Paths Audited

1. Official Results event/round, Champions and Podiums use
   `PublishedCompetitionResultsContent.rankedRows` and
   `CompetitionResultExperience` in list mode. A tapped result opens the existing
   same Result Card; All Results loads
   `PublishedCompetitionPresentation.competitor` from the downloaded official
   snapshot.
2. Official By Competitor calls that same adapter and opens the same card with
   competition entry context, directly displaying the competitor's event tables.
3. WCA Live round results load `fetchWCALiveCompetitorContent`. Its GraphQL query
   explicitly requests separate single/average tags and attempts.
4. CubingChina Live Results, grouped records/podiums, sum-rank and personal
   shortcuts load the competitor endpoint and adapt through
   `CubingChinaLivePresentation.competitor`. Explicit provider PR fields are now
   retained by the prior phase's small presentation fix; regional records win.

All competitor tables converge in
`CompetitionResultExperience.competitorEventResultsTable`. The ordinary
event/round competitor list remains unchanged. No second Result Card, popover,
screen, or navigation flow has been introduced.

## Summary and Individual Solves

The previous `CompetitionAllResultsColumns` plan is unchanged. Each header/row
retains that leading summary block at its previous width:
`max(viewport width, existing summary minimum width)`. The new solve cells start
strictly after its right boundary. Thus the Spacer inside the old summary cannot
expand into the new tail and displace Average/Best.

`CompetitionAllResultsDisplay.attempts` reuses `WCAResultFormatter` with single
result semantics. Trailing unattempted zeros are omitted; internal zero slots
stay blank rather than shifting later attempts left. Each event's plan measures
the maximum actual slot count across its rounds. Shorter rows have empty cells
only for alignment, not invented solve values. DNF/DNS remain canonical. Time
penalties are already included in provider centisecond totals; no separate +2
marker is inferred when the source does not transmit one.

`CompetitionAllResultsSolves` measures actual formatted strings and the localized
header. `CompetitionAllResultsSolveCells` reuses the existing Results header and
statistic components with unchanged 14-point typography. Only the first solve
column has the localized Results header; every later header is empty. Solve
cells have ordinary 10-point horizontal padding, with no extra trailing spacer.
The existing 36-point result rows remain unchanged.

## Independent Native Horizontal Scrolling

There is still one `CompetitionAdaptiveResultsTable`/horizontal SwiftUI ScrollView
per event, with independent native scrolling state. The table adds the measured
tail width without changing its viewport or the enclosing card's vertical owner.
No offset initialization/compensation is introduced: the native initial leading
boundary is retained.

The installed SDK's public `ScrollBounceBehavior` offers automatic, always and
basedOnSize, but no never-bounce option for content that actually scrolls. A
small content-side `CompetitionHorizontalTableBoundaryAnchor` therefore configures
only the nearest owning UIScrollView: `bounces = false` and
`alwaysBounceHorizontal = false`. It saves/restores its own owner's previous
flags on detach. No UIAppearance proxy, timers, polling, delegate replacement,
gesture recognizer, scroll-physics replacement or production contentOffset write
is used. The outer vertical card and browser collections are untouched.

## Records and Shadows

No new badge design or classification-by-value was added. Single/average tags
still feed `CompetitionResultTableStatisticValue` and the original compact
`CompetitionWCARecordTagView` in their existing upper-right positions. Official
By Competitor already forwards verified regional tags through the same adapter
as round-origin All Results. The audit did not establish a generic official
WR/CR/NR loss in this path; earlier pixel checks demonstrated all four badge types
when explicit metadata is present. A new captured-official-data adapter test
compares every record row across the two paths, rather than assuming that result
from the renderer alone. Official PR status is not manufactured if absent from
the official response. Live explicit PR metadata remains supported.

All Results now reuses `CompetitionResultListDecoration(enabled: true,
darkShadow: true)`, the accepted official Results surface treatment. This applies
one shared table-level decoration, with the same 4-point corners, light shadow
and adaptive dark ambient lift. There are no row/separator shadows and no extra
custom shadow stack. The existing outer border remains separate.

## Separator Investigation

No separator rendering correction has been made. The owner remains the original
`CompetitionResultRoundRow`. Header bottom plus subsequent-row top ownership
produces one internal boundary, not two. Green advancement is confined to the
rank cell; the rule is drawn as an opaque full-row overlay. No round-count branch
or green-dependent rule style exists. Global pixel-phase, Canvas compositing and
parent placement remain possible physical concerns, not established causes.

The earlier phase's two-, three- and four-round Beijing fixtures and fractional
pixel-profile comparisons passed in simulator, including green advancement.
That does not resolve the stationary physical issue in Concordia or Beijing.
The new tail and shared shadow still require regression verification of those
same tests. Rule opacity, thickness, pixel-snap math and drawing owner are
unchanged. No speculative style adjustment was applied.

## Files Changed in This Addition

- `CubeFlow/Views/iPhone/CompetitionResultsStyle.swift`: solve formatting/column
  plan/cells; width-aware existing horizontal table; scoped native bounce flags;
  viewport geometry callbacks for the unspecified-width fallback.
- `CubeFlow/Views/iPhone/CompetitionTabView.swift`: append solve cells after the
  fixed summary block; reuse existing shared table decoration. The existing
  DEBUG row probe remains on the summary block so old diagnostics keep measuring
  visible summary coordinates instead of the offscreen solve tail.
- `CubeFlowTests/CompetitionAllResultsTableTests.swift`: focused tests for actual
  solves, single/three/five formats, internal blanks/DNF/DNS/penalty-inclusive
  formatting, first-only header, independent native owners, bounds/no-bounce
  configuration, preserved vertical scrolling, original summary geometry,
  scope/restoration of native flags, and official record metadata parity.
- `CubeFlowTests/CompetitionPresentationBoundaryTests.swift`: synchronize the
  existing no-explicit-viewport test with the measured width, retaining all its
  original geometry assertions.
- `CubeFlowUITests/CompetitionResultsNavigationAcceptanceTests.swift`: actual
  official By Competitor navigation, verified NR, independent horizontal solve
  access, and card dismissal. Reused the existing round/direct-card navigation
  acceptance test without changing that production flow.

## Resumed Verification

Swift syntax parsing and `git diff --check` passed. Frozen-file comparisons passed
for Top Cubers sizing/motion/chips, Filter presentation/controls, native Result
Card/Back presentation and the project file. The separator drawing implementation
is unchanged; only other table helpers in its file changed.

The initial disk-space gate was lifted before tests resumed. An interrupted
background run completed 16 focused unit tests: 15 passed, while one width test
had two failing assertions. Waiting for preferences did not resolve that failure.
A temporary DEBUG audit demonstrated the actual fallback problem: the internal
width preference stayed at zero even while the outer viewport measured 346 pt,
leaving the table at its 220/300-point minimum. This was not dismissed as a
timing-only test failure.

The fallback now reads its own viewport through GeometryReader onAppear/onChange
callbacks, updating local width only when no explicit width is supplied and the
positive measured width actually changes. There is no timer, polling, offset
write, or self-sizing rewrite. Production cards keep their explicit viewport
width. Temporary audit prints were removed.

- `final-table-regressions.log`: seven tests passed, including the four new
  production-table tests, unchanged record-badge pixel locations, round-origin
  expansion/loading, and the corrected viewport fallback.
- `final-path-acceptance.log`: final-source fractional separator profiles passed
  in light/dark at eight origins. The existing sum-rank/direct-card/round-entry
  native UI flow also passed. A new UI query initially used the wrong English
  capitalization for First round; correcting that test-only label required no
  production change.
- `final-official-path.log`: actual official By Competitor UI passed. Captured
  Beijing data for Tymon exposes NR, one Results header per table, horizontal
  scrolling of the first table without moving the second, and normal dismissal.
- Across targeted runs, all 16 distinct focused unit checks and the two selected
  native UI checks have passing results. This includes the previously passing
  Top Cubers/Filter/native Back regressions; no broad suite was executed.
- Native screenshots were exported and inspected in `official-screenshots/` and
  `path-screenshots/` under this task's build folder. The official screenshot
  shows the first table's solve tail while subsequent tables retain their leading
  summary positions. The direct-card screenshot retains the original summary
  geometry and existing NR badge.
- The one final unsigned generic iOS Debug build for this addition passed;
  its log is `final-unsigned-generic-debug.log` in the same task build folder.
- Final tracked/new-file whitespace checks and frozen-source comparisons passed.
  At final inspection the test simulator was already shut down, and no test/build
  process remained. No simulator data was erased or valid runtime removed.

Simulator checks use iOS 26.5 with the iOS 27.2 beta SDK. They do not establish
physical iOS 27.2 beta acceptance. The earlier generic build for Top Cubers/Filter
is reported separately and is not being substituted for this addition's build.

## Authorized Simulator Storage Cleanup

The user subsequently requested removal of unneeded simulator storage. Before
deleting, the active-process/device inventory was inspected and the selected
versions, sizes and reinstall consequences were explained. Only two runtimes
that the current macOS cannot run, with no simulator devices depending on them,
were removed using the supported `simctl runtime delete` API:

- iOS 15.5, build 19F70, runtime image
  `F85B7221-D27B-49B2-BA22-67F092B488C2` (about 11.5 GiB nominal).
- iOS 16.4, build 20E247, runtime image
  `41A02FC9-249F-42CB-92A6-055DD63573BA` (about 5.8 GiB nominal).

Both subsequently disappeared from the runtime inventory. Observed free disk
space increased from 5.5 GiB before deletion to about 23 GiB after completion,
then approximately 24 GiB during verification; concurrent system/build activity
means the entire last variation is not attributed to runtime deletion alone.
No simulator device/App data, valid runtime, physical-device DeviceSupport,
active DerivedData, repository build output or personal files were deleted.
Current CubeFlow testing still uses the preserved iOS 26.5 device. The removed
runtime packages would require downloading again if needed on a compatible host;
the app's deployment target and minimum-OS direction were not changed.

## Physical Acceptance Still Required

Check both official By Competitor and round-card All Results, then WCA Live and
CubingChina Live. Confirm the leading summary matches the previous screen;
independent left/right swipes reveal actual solves with a single Results header;
both horizontal edges stop without blank elastic overscroll; and vertical card
scrolling/navigation/expansion stay native. Check verified single/average badges,
explicit PR metadata, and the shared light/dark table shadow. Recheck stationary
two/three/four-round separators without assuming simulator success proves the
physical issue fixed. The previously accepted Browser List/Glass scrolling and
Top Cubers motion remain out of scope and unchanged.

No commit or push.
