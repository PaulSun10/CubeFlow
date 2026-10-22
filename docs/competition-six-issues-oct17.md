# Competition Physical Acceptance Follow-up, October 17

## Scope

Turn-specific starting copies, strict-concurrency probes, and verification logs
are in `build/competition-six-issues-oct17/`. Existing dirty changes are retained.
No commit, push, signed installation, or physical-device acceptance is claimed.

## 1. Formatting Isolation

Active tools: Xcode 27.2 beta (27B5019j), Swift compiler 6.4. Checked-in Debug
settings resolve to Swift language mode 5, default MainActor isolation,
approachable concurrency enabled, and iOS 15 deployment. Compiler version and
language mode are not interchangeable. The user's local build override is not
known; the previous successful Swift-5-mode build did not prove Swift-6 safety.

`CompetitionAllResultsDisplay` inherited default MainActor isolation, although
it only reads immutable Sendable result data and calls the already nonisolated
`WCAResultFormatter`. Passing `attempts` to `Sequence.map` crosses into its
synchronous function-parameter type. A strict Swift-6 typecheck of the actual
extracted declarations reproduces loss of MainActor isolation at that boundary.

The formatting enum is now explicitly `nonisolated`. Its adjacent `value`
method switches directly on the statistic instead of invoking that enum's
default-isolated synthesized Equatable conformance. The first strict probe
identified this second dependency; the final strict probe passes. No isolation
suppression, actor assumptions, Task, or async conversion is used. UIKit font
measurement and view/layout helpers retain their normal UI isolation.

## 2. Solve-Tail Spacing

Each solve previously reserved at least 62 points plus 10 points on each side.
That made a short result occupy at least 82 points, regardless of its ink width.
The solve-only plan now measures actual formatted values without the 62-point
floor and uses four points per side. The first column still accommodates the
localized Results header; later headers remain empty.

Mounted production-cell checks compare adjacent cell positions and formatted
text widths against the previous 62/10 plan, requiring at least a 50% reduction
in inter-value space, including longer times, DNF, and DNS. The summary plan,
36-point rows, native horizontal owners, bounds, bounce configuration, and
table decoration are unchanged.

## 3. Between-Round Separators: Unresolved

Production separator drawing is unchanged. There is still exactly one boundary
owner per internal round transition. Qualification green remains confined to
the rank cell; it does not supply an additional full-width separator. The
shared table shadow surrounds the entire table, not individual internal rows.
There is no two-/three-/four-round style branch.

Further hierarchy inspection distinguishes the coordinate/raster stages:

- The Canvas snaps using SwiftUI `GeometryProxy.frame(in: .global)` and the
  environment display scale. This is layout geometry, not a measurement of the
  final on-screen presentation layer or its raster coverage.
- Its snapped local paint origin can be up to half a physical pixel above or
  below the local top edge. Whether the physical render pipeline clips or
  filters that offscreen paint is not established by the earlier layout tests.
- The native Result Card transition animates container opacity. SwiftUI's card
  scale animates from 0.97 to exactly 1; no source-level persistent non-unit scale
  was found. This does not measure the physical device's settled layer tree.
- More rounds change total card height and its centered/scrolling placement.
  They do not change the separator owner, paint color, or nominal thickness.

The earlier simulator fractional-origin tests cannot discriminate a physical
offscreen-raster/clipping issue from a final-screen pixel-phase issue. Repeating
them would not establish a new root cause. No speculative opacity, thickness,
row-height, green-background, or compositing change is made. A settled physical
screen/layer measurement remains necessary to resolve this issue.

## 4. Filter Rapid Reopen: Unresolved Physical Attribution

Production Filter code is unchanged. User intent and native binding each carry
a generation. Old dismissal acknowledgements cannot close a newer generation.
Reopen intent arriving during a real dismissal is queued until its native
transition completion; it is not presented over the dismissing controller.
The completion callback then publishes the next generation synchronously.
There is no application cooldown, arbitrary delay, polling, or retry loop.

The existing DEBUG `--competition-filter-timing` capture observes:
passive window touch delivery, toolbar action (`open-request`), intent,
native binding request/acknowledgement, content creation, native will/did appear,
first observable native surface, and actual dismissal completion. Its passive
recognizer does not recognize/prevent/delay touches. Logging is DEBUG opt-in.

