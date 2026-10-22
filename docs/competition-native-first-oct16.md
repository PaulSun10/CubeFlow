# Competition UI: Native-First Restoration

October 16, 2026. Current dirty worktree preserved. No commit/push.
This report supersedes claims that the rejected background-button glass, dimmer
aperture, or custom Filter animation satisfied physical acceptance.

## Original Implementations

Commit `c551de97` contains both native paths:

- `CompetitionCardSurfaceModifier` applies `compatibleGlass(in:)` directly to
  card content. That helper uses `.glassEffect(.regular.interactive(), in:)` on
  iOS 26+. `competitionListRowBase` is a plain Button whose label is the card.
  Both the modifier placement and the native Button interaction owner matter.
- Filter is a Button with SwiftUI `.popover`, bottom attachment/top arrow, the
  original `CompetitionFiltersPopover` content, clear presentation background,
  and compact popover adaptation. UIKit/SwiftUI owns its transitions; no layer
  opacity/scale replacement exists in that commit.

## Changes and Limits

### 1. Interactive Glass

Removed the separate card-sized background Button and noninteractive comparison
switch. Restored content-wrapping native glass and the original plain Button
owner for Glass rows. Removed the competing Glass-header tap gesture; normal
navigation goes through the row Button. Disclosure retains its own native Button.
List/Compact navigation and address/chip data actions are not redesigned.

Tiny measured simulator movement is no longer an acceptance criterion. The old
synthetic positive/control tests for the rejected surface were removed, not
repurposed as evidence for the original interaction. Physical press deformation,
highlight and release still require the user's inspection of the new build.

### 2. Top Cubers

Read-only probes now sample the actual venue row, Top Cubers heading, visible
competitor entries, and disclosure control, not merely the title/viewport.
Measurement-only invisible cuber copies do not register as visible entries.
The initial visible probe identities are captured before the disclosure action,
so newly inserted rows are not mistaken for pre-existing content.

With content-wrapping glass restored, the baseline export reproduced the precise
boundary: the venue and existing cubers moved approximately 15-18 points during
resize even though title drift was much smaller. Model and presentation samples
showed intermediate vertical layouts, not a scroll-offset correction.

The inner card stack now uses `.fixedSize(horizontal: false, vertical: true)` in
both List and Glass. It retains its content-derived vertical size while the native
self-sizing cell interpolates its bounds, instead of laying out its descendants
against intermediate height proposals. This does not constrain horizontal
wrapping, hardcode a height, change three-row counting, move glass to a background,
or turn off native feedback. Existing 0.32-second disclosure animation is unchanged.

Initial native-glass sizing checks reduced venue drift from about 14.75 points to
0.44 points and existing cubers below one point. The corresponding List check
records zero venue/heading/existing-cuber drift across four toggles. The strict
original title assertion still failed at approximately 1.51 points in Glass;
its one-point tolerance was not weakened. These checks are not full acceptance.

Removed the DEBUG collapse-at-drag-start implementation, its Search interception,
registration hooks and tests. It changed the interaction being tested and did not
prove real tap-then-swipe behavior. The original native scroll/disclosure actions
remain. Rapid physical tap-then-swipe hitching is not marked resolved.

The existing gesture-idle loader publication gate remains unchanged. Its earlier
tests stopped at drag/deceleration completion. Read-only native traces now also
sample just after idle, exposing rather than concealing a possible deferred jump.
No new loading gate, timer-based publication delay, forced reset, or speculative
offset compensation was introduced. Cold-scroll physical acceptance remains open.

### 3. Native Detail Back

Removed `CompetitionBackExposure`, its environment injection, even-odd Path hole,
per-control tint override, and exposure lifecycle. The backdrop is again uniform
black at 0.42 opacity. In this architecture a full-window presented controller
covers the original navigation controller. Elevating only its UIKit/SwiftUI-owned
Back visual would require moving owned views or recreating its appearance; neither
is a safe native restoration. The explicitly allowed uniformly dimmed fallback
is used instead.

The existing transparent measured hit proxy forwards the original native Back
action after card dismissal exactly once. It draws no replacement Back. Only
the modal controller owns it; no-card Back remains entirely native and unchanged.
Other background controls remain blocked. Existing press forwarding, Profile and
card-internal navigation are retained.

### 4. Round Separators

The user subsequently clarified that the discrepancy is specifically between
internal round separators inside one competitor's All Results table, not the
main Competition Results list. No annotated screenshot is available. The
rendering-owner inventory distinguishes:

- All Results internal header/round boundaries: `CompetitionResultRoundRow` in
  `competitorEventResultsTable`, currently one-pixel opaque Canvas fills.
- All Results outer rounded border: separate adaptive `separator` stroke at
  0.5 opacity and 0.5-point width; intentionally not the internal boundary.
- Main Results header/competitor boundaries: native Divider in `resultListRows`.
- Sum Ranks boundaries: native Dividers in `CompetitionResultsRefinement.swift`.
- Selector event/round divider: native Divider with its own 0.55 opacity.

