# DEBUG Competition Capture Retention

October 16, 2026. New task; the earlier scrolling investigation is not reopened.
Physical scrolling pullback remains unresolved. No commit or push.

## Root Cause Established Before Implementation

The recording preference is read dynamically at gesture start and the production
collection delegate is already installed independently of recording. Capture
storage was static/app-lifetime; changing tabs did not itself clear that array.

The loss occurred BEFORE archival:

- A collector owned by the collection coordinator accumulated useful frames but
  archived only after the existing post-idle sampling interval.
- Its display-link callback stopped on a detached/deallocated scroll view or
  recording-off without publishing the buffer. A newly started gesture could
  also reset a previous still-finalizing buffer.
- Even if publishing were reached, `archive` checked the CURRENT recording
  preference, rejecting a capture that began while enabled but finished after
  recording was disabled.
- The diagnostics screen stored count in local `@State`, refreshed only onAppear.
  A capture arriving after that snapshot could not enable Share or update count.

`baseline-runtime.log` reproduces zero retained captures with the unmodified
implementation. The mounted Settings/Competitions TabView uses the production
virtualized collection/coordinator. Recording is enabled AFTER that collection
exists; native delegate entry points start/end a gesture. Returning to Settings,
removing the competition surface and disabling recording before post-idle
completion loses the capture. This baseline does not simulate the physical
pullback or claim to establish its cause.

## Small DEBUG-Only Correction

1. `CompetitionScrollOwnerDiagnostics.swift`: an app-lifetime observable capture
   store publishes only retained capture changes, still bounded to four. Archival
   is not rejected merely because recording has since stopped. Clear advances a
   generation so old pending collectors cannot repopulate cleared captures.
2. `CompetitionLongListAcceptance.swift`: each collector snapshots whether it
   started enabled and the store generation. It finalizes its LAST VALID frames
   on recording-off, detachment, duration limit or the next gesture instead of
   silently dropping them. A new gesture still requires the existing enabled
   check. The full post-idle path remains unchanged when the view stays available.
3. `CompetitionScrollDiagnosticsView.swift`: count and Share derive directly from
   the observable store, not an onAppear snapshot. Share remains disabled while
   recording or when no captures exist. The label says Captures, since interrupted
   recordings may be retained with explicit incomplete-coverage metadata.

No new timer, delay, scrolling compensation or animation was added. The existing
CADisplayLink remains the sampling clock and is invalidated on finalization.
The production collection, layout, delegates, glass, Makati sizing, Filter,
disclosure, results transitions and native Back are unchanged by this task.

## Export Semantics and Limits

- `captureFinalized`: the retained buffer has been closed.
- `gestureCompleted`: the native completion entry point was observed.
- `idleRecordingComplete`: the full existing post-idle observation was captured.
- `finalizationReason`: distinguishes full completion from recording-off,
  detachment, next-gesture interruption or the existing duration limit.

No measurements are fabricated after detachment. An interrupted capture can be
useful but must not be mistaken for complete post-idle coverage. Captures remain
memory-only and do not survive app termination. Existing sample/event caps remain.

## Focused Verification

Five unique focused unit checks and one targeted UI route passed on iOS 26.5
simulator. This does not constitute physical iOS 27.2 acceptance.

- `focused-tests.log`: the two existing diagnostics/export tests and generation
  clear test passed. The initial navigation fixture's other assertions exposed
  test selection of cached tab content, not a reason to relax completion checks.
- `owner-replacement-tests.log`: all THREE final lifecycle tests passed. They
  target the native selected controller and explicitly force owner replacement;
  hiding a TabView child alone does not necessarily destroy it. Completed gesture,
  retained frames, JSON export and replacement assertions remain intact.
- `ui-switch-navigation.log`: the real Settings switch -> real competition swipe
  -> Settings route PASSED, with asserted native switch values, nonzero capture
  count and enabled Share. No owner-timing launch flag enabled recording.
- The screenshot in `accepted-ui/` was inspected: recording off, one retained
  capture, Share available. Production and test code remain separate.
- `git diff --check` passed. The complete production `CompetitionTabView.swift`
  matches the before-task snapshot byte for byte. Frozen Filter, disclosure,
  Makati loader, result presentation/style and project hashes also match.

Earlier UI attempts are not credited as passes: native scrolling minimized the
tab bar, and a row-center automation tap did not activate the UISwitch. The final
test expands the native bar and taps the actual switch, asserting ON/OFF before
checking capture behavior. An uncredited pre-correction selector result was also
replaced with an explicitly identified current test entry point. No application
scrolling, navigation or animation was changed to accommodate automation.

Coverage:

- Settings -> Competitions -> Settings, with collection teardown and recording-off
  before post-idle finalization; valid samples and JSON survive owner replacement.
- Recording-off while the collection remains mounted retains a completed gesture.
- Clear rejects an older collector's late archive.
- One actual-app UI route uses the real Settings toggle, a real competition-list
  swipe, and checks nonzero count and enabled Share after returning to Settings.
  Captured summaries supply only data; no owner-timing launch flag enables capture.
- Existing focused diagnostics tests cover normal post-idle completion, meaningful
  hosted/view/offset measurements, four-capture bounds and exported JSON.

The initial baseline test compile needed an explicit Combine import; corrected
before recording the failing runtime baseline. No broad test suite or generic iOS
build is part of this task.

## Physical Acceptance Still Needed

Repeat the user's exact List-mode sequence on the iPhone 17 Pro/iOS 27.2 beta.
Count should increase and Share should enable after recording is switched off.
Export the file; it should include nonempty `owners` frames with offset, viewport,
cell and hosted-content measurements. Repeat in Glass if convenient. Native
gesture/presentation behavior on that beta is not established by simulator tests.

Only this diagnostics pipeline is being corrected. The original physical
scrolling pullback remains UNRESOLVED.