The saved earlier simulator timing capture shows warm action-to-intent below
2 ms, binding around 3-5 ms, first observable native surface around 81 ms, and
native did-appear around 875 ms. These are separate milestones: did-appear is
not the first visible frame. That capture's opens were not true physical taps
during dismissal, so its approximately 850 ms native transition cannot be
declared the cause of the user's approximately one-second physical reopen lag.

The focused native-host tests exercise queued reopen and repeated native
dismissal cycles. Automated UI synchronization can wait for native idle and
therefore cannot substitute for the physical immediate-reopen sequence.
Without its touch/action/binding/native timestamps, it remains unknown whether
the physical tap is suppressed, intent arrives late, or native presentation
waits. No unsupported presentation/animation change is made.

### Follow-up Diagnostic Coverage Audit

The physical iPhone 17 Pro was subsequently confirmed connected using a
read-only `devicectl list devices` query. Fresh approval was requested before
installing, launching, attaching to, or otherwise interacting with its app;
none of those actions has been performed in this continuation.

The existing input probe attaches only to `anchor.window` and records a touch
only when it falls in the converted toolbar anchor target. Therefore a missing
`filter-touch-began` entry alone does not prove the OS failed to deliver a tap:
another native window or target-coordinate mismatch could be outside this
probe's coverage. Physical diagnosis must first establish the actual toolbar
target and active native presentation windows. A delivered touch followed by
prompt intent but delayed native presentation can be classified from existing
events; an absent touch requires this additional coverage check.

The separator probe stores SwiftUI global CGRects in memory, not a final-screen
layer/raster export. The scroll-owner export is scoped to Competition Browser
UICollectionView scrolling and is not evidence about internal Result Card
round boundaries. Reusing that export as though it measured separators would
be incorrect. The next useful inspection is the actual settled physical
hosting/presentation hierarchy, rather than another simulator fractional-origin
test. No further tests, generic builds, or application source edits were made
for this coverage audit.

## 5. Record Glyph Centering

The old Text frame centered the font's advance/line box, not the event's ink.
The badge now draws that same font glyph's CoreText outline at the same scaled
13-point size. It translates the actual path-bounds midpoint to the unchanged
25-point circle's midpoint, flipping CoreText's Y-up coordinates explicitly.
This uses each glyph's own geometry, not per-event or guessed global offsets.
There is no bitmap cache, hidden measurement pass, or asynchronous publication.
The Shape is explicitly nonisolated and receives its font name as immutable
input, rather than accessing the UI-owned font registry while drawing. A
separate strict Swift-6 check of the actual Shape declaration passes as well.

Tests check all 17 official event outlines at normal and doubled scale, preserving
their original ink dimensions and verifying both axes' centers. Existing real
chip/first-fit/animation checks cover the unchanged outer geometry.

## 6. Record Glyph Colors

The badge explicitly applied `.foregroundStyle(.primary)`; tinting the glass
background was not a red/orange/yellow glyph foreground. Primary becomes white
in dark/inherited environments. The actual outline now explicitly fills with
the existing category color: WR red, CR orange, NR yellow. Tier-text fallback
uses the same explicit foreground. No palette or circle dimensions changed.

The native circle remains `.regular.tint(color.opacity(0.3))` without
`.interactive()`. Outer interactive card glass is untouched. Pixel checks use
both parent presentations and light/dark schemes, including an inherited white
foreground, to distinguish saturated colored ink from a tinted background.

## Exact Changes

- `CubeFlow/Views/iPhone/CompetitionResultsStyle.swift`: pure formatting isolation
  and solve-tail width/padding only.
- `CubeFlow/Views/iPhone/CompetitionTopCuberChip.swift`: ink-centered vector glyph
  and explicit tier foreground only.
- `CubeFlowTests/CompetitionAllResultsTableTests.swift`: off-actor function
  reference and mounted solve-tail spacing regression coverage.
- `CubeFlowTests/CompetitionTopCuberPackingTests.swift`: official glyph bounds
  and actual native-glass foreground pixel coverage.
- This report.

