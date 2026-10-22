# Physical Evidence: Filter, All Results Separators, Cubing Live Indicators

## Status

- **Filter:** the waiting state and its cost are confirmed, but the capture does
  not distinguish an overlong native dismissal from a late/unrelated observer
  acknowledgement. No speculative production lifecycle change was made.
- **Separators:** a reproducible raster-origin error was isolated and corrected.
  Controlled production-component rendering is now one consistent raster row.
  Physical compositor acceptance remains pending; the supplied snapshot is not
  an original iOS screenshot.
- **Cubing Live:** the clarified lazy-discovery defect is fixed: unvisited
  Event/Round selectors now consume the already-requested competition record
  summary, not only manually opened round snapshots. Explicit PR loss in the
  session adapter and tolerant optional record decoding are also corrected.
  Existing result-cell badge support was not reinvented. Historical WebSocket
  record semantics remain unverified, not guessed.
- **WCA Live:** its transport, interpretation, badge component and presentation
  logic are unchanged.

No physical Apple device was accessed. No commit or push was performed.

## Evidence Actually Inspected

Both original ZIPs were read before changing production source. Copies of their
JSON/image evidence and analyses are under `build/competition-evidence-oct19/`.

| Bundle | Contents | SHA-256 |
| --- | --- | --- |
| `/Users/paulsun/Downloads/E7871F72-DA8F-424A-AEB9-DC6C833887A0.zip` | Filter metadata, 78 events, 0 dropped | `ee844a7bbf8fc4745f22d1548e483604b4817f40c2182218aaed6dc441bd3e48` |
| `/Users/paulsun/Downloads/CD9B962C-8474-437B-BE22-A574761BA37A.zip` | Separator metadata + snapshot.png | `92089f63a9922a7b8c3b1219f4316768a674742d220e0ccb39d76fe7bcb62ea7` |

OS: iOS 27.2, build 24B5084k. Logical and native scale are both 3. The separator
image is a **1110 x 2040, 16-bit RGBA UIKit snapshot**, covering a 370 x 680-point
card crop at window (16, 111). The ZIP has no `system-screenshot.png` and no
`authoritativeImage` field. It does not prove exact physical compositor pixels.

## Filter: Exact Timeline

Times below are captured CACurrentMediaTime seconds, not wall-clock guesses.
`filter-timing.csv` contains the calculations from the full unfiltered event list.

| Event | Time | Meaning |
| --- | ---: | --- |
| Initial touch ended, delivered | 51646.168052 | Native input reached the app |
| open-request / intent-published | 51646.168958 / 51646.169002 | Immediate application response, generation 2 |
| close-request | 51646.520173 | User closes generation 2 |
| native binding false | 51646.525143 | Dismissal requested from SwiftUI |
| probe will-disappear / dismissal-began | 51646.536826 / 51646.536841 | Probe reports animated=true, duration=0 |
| Reopen touch ended, delivered | 51646.851312 | Reopen input was not missed |
| open-request, dismissing=true | 51646.852251 | Action follows delivery by **0.939 ms** |
| dismissal-finished | 51648.412491 | Pending request waited **1560.241 ms** |
| next intent-published | 51648.412608 | Only **0.116 ms** after completion acknowledgement |
| next binding true / content make | 51648.421794 / 51648.444003 | New native presentation requested/mounted |

Generation 3 repeats the same pattern. Delivered reopen actions occur at
51649.443280, 51649.652391 and 51649.802676 while dismissing=true. They wait
1319.960, 1110.849 and 960.564 ms respectively for the same acknowledgement at
51650.763240. Exactly one generation-4 intent follows, **0.098 ms** later.
Action-after-touch-delivery costs are 0.337, 0.784 and 0.824 ms, not a second.

The app's `CompetitionFilterPresentation.open()` sets requested=true and queues
behind isDismissing. The latter is cleared by dismissalFinished, invoked through
CompetitionPopoverCompletion's registered transition completion. There is no
cooldown or additional scheduled delay after that callback. Close-to-completion
costs are 1892.318 ms (generation 2), 1460.186 ms (3), 1276.280 ms (4) and
1276.813 ms (5).

### What Is Not Proven

The capture has no first-visible-native-surface events, no observer/native
coordinator identities, and no did-disappear event. Its probe's did-appear events
coincide with closing rather than providing a useful first-visible timestamp.
The recorded zero duration belongs to the representable observer's coordinator;
it is not proof that the actual popover's native dismissal took zero time.

