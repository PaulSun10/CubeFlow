# Top Cubers Profile, Bounds, Solve Spacing, and Physical Diagnostics

## Implemented Changes

### Existing Full-Page Profile Navigation

The WCIF adapter already uses `person.wcaId` as `CompetitionTopCuberPreview.id`.
No name lookup or data-model/cache migration is required. A selection accepts
the trimmed canonical WCA ID syntax (four digits, four uppercase ASCII letters,
two digits). This is identity-format validation, not a claim that the remote
profile exists. Missing or malformed IDs receive no chip Profile gesture or
Profile accessibility affordance. Existing card-level navigation is unchanged.

The previous chip gesture opened Competition Detail. It now routes its actual
ID/name to the existing `WCAProfileView` through the native hidden NavigationLink
pattern already used in Explore and the Profile itself. The navigation owner is
CompetitionBrowserView, outside reused collection cells. There is no new sheet,
popover, cover, external website, profile implementation, animation, or loading
system. In particular, the existing item-based compatibility helper would use
a sheet below iOS 17, so this route deliberately uses the existing native
NavigationLink API that also supports iOS 15.

The entire chip's existing rectangular content shape uses one replacement tap
gesture, not an additional gesture layer or nested Button. The badge, name,
padding and remaining chip surface share that action. Valid chips also expose
a combined accessible button action. Intrinsic metrics, ink, palette and glass
styling are unchanged.

WCAProfileView, its view model/service, profile caching, unavailable/error UI,
and native Back are unchanged. Browser collection/data/disclosure owners are
not replaced or cleared. The existing normal freshness policy remains in place;
no profile-specific reload or scroll-offset restoration was added.

### DEBUG Bounds Toggle

Settings > Development contains one new switch, **Top Cubers Debug Bounds**.
It uses AppStorage key `competitionTopCubersDebugBounds`, default false, and
persists normally. The existing shared `competitionSizeDebug` modifier observes
that key, controlling both chip outlines/labels and section outlines/labels.
It keeps the content branch stable, changing only layout-neutral overlays.
Overlay geometry and labels remain excluded from hit testing and accessibility.
Both List and Glass call the same chip and section modifier.

The binding, switch, modifier implementation, key declaration, and all new
diagnostics are compile-time DEBUG-only. Release's modifier still returns self.
No new Settings page or overlay design was introduced.

### Solve-Tail Spacing

Per-side padding changes from 4 to **6 points**. Adjacent values therefore gain
**4 points** of effective separation. The measured per-column value/header
widths are unchanged; no 62-point floor was restored. Total additional width
remains the sum of measured widths plus two paddings per solve column. The first
Results header, blank later headers, original summary plan, 36-point rows,
typography, badges, shadows, independent scroll owners, and no-bounce behavior
are unchanged.

## Filter Diagnostics: Improved Coverage, No Production Fix

Enable the existing `--competition-filter-timing` launch argument in a DEBUG run.
The existing non-recognizing observer is now maintained on visible windows in
the anchor's own app scene, using native visibility/key/activation notifications.
There is no polling. Observers have no target/action, never recognize a gesture,
cannot prevent or be prevented by other recognizers, and never delay or cancel
touches. They detach when the anchor is removed.

Every begin/end/cancel is logged, not just touches near the anchor. Each event
includes its touch identity, input/delivery timestamps, event window identity,
actual native UIView target ancestry, touch coordinates, current model anchor
and target bounds in screen coordinates, and projected presentation-layer
anchor bounds when affine projection is supported. Coverage records include
window identities/levels, OS, scene activation and display scales. The existing
action/intent/generation/binding/native lifecycle/first-surface events remain.
The event ring is bounded to 512; atomic JSON file writes use a serial background
queue rather than doing disk I/O in the input callback.

Limitations remain explicit: these are the app scene's windows, not OS-owned
input routing. A SwiftUI control's native hit owner can be its hosting surface,
so UIView ancestry is not a fabricated SwiftUI-control identity. The
`filter-touch-*` prefix means the coordinate is near the model anchor (or that
its gesture began there); only `open-request` proves the toolbar action ran.
Initial coverage can precede layout; use each touch's freshly converted bounds.
An absent touch event still does not prove OS suppression. The physical beta's
one-second rapid-reopen cause remains unproven. Production Filter state,
binding, native presentation and animation code is unchanged.