Frozen-file hashes verify CompetitionTabView, CompetitionExpandableTopCubers,
CompetitionNativePresentation, CompetitionFiltersView, CompetitionResultTable,
and project.pbxproj against this pass's starting copies. The Filter presentation
file also remains unchanged.

## Authorized Storage Cleanup

Fresh authorization allowed removing unused simulator resources. Only runtimes
with no associated device were removed: iOS 17.5, iOS 18.6, watchOS 26.5, via
`simctl runtime delete`. Available Data-volume space increased from about 14 GiB
to 34 GiB immediately afterward. Retained all simulator device/application data,
iOS 26.5 for these tests, iOS 27.0/27.1, DeviceSupport, current DerivedData,
diagnostics, and source. No unrelated cache or user-file cleanup.

## Physical Acceptance

1. List and Glass, light and dark: confirm the unchanged badge circle and chip
   footprint, centered event ink, and red/orange/yellow foregrounds. Include
   Pyraminx, Square-1, Clock, and blindfolded icons.
2. Scroll loaded competitions normally; verify accepted smooth reuse, first
   three Top Cubers rows, progressive reveal/reversal and native glass feedback.
3. Expand All Results: summary columns must remain unchanged; scroll each event
   independently and inspect compact solve gaps, long values, DNF/DNS, single
   Results header, and unchanged horizontal/vertical boundaries.
4. Filter: first open, immediate reopen during dismissal, reopen after native
   dismissal, and repeated rapid cycles. Use existing DEBUG timing capture to
   classify touch delivery versus state versus presentation; the lag is not
   declared fixed by this pass.
5. Separators: inspect stationary light-mode Concordia three-round and Beijing
   four-round tables alongside two-round cases. The inconsistency remains open;
   this pass has not changed separator rendering or claimed physical acceptance.

## Verification Results

- Initial current-source simulator build-for-testing passed before the visual
  edits. The newly introduced outline helper initially had a local-variable
  redeclaration compile error; corrected before any tests executed.
- Strict Swift-6/default-MainActor/complete-concurrency typechecks pass for the
  actual formatting declarations and final outline Shape. The probes preserve
  the earlier failures rather than presenting a Swift-5 build as Swift-6 proof.
- Nineteen distinct focused unit/native-host tests now have passing results:
  six All Results tests, six packing/badge tests, four disclosure animation
  tests, one production-chip first-fit/reuse test, and two native Filter tests.
- The first 19-test selection had 18 passing tests and one failing new pixel
  fixture (11 assertions). Inspection of its screenshots showed colored ink;
  the fixture mixed named SwiftUI coordinates with window bitmap coordinates.
  It now uses a native background anchor converted into the actual window.
  The pixel test passed, and passed again with the final Shape declarations.
  No color thresholds were loosened to make this pass.
- One focused native Filter UI test passed, including its original controls,
  Region return, retained selection, repeated reopen, and outside dismissal.
  This is simulator verification, not a physical immediate-tap timing capture.
- Final ink regression selection: three tests passed (all 17 outlines,
  saturated foreground pixels in four environments, production first-fit/reuse).
- Across the selections, 20 distinct tests have passing results. No broad
  unrelated test suite ran. Compiler work for the test target is not a claim
  that every compiled test was executed.
- The queued-reopen native test observed the next mounted host on the same
  observation as dismissal completion (about 0.004-0.010 ms measured after that
  observation). This rules out an additional application cooldown in those
  simulator runs, not physical touch suppression or the native transition cost.
- Light/dark native-glass badge and All Results screenshots were exported and
  inspected under the task's `screenshots/` directory.
- `git diff --check` passed, as did explicit whitespace checks for the newly
  added/untracked touched files. All frozen-file hashes match; Filter's source
  also matches its starting copy.
- The single final unsigned generic iOS Debug build is recorded in
  `final-unsigned-generic-debug.log`: **BUILD SUCCEEDED** against the final
  production source. No second generic build was run.
- Data-volume free space after verification remains about 33 GiB, compared
  with about 14 GiB before the authorized runtime cleanup.

Four implementation corrections are verified within this pass. Filter physical
rapid-reopen attribution and stationary physical separator inconsistency remain
unresolved; no simulator-only result is presented as acceptance for either.