UIKit's SDK contract explicitly allows a controller's transitionCoordinator to
be inherited from its parent. Without coordinator identities/from/to controllers
and native presenter state, this capture cannot establish when UIKit actually
released the popover or whether the observer acknowledged later than necessary.
Clearing isDismissing early, reversing the binding blindly, or presenting a second
instance would be a speculative race, not a proven fix.

### Change Made

Only DEBUG diagnostics were extended: observer/parent/native-container identities,
native presenter/window/presenting/dismissing state, observer versus native
coordinator identity/duration/interactive/cancelled/from/to information,
completion registration, transition completion, did-disappear, and completion
acceptance. Existing event names, generations, touch observation and export
workflow remain usable. There is no additional transition registration, polling,
delay, gesture or production state-machine change. DEBUG-stripped Filter source
is identical to this pass's starting source.

**Filter latency remains unresolved.** One short follow-up capture with these
fields can distinguish the missing native-owner timing; no device access by the
agent is needed.

## Separator: All Owners and Selected/Unselected Comparison

Competition is BeijingAutumnRivalry2026. All IDs below use the actual published
round IDs, not inferred round labels. All boundaries have logical/native scale 3,
identity transforms, opacity 1, no explicit rasterization and no active animation
keys. Model and projected presentation coordinates agree to floating-point error.
There is one Canvas per boundary in source, not duplicate drawing by round count.

`Y px` is the marker's recorded top edge in screen render pixels. Every value
has phase .5: **pixel phase alone does not distinguish the groups.**

| Event / boundary | Actual round IDs | Selected as thick? | Y px | Local paint Y pt | Snapshot rows at x=700 |
| --- | --- | --- | ---: | ---: | ---: |
| 333 header -> First | header -> 954898 | No; header | 636.5 | 28.5 | 2 |
| 333 First -> Second | 954898 -> 954899 | **Yes** | 746.5 | +1/6 | **2** |
| 333 Second -> Semi Final | 954899 -> 954900 | **Yes** | 855.5 | +1/6 | **2** |
| 333 Semi Final -> Final | 954900 -> 954901 | **Yes** | 964.5 | +1/6 | **2** |
| 222 header -> First | header -> 954902 | No; header | 1293.5 | 28+5/6 | 1 |
| 222 First -> Second | 954902 -> 954903 | **No; thin reference** | 1402.5 | -1/6 | **1** |
| 222 Second -> Final | 954903 -> 954904 | **Yes** | 1512.5 | +1/6 | **2** |
| 444 header -> First | header -> 954905 | No; header | 1839.5 | 28.5 | 2 |
| 444 First -> Second | 954905 -> 954906 | **No; thin reference** | 1949.5 | -1/6 | **1** |
| 444 Second -> Final | 954906 -> 954907 | No | 2059.5 | +1/6 | **2** |
| 333oh header -> First | header -> 954917 | No | 2386.5 | 28.5 | Outside crop |

There are 11 recorded owners, 10 painted boundaries inside the image, and 8
selectable lines. The two thin partially clipped top strokes were present in raw
geometry but omitted from the review's selectable line list. Selection has four
IDs: the three unwanted 333 round separators and 222 Second->Final.

The snapshot does demonstrate a selected-two-row versus unselected-one-row
comparison. However, unselected 444 Second->Final and two unselected headers also
occupy two rows in this UIKit image. They must not be falsely described as thin
in this snapshot, or used to contradict the user's physical observation. This is
one reason an original system screenshot is still necessary for strict physical
pixel-level conclusions. No original image was silently assumed.

### Confirmed Reproducible Rendering Mechanism

The old top-boundary formula rounds the logical global GeometryReader origin,
then applies that residual inside Canvas. The rendered Canvas surface's own
pixel-rounded origin can differ from that logical global origin. The captured
local residuals are +/- half a render pixel. A negative residual can be clipped
at the Canvas edge; a positive residual can cover two raster rows and extend
from the spacer into the adjacent green/white content. The green styling does
not choose a different separator style, but it changes the lower pixel's
compositing when the stroke extends into content.

An actual production-component regression reproduced the problem without
changing opacity or color: with six fractional row origins, three old boundaries
painted one row and three painted two. The other three already had one-row
coverage. The fix paints a top boundary at **the Canvas's local raster origin
(y=0)** rather than applying a second global-layout correction. All six now use
one row, with identical intensity. This is not a per-round/event offset, reduced
opacity, guessed half-pixel phase fix, contentOffset adjustment or clipping mask.