### Manual Filter Capture

1. In Xcode's DEBUG Run scheme, enable `--competition-filter-timing`; run the
   current source on the iPhone yourself. Do not enable acceptance fixture flags.
2. Open Competitions normally. First open Filter; close with X and immediately
   reopen; close and wait about two seconds before reopening; then perform two
   more immediate close/reopen cycles. Leave the filter selection unchanged.
3. Note which openings actually lagged. A short screen recording helps correlate
   observed visibility with the input/native events. Keep the session short so
   the bounded event history still contains the first opening.
4. After the last transition settles, allow pending diagnostic writes to finish,
   then download the App's data container through Xcode. Supply
   `AppData/tmp/competition-filter-lifecycle.json`. Filtered `[FilterLifecycle]`
   console text is supplementary: it does not contain all JSON target fields.

Interpretation: touch delivered but no action, with a covering native target,
supports hit-routing/transition suppression in that observed window. Prompt
touch but late `open-request` localizes delay before application intent. Prompt
intent/binding but late first native surface localizes it after intent. Queued
intent before `dismissal-finished` must be distinguished from extra delay after
native completion. Missing coverage or unsupported projection prevents a stronger
conclusion; it is not permission for a guessed production fix.

## Separator Diagnostics: Screen Geometry, No Paint Change

Enable `--competition-separator-screen` in a DEBUG run. A transparent, non-hit
testing UIView marker is placed as a sibling/background of each existing Canvas
boundary. It never changes the production rule, spacer, opacity, green fill,
row sizing, clipping, shadow or scroll configuration.

When the user takes a normal iPhone screenshot with boundary markers mounted,
UIApplication's screenshot notification saves a geometry snapshot. The last four
are retained in `competition-separator-screen.json`. This needs no extra gesture,
timer, polling, UI control, or automatic debugger attachment. The same explicit
capture can optionally be invoked from the debugger on the main thread using
`po CubeFlow.CompetitionSeparatorScreenCapture.capture()`.

Each boundary records the original SwiftUI global origin, the exact local paint
Y computed by the unchanged Canvas formula, window/model screen coordinates,
environment/display/native scales, screen/native/window bounds, affine-projected
presentation coordinates, and ancestor transforms, rasterization scales,
contents scales, clipping flags, opacity and animation keys. Unsupported 3D
projection is reported, not guessed. Screen Y and nativeScale are both retained
so display zoom/render-pixel coordinates need not be mistaken for native pixels.

This is a public sibling geometry marker, not access to SwiftUI's private Canvas
texture. It cannot prove which pixels were clipped/filtered inside that texture.
The screenshot notification snapshot is nearby in time, not an atomic sample
of the screenshot's compositor frame. Active animation keys or different model/
presentation positions disqualify it as proof of settled pixel phase.

### Manual Separator Capture

1. Enable `--competition-separator-screen`, then run the DEBUG source yourself.
   Use Light Mode and normal competition data.
2. Open a competitor's All Results and find a normal two-round event. Stop
   scrolling, let animations finish, and take one original iPhone screenshot.
3. Repeat for a visibly inconsistent three-round event (Concordia Fall Foliage
   2026, 2x2/3x3) and the reported Beijing Wang Yiheng four-round 3x3 case.
   Do not take unrelated screenshots before exporting the last-four history.
4. Supply the original, unresized images, competition/person/event names, and
   `AppData/tmp/competition-separator-screen.json` from the App data container.
   The console's `[SeparatorScreen]` line confirms the saved path. Wall-clock
   timestamps in each snapshot help match images to geometry.

If boundaries are empty, the marker was not mounted: verify the DEBUG argument
and that All Results was open, rather than interpreting absence as normality.
Fractional final pixel edges or non-unit ancestor scale would support a geometry
mechanism. Different layout versus presentation coordinates would localize a
transform stage. Equal settled geometry with unequal screenshot coverage would
instead leave Canvas rasterization/clipping/filtering as a distinct investigation.
None of these hypotheses is declared physically proven in this pass.

## Device Permission Boundary

No physical installation, launch, attachment, logging or interaction was done
by the agent. The user's manual-capture preference is preserved. The procedures
above are user-operated actions; any future agent-operated device work requires
fresh explicit authorization. Filter and separator remain unresolved physical
bugs, not claimed fixes.

