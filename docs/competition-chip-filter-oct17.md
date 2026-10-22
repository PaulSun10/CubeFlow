# Top Cubers, Filter Reopen, and All Results Follow-up

## Scope and Preservation

No commit, push, reset, cleanup, signed installation, or physical-device interaction.
Existing worktree changes were preserved. Turn-specific baselines and logs are in
`build/competition-chip-filter-oct17/`.

SHA-1 comparisons confirm these files are unchanged:

- `CompetitionExpandableTopCubers.swift`: synchronous first-fit sizing, three-row
  prefix, motion tracking, progressive reveal, rapid reversal, Reduce Motion.
- `CompetitionFiltersView.swift`: original popover controls, appearance, bindings.
- `CompetitionNativePresentation.swift`: Result Card/native Back presentation.
- `CompetitionDisclosureAcceptanceSurface.swift`: accepted animation fixture.
- `CompetitionResultsStyle.swift`: all separator drawing and advancement styling.
- `CompetitionResultTable.swift`: shared Results badge component and placement.
- `project.pbxproj`: preserved external/project changes.

The content-wrapping interactive card glass modifier, hosting cells, virtualized
collection/layout implementation, and Results/All Results section of
`CompetitionTabView.swift` also compare byte-for-byte with the starting copy.
No scroll physics, contentOffset compensation, async publication, filtering,
ranking, Makati header, or presentation animation was changed.

## Top Cubers Findings and Changes

The chip surface had padding but no production background. The red DEBUG outline
was therefore its only visible boundary. `CompetitionTopCuberChip` now owns a
production continuous rounded rectangle with radius 4, matching that outline's
geometry. The adaptive primary-color fill has opacity 0.065 in Light Mode and
0.10 in Dark Mode, with primary foreground. Horizontal/vertical padding remains
10/8. The background does not depend on DEBUG.

The old badge used asymmetric horizontal/vertical padding around a glyph view
that itself added vertical padding and minimum height. Its capsule consequently
had a variable rectangular footprint. `CompetitionTopCuberRecordBadge` now has
an explicit square, Dynamic-Type-scaled 25-point diameter with centered content.
Glyph size is 13 points, scaled once using a fixed-size custom font. The chip's
layout centers actual name and badge bounds vertically; no baseline/position
offsets were added. WR/CR/NR retain red/orange/yellow. iOS 26+ uses
`.glassEffect(.regular.tint(color.opacity(0.3)), in: Circle())`, deliberately
without `.interactive()`. Earlier systems use a 20%-tinted circle. An unavailable
event glyph falls back to the record tier, with full event and record-tier
accessibility labels. Badge fallback text is 11-point bold and scales with the
circle. Event glyphs remain the ordinary visual content.

The flow already packed consecutive ranked entries. No sorting, skipping, or
backfilling defect was found. It did, however, carry a second measurement model:
per-string UIKit widths, multiple ceil operations, unscaled badge font estimates,
and a preferred-width layout hint. These estimates are not the actual SwiftUI
chip, especially when typography or badge geometry changes. They are removed.
`CompetitionWrappingLayout.measuredSize` now uses the actual subview's intrinsic
fit and proposes the available width only when that fit exceeds the container.
The inner chip no longer insists on a 96-point name allocation when the real
remaining width is smaller. No chip width is hardcoded.

The existing synchronous sizing layout and visible flow still call the same
measurement function. Their ranked sequence and 8-point gaps are unchanged.
This removes parallel metrics without changing the accepted sizing lifecycle.
It does not prove that every previously perceived gap was a bug: a gap is valid
when the next ranked chip cannot fit. Tests explicitly verify that condition.
For example, real default-size chip widths 111, 98.333, and 92 fit together in
320 points with two 8-point gaps (317.333 total), without reordering.

Git commit `afecf2f9` contains the original full-width wrapping container with
`.competitionSizeDebug("section", color: .blue)`. Only the overlay convention
was recovered, not the old layout. The current persistent component has the blue
outline again. Its label reports available container width and measured height
to one decimal point; chip labels also show width and height. The outer label is
below the outline to avoid overlapping chip labels. These are overlays only,
hidden from accessibility and hit testing, and compile out in Release.

Light/dark screenshots were inspected and saved in the build output directory.

## Filter Findings and Changes

No app timer, debounce, cooldown, or artificial animation wait was found. The
existing recorded native lifecycle shows warm intent publication under 2 ms,
binding requests in roughly 3-5 ms, first observable native surfaces near 81 ms,
and approximately 850 ms native dismissal/full presentation lifecycles. Those
are separate measurements: didAppear is not the first visible frame.

A distinct source-level race was found in the popover Binding setter. It used
the latest mutable `nativeGeneration`, not the epoch captured by that binding.
An acknowledgement from an older dismissed popover could therefore write false
into a newer native presentation before the intent model's epoch guard ran.

`CompetitionFilterNativeBindingState` now scopes native acknowledgements to both
the captured binding epoch and the current intent epoch. Old acknowledgements
cannot mutate the new native binding or enqueue a dismissal for it. Existing
queued intent still reopens synchronously from actual native dismissal completion.
The popover, anchor, UIKit completion observer, transitions, Region sheet, and
filter selections are not redesigned.

Mounted rapid-close/reopen checks show no app cooldown after actual native
completion: the next host was observable on the same test observation or within
about 21 ms. Tests also cover duplicate open requests, late acknowledgements,
parent recreation, and retaining animated native transitions. They do not prove
the physical beta's perceived one-second delay is eliminated. Reopening while
UIKit still dismisses is intentionally queued, not overlapped. Its native
transition duration remains intact.

## All Results Badges