The original 1/displayScale thickness, opaqueSeparator color, spacer, row height,
header-bottom formula, table shadows, qualification backgrounds and layout all
remain. Header boundaries are deliberately not restyled. The DEBUG geometry
probe uses the same paint helper so after-captures describe the new actual rule.

At 3x in the controlled simulator image, original on-grid one-row color was
208.51 (converted sRGB red); off-grid old lines were two rows at 231.71 each.
After the fix all six are one row at 208.51. Thus nominal stroke coverage is
conserved and made consistent, not made uniformly fainter with a cosmetic alpha
change. These levels are simulator/snapshot conversions, not physical-device
color measurements. Exact physical perceived thin/light acceptance remains the
user's check; it is not claimed from nominal geometry or the UIKit snapshot.

The accepted CoreText Results/solve ink alignment, 6 pt solve padding, summary
widths, row heights and independent no-bounce horizontal owners are unchanged.

## Cubing Live: Provider Facts and Narrow Implementation

The current Cubing Live provider is Cubing China's REST/SSE path, distinct from
WCA Live. The code also retains a legacy WebSocket path. No transport rewrite,
new endpoint, bulk round scanning or local numerical record detection was added.

Public responses were read directly on 2026-10-19:

- [Beijing 7x7 round 1](https://api.cubing.com/competitions/Beijing-Autumn-Rivalry-2026/live/results/777/1):
  51 results; its first result supplies regionalSingleRecord=NR,
  regionalAverageRecord=AsR and explicit PR flags. There are 21 single and 17
  average PR flags in that response.
- [Beijing 7x7 final](https://api.cubing.com/competitions/Beijing-Autumn-Rivalry-2026/live/results/777/2):
  17 results, including explicit WR/WR, NR, and personal-only PR results.
- The [provider's Live page](https://cubing.com/competition/Beijing-Autumn-Rivalry-2026/live)
  identifies these Live markers as provisional. Its HTML-only placeholder is not
  used as a substitute for the actual result API.

The actual fields are regionalSingleRecord, regionalAverageRecord,
personalSingleRecord and personalAverageRecord. rankSingleMarker=WR5 or
rankAverageMarker=WR3 is NOT a record. The provider's modern primary renderer
already used correct regional/personal flags. A real bug remained in the
CompetitionCubingLiveSession row adapter: it discarded personal-only flags by
using regional-only singleBadge/averageBadge instead of the normalized preview.
A baseline test failed with nil/nil for explicit PR/PR before the correction.

### Exact Behavior

- One Cubing-specific normalizer reuses the existing regional alias mapping:
  WR -> WR, AsR/other known continental aliases -> CR, NR -> NR.
- A known regional flag takes precedence; otherwise explicit personal PR is
  displayed. Single and average are normalized independently.
- Missing, unknown, rank-marker and non-string record values produce no invented
  badge. Whitespace/case are normalized, not interpreted numerically.
- Optional record decoration decoding is tolerant. Invalid scores, attempts,
  identity or round ownership remain strict. Previously a boolean record field
  threw and discarded the result snapshot; the regression now retains the scores
  with nil record decorations. Codable round trip and off-actor decoding pass.
- Primary round, competitor All Results and session-row adaptation use the same
  Cubing-only display indicators. Regional-only singleBadge/averageBadge remain
  separate, so global discovery does NOT acquire personal-only records. Cubing-only
  selectors can show explicit available PRs with WR > CR > NR > PR precedence;
  shared WCA regional normalization remains unchanged.
- Existing CompetitionWCARecordTagView, palette, placement, localization and score
  formatters are reused. WCA Live and shared regional normalization are unchanged.

### Clarified Root Cause: Unvisited Round Discovery

The user identified Beijing Autumn Rivalry 2026 and three concrete records.
The existing competition-scoped [records endpoint](https://api.cubing.com/competitions/Beijing-Autumn-Rivalry-2026/live/records)
returned all three in one 7,090-byte response (10 result objects), saved as
`build/competition-evidence-oct19/evidence/cubing-current-records.json`:

| Round | Competitor | Explicit single / mean flags |
| --- | --- | --- |
| 666 round 1 | Timofei Tarasenko | empty / WR |
| 777 final | Timofei Tarasenko | WR / WR |
| 777 round 1 | Ziyu Wu | NR / AsR |

Wu's single is NR while his mean is continental. Therefore the first-round
selector should show **CR**, not NR: a selector shows the highest available level,
whereas his result values keep their separate NR single / CR mean badges.

Before this correction, `CubingChinaLiveExtrasStore.refresh` already requested
`/live/records`, but `CubingChinaUnifiedLiveContent` built Event/Round badges only
from `session.knownRoundBadges`. That dictionary was populated by `updateBadge`
only after installing the selected full round snapshot. Opening a round
incidentally repaired its selector badge. The competition summary was used for
the Records destination but was disconnected from selectors. In addition,
records were not published until podium and sum-of-ranks requests completed.

The corrected path is:

1. Publish validated records as soon as their existing aggregate request finishes,
   independently of slow podium/statistics responses.
2. Build round tags from validated, round-identity/metadata-matching aggregate
   evidence. Event tags reduce those round tags with Cubing-only precedence.
3. Prefer a current complete round snapshot, including authoritative absence of
   a record, over partial aggregates. Never resurrect a retracted regional flag
   from an older podium response after a complete regional summary arrives.
4. Reject superseded in-flight responses and coalesce refreshes with the **latest**
   bootstrap, not the original request's captured round metadata.
5. Refresh aggregates on relevant SSE updates, including equal-revision events,
   and after reconnect. Stale events do not trigger a refresh. The existing
   selected-round/advancement request behavior is preserved; no new full round
   requests are made for record discovery.

Round metadata contains identity/revision/rules, not regional/personal record
summaries. The `/records` aggregate contains regional record rows, not every
personal-only PR. Explicit PRs already present in current full snapshots or
validated podiums are shown; unknown personal records are not fabricated or
discovered by bulk round downloads. Failed aggregate requests do not replace
previous valid record evidence with an invented authoritative empty response.

### Legacy WebSocket Audit and Limitation

The legacy branch was inspected separately: `CompetitionService` bootstraps
`data-c/events/params/filters`, `CompetitionCubingLiveSession` subscribes at
`wss://cubing.com/ws`, requests the selected round through `result/fetch`, and
handles `result.all/new/update`. Its row builder reads `i/n/e/r/b/a/v`; no
verified record-field mapping or competition-level record summary contract is
available in that bootstrap. It does not share modern REST identity domains.
The inspected v1 archive did not provide a usable Live bootstrap. No guessed
compressed field, modern-ID bridge or speculative all-round scan was added.
The supplied Beijing examples are verified on the modern REST/SSE path and are
covered by this correction. Historical WebSocket record support is not claimed
as fixed without an authoritative payload contract.

## Files Changed

- CubeFlow/Views/iPhone/CompetitionResultsStyle.swift
- CubeFlow/Views/iPhone/CompetitionUIDiagnostics.swift
- CubeFlow/Views/iPhone/CompetitionFilterPresentation.swift (DEBUG only)
- CubeFlow/Views/iPhone/CompetitionTabView.swift (Cubing row mapping, summary refresh lifecycle and selector tags)
- CubeFlow/Views/Shared/CubingChinaLiveModels.swift
- CubeFlow/Views/Shared/CubingChinaLivePresentation.swift
- CubeFlow/Views/Shared/CubingLiveRecordIndicators.swift (new)
- CubeFlow/Views/Shared/CubingChinaLiveExtras.swift
- CubeFlow/Views/Shared/CubingChinaModernLiveSession.swift
- CubeFlow/Views/iPhone/CubingChinaUnifiedLiveContent.swift
- CubeFlowTests/CompetitionSeparatorEvidenceTests.swift (new)
- CubeFlowTests/CompetitionFilterEvidenceTests.swift (new)
- CubeFlowTests/CubingLiveRecordIndicatorTests.swift (new)
- CubeFlowTests/CubingLiveRecordDiscoveryTests.swift (new)
- docs/competition-evidence-fixes-oct19.md

All unrelated dirty changes are preserved. No project, Top Cubers, Glass,
Connected Devices, Timer/Combined, navigation or Filter-controls file was edited.

## Verification

- **34 distinct focused unit/native-host tests + 1 UI test passed across this
  goal's focused runs.** The clarification's final run passed 13 tests with zero
  failures, including six new discovery regressions, record decoding/bridging,
  aggregate validation and an unchanged WCA Live light/dark native mount. These cover
  normal/repeated/queued Filter epochs, 20-cycle stress, original native animation,
  binding generations, no duplicate host, original controls/selection retention,
  new owner diagnostics, captured selected/unselected identities, one-row raster
  coverage/intensity across six origins, unchanged header formula/row footprint,
  accepted solve/header ink alignment and spacing, independent no-bounce owners,
  explicit regional/personal record adaptation, malformed optional flags and
  strict scores/identity, Codable round trip, native Cubing/WCA light/dark mounts.
- New discovery checks exercise the production store and session: all three
  supplied examples before visiting their rounds, publication ahead of blocked
  statistics, round metadata invalidation, complete-snapshot badge removal,
  coalesced refresh using latest metadata, rejecting superseded nonempty replies,
  old-podium regional retraction versus explicit PR, and the actual mounted
  Competition section's equal-revision SSE/reconnect refresh. Requested round
  keys remain confined to the already-selected default round in those fixtures.
- The first discovery run had one test-observer setup failure: it counted the
  initial scope-clear notification. Registering the observer after that explicit
  initialization corrected the test; no production behavior was changed to make
  it pass. All final discovery assertions pass.
- Both baseline regressions failed before their corrections: production
  separators had two-row off-grid strokes; the Cubing bridge dropped PR and a
  malformed record flag rejected valid result data. Corrected tests pass.
- Exported light/dark native result screenshots were inspected. The modern Cubing
  list visibly retains existing WR/NR/PR badges and native selectors; CR is
  verified from the actual AsR wire value and production presentation tests.
- The new mounted refresh screenshot was also inspected: unvisited event badges
  appear while the default event remains selected; no round-selection action is
  used. It is a controlled fixture with an empty default round, not a physical
  production screenshot. Xcode emits the previously observed SwiftUI native
  UIKitToolbar hosting warning; it is retained in the result bundle, not hidden
  or treated as a failed assertion.
- A Swift beta code-generation issue with cross-file private CodingKeys was
  resolved by co-locating the Codable extension with its model, retaining
  explicit nonisolated decoding. No compiler-safety setting was weakened.
- The originally allowed unsigned generic iOS Debug build passed, recorded in
  `final-generic-debug.log`. After the user explicitly approved one additional
  final build for the clarified discovery correction, that build also passed
  (`CODE_SIGNING_ALLOWED=NO`, `generic/platform=iOS`), recorded in
  `record-discovery-final-generic-debug.log`. No further build was run. The only
  subsequent source edit removes a pre-existing extra blank line at EOF; no
  executable code changed after the final build.
- git diff --check passed. Explicit whitespace checks on all touched added/untracked files also passed.
- No Release build, broad unrelated test suite, physical-device operation,
  manual simulator/cache cleanup, commit or push was performed.

Logs, result bundles, exact timing CSV, original evidence copies, pixel analysis,
before/after raster screenshots and source baselines are in
`build/competition-evidence-oct19/`.

## Remaining Physical Acceptance and TestFlight Risks

1. Repeat the same short Filter capture once after running the new source:
   Start -> normal open/close -> immediate reopen -> Stop -> Share. The added
   owner/coordinator/did-disappear fields are needed to decide whether the native
   presentation actually remains active throughout the delay. Do not change
   selection state solely for this diagnostic. No agent device access is needed.
2. Revisit the supplied Beijing competitor's 333/222/444 All Results. Compare the
   three formerly selected 333 lines against the formerly thin 222/444 references.
   Take one original iOS system screenshot while stationary, then Capture Visible
   Table without moving, import that screenshot, mark any remaining problem and
   Share. Header style is intentionally unchanged. UIKit snapshots alone cannot
   establish final physical pixel appearance.
3. Confirm Results/solve alignment, horizontal no-bounce scroll, vertical card
   scrolling, green advancement, shadows and native card/Back animations remain
   accepted. No Top Cubers/Browser scrolling implementation changed.
4. Enter Beijing Autumn Rivalry 2026 Live fresh. Before opening 666/777 rounds,
   wait for the competition summary: both event icons should show WR; 666 round 1
   and 777 final should show WR, and 777 first round should show CR (highest of
   Wu's NR single and CR mean). Then check separate result-value badges for all
   three supplied examples and an explicitly flagged personal-only PR. No WCA Live
   behavior change should be observed.

Filter's approximately 1-1.5 second reopen delay remains a product acceptance
risk. The separator fix still needs physical thin/light approval. A remaining
legacy/provider-specific badge omission cannot be signed off without identifying
its source. A passing unsigned Debug build is not a full TestFlight/release audit,
and this report does not declare all physical issues resolved.