The clarified internal lines all use the same per-row Canvas, color and thickness;
there is no alternating native Divider or record/round-specific color branch.
The adjacent header line uses the same wrapper at its bottom. The first result
does not add another top line, so the header boundary is not deliberately doubled.
The rounded outer stroke is a separate owner, intentionally different, and does
not cross those internal round boundaries.

The old pixel checks mostly compared the darkest pixel near each boundary. A new
focused test compares both peak shade and integrated seven-pixel profiles on the
actual four-round All Results card at eight vertical offsets, in light and dark.
Production styling is unchanged. Results are recorded in the clarification
follow-up below; simulator equality is not treated as physical acceptance.

### 5. Filter

Removed `CompetitionFilterSurfaceMotion`, keyed CA animation group, explicit
opacity/scale writes, show/hide callbacks and its DEBUG no-motion switch. Removed
the Filter-only transaction that disabled native animation. The original SwiftUI
popover now owns presentation/dismissal normally. Map/Filter toolbar grouping,
popover content/attachment, Region controls and navigation remain unchanged.

Retained the generation-aware user-intent/local-binding acknowledgement and native
dismissal-completion observer. A reopen request during dismissal waits for the
native lifecycle, rather than a timer or synthetic surface animation. Old binding
acknowledgements cannot close a newer generation or permanently lock Filter.

Mounted checks confirm prompt mounting and animated UIKit transition coordinators,
with no `competition-filter-surface` animation on the actual presented layer.
This proves native ownership, not physical perceptual latency. Any remaining
platform-specific capsule/popover delay must be reported, not hidden by disabling
the transition or adding a replacement effect.

## Verification Journal

Evidence: `build/competition-native-restore-oct16/`.

- `native-baseline.log`: an editing error left an unbalanced DEBUG file; compilation
  failed before tests. The error was corrected, with no generic build consumed.
- `native-baseline-fixed.log`: four mounted native Filter/Back checks passed. The
  Glass disclosure check failed its original title tolerance. The initially placed
  new element assertions were not reached by the warm branch; raw element traces
  were collected, then the test routing was corrected. Do not count that initial
  List result as proof of the new element assertions.
- `ideal-height-elements.log`: venue/heading/cubers in Glass were below one point,
  but the original title assertion failed. List then exposed the previously missed
  lower-content movement. This mixed run is not a pass.
- `native-layout-and-lifecycle.log`: three native Filter lifecycle/reopen tests,
  List element checks, and both interior-cold checks passed. Glass retained the
  approximately 1.51-point title failure. This mixed run is not a pass.
- `original-button-and-native-routes.log`: the actual Detail Back route and native
  Filter controls/Region/outside/repeated-open route passed. The Glass fixture
  initially selected the row Button because it inherited its child's identifier.
  Giving the native row its own stable accessibility identifier corrected that
  ambiguity without changing touch routing.
- `original-button-disclosure.log`: the corrected query reached the actual child
  disclosure. Venue/heading/existing cubers were below one point; title drift
  remained 1.517 points. This run failed and is not presented as a pass.
- `final-native-regressions.log`: three reported tests passed (both interior-cold
  appearances and Filter background/foreground recovery). A separately requested
  new method was not reported; no independent-action pass is credited to this run.
- `complete-idle-and-original-route.log`: completed post-idle traces in both
  appearances passed. The combined route/geometry test also passed, but measured
  geometry after navigating away and back. That warm result is not evidence for
  the fresh-card first-tap invariant. The tests were separated accordingly.
- `fresh-geometry-and-independent-actions.log`: `testGlassCardActions` passed,
  explicitly exercising independent expand/collapse, original native row
  navigation, Back and disclosure-state retention. The separate fresh geometry
  case failed the unchanged one-point title assertion at 1.244 points. No further
  glass substitute or tolerance change was made to manufacture a pass.
- Filter rendered screenshots were exported and inspected in `filter-rendered/`:
  the original popover content and combined Map/Filter capsule remain intact.
- No physical UI handshake retry was made: the preceding task already established
  that automation cannot start on this phone/toolchain. This pass does not claim
  new physical acceptance or install its new source on the phone.

### Exact Elements and Remaining Gate

Fresh native-Button Glass trace: `makati-native-fresh-final.json`.

| Element | Maximum sampled vertical movement |
| --- | ---: |
| SM Makati venue row | 0.3601 pt |
| Top Cubers heading | 0.1346 pt |
| Leo Borromeo | 0.0296 pt |
| Ayooluwa Samuel Dada | 0.3382 pt |
| Gabriel Subion | 0.6468 pt |
| Disclosure control | 46.7878 pt downward; cell grows 47 pt |
| Competition title | **1.2444 pt; fails original 1 pt limit** |

The fourth cuber, Juan Miguel Y. Magallanes, is newly revealed, not classified as
pre-existing stationary content. The disclosure is expected to move with the lower
boundary, not remain fixed. List's four-toggle element check records zero movement
for venue, heading and the three existing cubers.