The current All Results renderer already uses
`CompetitionResultTableStatisticValue`, just like Results. It passes
`singleRecordTag` only to Best and `averageRecordTag` only to Average, using the
existing compact `CompetitionWCARecordTagView` and its upper-right (23,-6)
placement. No table geometry, shared badge design, or existing Results renderer
was changed. Pixel tests verify WR/CR/NR/PR in both corresponding value corners
while every row stays 36 points high.

WCA Live queries and adapters preserve separate single/average record tags.
Official WCA adapters preserve verified regional record metadata. They cannot
manufacture personal-record status when the source does not provide it.

An independently verified CubingChina gap was corrected: captured JSON contains
explicit `personalSingleRecord`/`personalAverageRecord` values of `PR`, but its
presentation adapter previously forwarded only regional badges. The shared
preview/competitor adapter now takes a recognized regional badge first, otherwise
an explicit corresponding PR field. No numerical comparison/inference occurs.
Regional-only model badges and global discovery classification remain unchanged,
so personal-only records cannot leak into global WR/CR/NR discovery.

A competition/person/source example is still needed to diagnose any additional
observed missing WR/CR/NR instance; the generic All Results renderer is not
missing those badges.

## Separator Investigation Only

The internal round boundary owner is `CompetitionResultRoundRow` in
`CompetitionResultsStyle.swift`. The header owns one bottom rule; the first data
row owns no rule; each subsequent data row owns one top rule. The table's outer
rounded border is separate. There is no duplicate internal boundary in this path.

The green advancement background belongs only to the rank cell inside row
content. The rule is a Canvas overlay on the entire row and uses opaqueSeparator.
There is no green-dependent rule opacity or round-count-specific rendering path.
Round count does affect the card's total height/centering and therefore its
window origin, so raster phase remains relevant to investigate, not a proven
cause. The source snaps using the global row origin and display scale, with a
one-physical-pixel gap/painted height.

The saved Beijing Wang four-round data was rendered as 2-, 3-, and 4-round
prefixes in light/dark at three vertical phases. The four-round profile test also
compared internal and adjacent header coverage at eight fractional origins in
both modes. In the tested light frames the internal gaps were 1/3 point at 3x,
and each seven-pixel contrast profile had one 56.333-level sample with zero
neighbors; no unequal peak shade or painted coverage was reproduced. Green
qualification exists in the actual fixture; its source does not draw a second
rule. This is simulator evidence, not proof of physical iOS 27.2 uniformity.
Concordia's specific physical case was not newly captured. The stationary
physical inconsistency remains unresolved. No separator code changed.

## Exact Source Changes

- `CubeFlow/Views/iPhone/CompetitionTabView.swift`: DEBUG size overlay,
  `CompetitionWrappingLayout.measuredSize`, inner name fit, and delegation from
  `topCuberChip` to the extracted production chip. Removed parallel width helpers.
- `CubeFlow/Views/iPhone/CompetitionTopCuberChip.swift`: production chip and badge.
- `CubeFlow/Views/iPhone/CompetitionFilterPresentation.swift`: native binding epoch
  state and the existing modifier's request/acknowledgement wiring.
- `CubeFlow/Views/Shared/CubingChinaLivePresentation.swift`: explicit personal-tag
  fallback in `preview` and `competitor`, keeping single/average separate.

Focused test additions/updates are in `CompetitionTopCuberPackingTests`,
`CompetitionTopCubersSizingTests`, `CompetitionPresentationBoundaryTests`,
`CompetitionNavigationLoadingTests`, and `CubingChinaUnifiedResultsTests`.

## Verification

Simulator: iOS 26.5, using Xcode 27.2 beta SDK; no physical acceptance claimed.

- First selection: 18 focused tests. Seventeen passed; one comparison incorrectly
  required UIKit's rounded hosting fit to equal fractional Layout width within
  0.01 point. Corrected the test to permit only one physical pixel, without
  changing production geometry or exact-fit packing assertions.
- Follow-up selection: all 10 tests passed, including the corrected real-chip
  test and four additional All Results/source/separator checks.
- Across these selections, 22 distinct focused tests have passing results.
  Coverage includes fractional exact-fit and just-too-wide boundaries, no rank
  skipping, rendered/intrinsic widths at 280/320/390/768, English/Chinese,
  accessibility text sizes, loaded-host recreation, width/content invalidation,
  three-row/expanded sizing, both appearances, progressive motion, rapid reversal,
  Reduce Motion, native Filter cycles, and badge provenance/placement.
- Logs: `focused-tests.log` and `focused-polish-records.log` under the task build
  directory. The first log retains its original test failure for transparency.
- `git diff --check` passed, including explicit no-index whitespace checks on
  newly added Swift files.
- The one final unsigned generic iOS Debug build passed. Log:
  `build/competition-chip-filter-oct17/unsigned-generic-debug.log`.

## Physical Acceptance Checklist

1. In both List and Glass, check chip readability/background in light/dark,
   red/orange/yellow circles, centered names/icons, and unchanged rank order.
2. Check the blue available-width/dimension label and chip widths. Any empty row
   tail must be too small for the next consecutive chip including its gap.
3. With normal and larger text, check first three visual rows, exact hidden count,
   expansion/collapse and rapid reversal. Scroll normally through loaded reused
   cards and verify the accepted deceleration remains smooth. Confirm native
   interactive Glass press feedback and Makati geometry remain intact.
4. Open/close/reopen Filter rapidly through X and outside dismissal, including
   repeated taps during dismissal, Region return, and retained filter selection.
   Distinguish waiting for native dismissal from any delay after it has completed.
5. Check verified WR/CR/NR and explicit PR in All Results, separately for Best and
   Average, without changing Round/All Results/Profile/Back behavior.
6. Compare stationary light-mode round separators in Concordia and Beijing. This
   remains observation only; no physical separator correction is claimed.
