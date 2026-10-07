# Explore visual polish - 2026-10-07

## Scope and preservation

This pass changes Explore presentation, not its content architecture. The baseline
was the current dirty worktree, not HEAD. Per-file SHA-256 comparisons are saved
under `/tmp/cubeflow-explore-polish/baseline.sha`.

The approved external `CubeFlow.xcodeproj/project.pbxproj` change is preserved.
Its baseline hash is
`f4d9286a0080f301113a3342630db4b579e9029ed4d453798d2552b5c4696575`.
Models, providers, historical JSON/generator, badge implementation, network/cache
logic, and unrelated Timer/BLE/Algs work are frozen. No dependency was introduced.

## Baseline and visual rules

Actual Light and Dark Simulator screens showed a large bare hero, loose Discover
and Stats blocks, strong blue informational dates, inconsistent section headers,
and a Settings-like Browse transition. Home top, middle, bottom, Recent Records,
Discover, Stats, Rankings/Records errors and Competition entry were inspected
before styling changes.

- Home content inset: 20 pt; meaningful surface padding: 16 pt.
- Semantic grouped page canvas and secondary grouped surfaces; no decorative
  gradients, materials or shadows. Home surfaces have 20 pt continuous corners.
- Section rhythm: 24 pt between modules, 8 pt heading-to-content; internal
  relationships generally 6-12 pt. Maps use 12 pt clipping.
- Section headings: Dynamic Type title3 semibold. Primary content is primary;
  dates, locations, provenance and disclosure chevrons are secondary.
- Accent remains for actions and selection, not ordinary informational dates.
  Existing WR/CR/NR badge colors and typography are untouched.
- One grouped surface per module, not a card per record or nested cards.
- Native List/refresh/navigation remain; the iOS 15 Home fallback uses a grouped
  table for the semantic canvas without global UITableView appearance changes.

## Changes by surface

Hero: complete editorial unit with record context, result, badge, event/type,
person, country, competition and a quiet disclosure. Result base size is 34 pt
system bold, scaled relative to title, replacing 46 pt rounded bold. It retains
prominence without looking like the Timer.

Recent Records: bounded Home preview in one surface with dividers and 20 pt
semibold result values; full feed uses native grouped rows. Historical achievement
level and optional current standing remain independent. The hero is not repeated
in the preview and the full feed is not reduced to preview size.

Upcoming: neutral subheadline semibold dates, headline names and secondary
location/event metadata. Horizontal cards are 280 pt wide (310 pt at accessibility
sizes), with the next card visibly peeking. Names grow vertically, not truncated.
First-pass screenshots revealed blank space before Events; the filler Spacer was
removed and normal minimum content height reduced from 140 to 120 pt.
Chinese accessibility fixtures revealed uneven date wrapping; date ranges now
stack at accessibility sizes while normal-size ranges remain inline.

Discover: a purposeful geographic surface with native map, actual northernmost
competition and a quieter context label. The subpage uses the same headings,
source hierarchy, map clipping and grouped canvas. No synthetic editorial story.

Stats: one compact dated snapshot on Home; 28 pt title semibold on the full page,
shared section headings and native count rows. Scope/date/source remain truthful.

Browse: all five existing destinations in one quiet grouped surface, aligned
neutral symbols, consistent row spacing/dividers and chevrons. Hidden native
NavigationLink routing avoids extra List accessories while retaining child pushes
on iOS 15 (not sheet substitution).
Actual accessibility-size review caught symbols overflowing the fixed column;
the column now scales relative to body text and dividers follow that width.

Subpages: Recent Records, Discover, Stats, Rankings and Records share the grouped
canvas and section rhythm. Filter/error layouts are preserved, with aligned
chevrons and slightly more legible error spacing. Mature Competition browser
implementation is unchanged.

## Evidence and verification

All artifacts below are real Simulator/test attachments; synthetic module
fixtures are explicitly DEBUG-only and separate from production inputs.

- Baseline Light/Dark: `before-light/`, `before-dark/`.
- First implementation Light: `pass-one-light/`; screenshots motivated the
  second card-spacing correction.
- Focused model/service tests: 34 passed in ExploreCompositionTests,
  ExploreHistoryTests, ExploreRecentRecordStateTests and WCAExplorePublicDataTests.
  Includes localization/coalescing, empty/failure/cache distinctions, full-feed
  semantics, dated history and 403/error handling.
- Initial rendering test: six Light/Dark/accessibility fixtures passed.
- Initial navigation: real-data Home/all Browse destinations and legacy
  Competition tab request passed, 2 UI tests.
- Refined Dark real-data routes: English and Chinese passed, 2 UI tests; all
  exported Home and subpage screens inspected (`refined-dark/`).
- Light accessibility-large routes: English and Chinese passed, 2 UI tests;
  exported Home, Recent, Discover, Stats and 403 screens inspected
  (`refined-large/`). Additional Home-only checks in both languages passed at
  accessibility-large and standard large (`final-home-large/`,
  `final-home-normal/`). The corrected Browse column was visually rechecked.
- Final rendering matrix: eight fixtures passed, including Chinese normal and
  accessibility carousel layouts. All final attachments are under
  `final-rendering-corrected/` after the date-range correction.
- `git diff --check` passed; untracked touched files also passed `git diff
  --no-index --check` (empty diagnostics).
- Exactly one final unsigned generic iOS Debug build passed, after all visual
  corrections and review. Log: `/tmp/cubeflow-explore-polish/final-ios-build.log`.
  Command: `xcodebuild -project CubeFlow.xcodeproj -scheme CubeFlow -configuration
  Debug -destination 'generic/platform=iOS' -derivedDataPath
  build/codex-phase46-closeout-debug CODE_SIGNING_ALLOWED=NO build`.
- Final preservation comparison: four existing Explore view files and two
  Explore test files changed; only the shared Explore presentation file and this
  report were added. All other baseline file hashes, including the approved
  project file, remain identical. No commit, push, or manual cache deletion.

## Limits

Rankings/Records retain the existing upstream 403 behavior and official-site
fallbacks; no bypass or endpoint changes. Network-delivered content/maps can vary.
History is a dated export, not invented live analytics. Live records retain their
documented provisional/source-feed coverage limitations.

Simulator visual review is not physical-device acceptance. iOS 15 deployment and
availability-guarded code are retained; this machine's review runtime is iOS 26.5,
not an iOS 15 runtime.
The mature Competition browser's child navigation/loading state was verified,
but its live list remained loading in the captured review windows. Chinese
upcoming data was unavailable during the live Home review; localized carousel
geometry/date wrapping was separately validated with explicitly synthetic DEBUG
fixtures, not by injecting records into production or changing caches.