The final cold traces explicitly wait for `idleRecordingComplete`, not an earlier
partial recording: Glass covers 0.664 seconds after idle; List covers 0.662 seconds.
Both report zero sampled backward movement for the same visible cell, including
the post-idle interval. This is not physical frame-pacing proof and does not
establish the cause of the user's real rapid-collapse hitch. That issue, native
press/release feel, physical Filter latency, and the unreproduced internal-round shade variation
remain open. The native implementation is preserved rather than substituted.

## Scoped Files Changed

- `CubeFlow/Views/iPhone/CompetitionTabView.swift`
- `CubeFlow/Views/iPhone/CompetitionNativePresentation.swift`
- `CubeFlow/Views/iPhone/CompetitionFilterPresentation.swift`
- `CubeFlow/Views/iPhone/CompetitionExpandableTopCubers.swift`
- `CubeFlow/Views/iPhone/CompetitionDisclosureAcceptanceSurface.swift`
- `CubeFlow/Views/iPhone/CompetitionLongListAcceptance.swift`
- `CubeFlowTests/CompetitionPresentationBoundaryTests.swift`
- `CubeFlowUITests/CompetitionDisclosureGestureTests.swift`
- `CubeFlowUITests/CompetitionLongScrollAcceptanceTests.swift`
- `CubeFlowUITests/CompetitionPhysicalFinalBrowserTests.swift`
- This report.

## Frozen Accepted Work

The stable-ZStack Round/All Results transition and the result card's opening,
closing, content, outside dismissal, Champions fill, records, podiums, advancement,
and Profile/card-internal Back logic are unchanged. No Timer/BLE/Explore, transport,
WCIF, cache persistence, signing, project, or deployment-target work is included.

## Final Build and Handoff

The one final unsigned generic iOS Debug build passed:
`build/competition-native-restore-oct16/final-unsigned-generic-debug.log`.
No additional generic build is available for this goal. `git diff --check` and
explicit whitespace checks on touched untracked source passed. The project,
advancement and Live-transport SHA-1 values still match the preserved baseline.
The source from `resultDialog` through the end of `CompetitionTabView.swift` is
byte-identical to this goal's starting copy, preserving the accepted stable-ZStack
and subsequent Results/Champions behavior.

This is not an all-green closeout: the fresh-card Glass geometry assertion fails,
the real rapid-collapse hitch is not resolved by the synthetic/simulator evidence,
and the physical internal-round shade variation is not reproduced. No further custom alternative
is introduced to hide those limits. The unsigned build is not installed on the
phone; its previously installed debug app must not be mistaken for this new source.

Next physical checks, after building/running this source:

1. Press/release a Glass card and check authentic native deformation/highlight,
   normal navigation and independent disclosure. In fresh Makati, watch the venue,
   heading and the three existing names during the first expansion and collapse.
2. Expand a long list, tap Show Less and immediately swipe upward. Also observe
   initially uncached Top Cubers through dragging, deceleration and the first idle
   moment, in both appearances. No cache/data erasure is requested.
3. Confirm the intentionally uniform dimmer and functional original toolbar Back;
   no result card means the ordinary native Back remains unchanged.
4. Check native Filter presentation/dismissal, rapid reopening, Region/outside and
   scene recovery. Report any delayed first visible content separately from the
   duration of the native animation.
5. Compare internal round-to-round lines in All Results. Their owner is now known;
   a physical image would help isolate the still-unreproduced shade variation.

No commit/push. No device session or test/build process remains running from this
pass. The overall physical-acceptance goal remains unproven.

## Separator Clarification Follow-up

The internal-round owner is now confirmed by the user's description. The earlier
scope uncertainty is resolved; the cause of the physical shade variation is not.

Added `testInternalRoundSeparatorProfilesAtFractionalOrigins` to
`CubeFlowTests/CompetitionNavigationLoadingTests.swift`. It renders the actual
Wang four-round All Results card, not a replacement line view. It compares three
internal boundaries at eight vertical phases (0 through 7/12 point), in light
and dark, checking both darkest-pixel contrast and integrated seven-pixel coverage.
The adjacent header boundary is compared independently using the same profiles.

Both focused runs passed on iOS 26.5:

- `build/competition-round-separator-oct16/fractional-profiles.log`
- `build/competition-round-separator-oct16/round-and-header-profiles.log`

Within each rendered table the internal profiles matched, including the adjacent
header. No alternating owner, duplicate header/first-round line, round-dependent
style, or differing coverage was reproduced in these fixtures. This does not
establish physical iOS 27.2 equality or prove a compositor fault. It also does not
prove that every possible table position/state is covered.

No production separator, color, material, width, border, or global style changed.
Only the focused test and this report changed in the clarification follow-up.
The native outer border remains intentionally distinct. `git diff --check` passed;
no generic build, device interaction, commit, or push was performed.