## Files Changed

- `CubeFlow/Views/iPhone/CompetitionTopCuberProfile.swift`
- `CubeFlow/Views/iPhone/CompetitionTabView.swift`
- `CubeFlow/Views/iPhone/SettingsTabView.swift`
- `CubeFlow/Views/iPhone/CompetitionResultsStyle.swift`
- `CubeFlow/Views/iPhone/CompetitionFilterPresentation.swift`
- `CubeFlow/Views/iPhone/CompetitionUIDiagnostics.swift`
- `CubeFlowTests/CompetitionAllResultsTableTests.swift`
- `CubeFlowTests/CompetitionProfileDiagnosticsTests.swift`
- `CubeFlowTests/CompetitionTopCubersSizingTests.swift`
- `CubeFlowUITests/CompetitionTopCuberProfileAcceptanceTests.swift`
- This report.

Frozen-file hashes match the pass's starting copies for the original chip/ink/
colors, expandable sizing/motion, Top Cubers loader, native Result Card/Back,
Filter controls, shared result table, WCA Profile and service, WCIF adapter,
compatibility helpers, and project.pbxproj. A DEBUG-stripped source comparison
also verifies unchanged production Filter code and separator owner/paint code.
No scroll physics, offset compensation, new profile loading, unrelated cleanup,
commit, push, simulator/device-data deletion or project-file edit was performed.

## Verification Results

- Xcode 27.2 beta / Swift compiler 6.4, app language mode 5, default MainActor
  isolation, iOS 15 deployment target. A separate strict Swift-6/default-MainActor
  check of the actual new Profile selection and WCIF preview declarations passes.
- **23 distinct focused tests have passing results: 19 unit/native-host tests
  and four UI tests.** Deduplicated names and logs are in
  `build/competition-profile-diagnostics-oct17/`.
- The first selection passed all 17 unit tests and both real Browser Profile UI
  tests. The latter tap name, badge and chip edge in List/Glass, verify no modal,
  return three times to the same expanded card and Y position, then drag from
  a chip to verify scrolling rather than Profile navigation.
- Additional UI tests passed for the actual Development switch's persistence
  across app relaunch and the original Filter controls, Region return, repeated
  reopen and outside dismissal with diagnostics enabled.
- The expanded test fixture initially needed an explicit Combine import and
  MainActor annotation on its nested observable state; corrected before those
  additional tests ran. Two subsequent fixture assumptions failed: unmounted
  versus mounted hosting fits included different safe areas, and a bounds-only
  update correctly produced no preferred-size invalidation at all. The fixtures
  now compare equally mounted hosts and permit no fitting callbacks on a purely
  visual update, while requiring every fitting callback that does occur to keep
  the same height. The original mandatory first-fit/reuse checks remain intact.
- The final eight-test selection passed all Profile/diagnostics tests and the
  updated real collection-cell production-chip sizing test. It covers actual
  native legacy push/Back, ID rejection, live bounds colors and intrinsic/hit
  neutrality, window observer attachment/removal and cross-window coordinates,
  two-/three-/four-round marker neutrality, non-unit native transforms, screenshot
  notification export and the four-capture bound, plus List/Glass first-fit,
  recreation, Dynamic Type/localization, live bounds toggling and expansion.
- Existing solve formatting, first-header-only semantics, original summary
  geometry, separate horizontal owners, no-bounce scope, badges, record ink/
  colors and disclosure/reversal checks passed in the first selection.
- The diagnostics source emits no diagnostic declarations with DEBUG disabled
  (verified via compiler SIL generation). Source-boundary comparisons verify
  the Debug settings/overlay exclusion and unchanged production Filter and
  separator drawing. This is not a claim that a separate Release app build ran.
- **One final unsigned generic iOS Debug build passed** against the final
  production source: `final-unsigned-generic-debug.log`. No second generic build.
- `git diff --check` and explicit whitespace checks for new/untracked touched
  files pass. All frozen-file hashes match.

These are simulator/compiler findings, not new physical-device results. The
user's accepted ink/colors and other frozen features are preserved, but the new
chip navigation, toggle and 6-point spacing still merit normal phone acceptance.
Filter's physical rapid-reopen lag and separator contrast remain unresolved;
this pass completes diagnostic preparation rather than declaring either fixed.
