# Physical Competition UI Corrections: In Progress

The acceptance reference is the user's iOS 27.2 beta (24B5084k) device. Simulator
checks use iOS 26.5. The phone subsequently became reachable and the user approved
signed install/launch and focused testing without erasing its data. Device results
are recorded separately below; simulator results do not establish physical acceptance.
This document supersedes the resolved-status claims in the earlier closeout where
the new physical report contradicts them. The six-area goal remains open.

## Current State

1. **Native interactive glass restored with an independently active surface.** Git
   `c551de97` applied glass directly to foreground content. Restoring that hierarchy
   also restored the short-disclosure movement. An inert background did not retain
   real feedback. The current background is instead a real card-sized plain Button
   carrying the same `.regular.interactive()` material and rounded shape. Header
   touches reach that surface and perform the original navigation action; disclosure
   remains independently tappable in the stable foreground. Header accessibility
   actions remain, and the background adds no duplicate accessibility control.
   This is deliberately not the original foreground-wrapping hierarchy. A real
   surface press produces 0.563pt movement in the simulator, whereas the identical
   noninteractive-glass control produces zero. No custom glass animation is added.
2. **Top Cubers: partially corrected, not resolved.** Async loader completion used
   to mutate hosted-cell state during dragging/deceleration, bypassing the native
   list's existing idle-publication guard. Fetches now continue immediately, but
   completed display state is held until the collection delegate reports idle.
   This is gesture-driven, not a timer, cache change, offset compensation or global
   animation suppression. A pending response is not fetched twice. List/Glass
   interior-cold checks pass. With the independently active surface, four actual
   Makati disclosure taps report zero title/relative-title/viewport drift, preserve
   the 419-to-466pt height change, and retain real header navigation/return state.
   A DEBUG-only overlap hook invokes the actual collapse action at native drag
   start, avoiding XCTest's post-tap quiescence. List and Glass checks show stable
   model anchors and no backward presentation movement. This is not equivalent to
   measuring physical frame pacing or every rapid tap-then-swipe timing window.
3. **Native Back visual exposure: candidate verified in simulator.** The accepted
   exact-once dismissal/event-forwarding path is unchanged. A measured aperture in
   the scene dimmer reveals the actual native Back rather than drawing a substitute
   or reparenting UIKit-owned views. Only that native control has its tint adjustment
   restored while exposed; its pressed state is forwarded and cleaned up. Other
   background hit regions remain blocked. Exposure is absent without a result modal
   and removed on Profile navigation/dismissal. Tests compare a native Back pixel
   before/after presentation, exercise highlight forwarding, toolbar rebuilding,
   and the original no-card action. Physical appearance/feedback still needs testing.
4. **Round separators: candidate verified in rendering matrix.** Header/round
   hairlines previously used locally aligned, translucent Canvas strokes. They now
   fill a globally pixel-aligned one-pixel rectangle using `opaqueSeparator`, so
   local fractional origins and different underlying fills cannot vary their
   intended shade. Outer table borders and ordinary results-table Dividers remain
   distinct and unchanged. Light/dark short/multi-round OH rendering and horizontal
   scroll checks pass. This does not prove which stroke was visible in the user's
   unreproduced physical screenshot; physical comparison remains required.
5. **Filter: immediate surface animation candidate.** Keep the existing native
   popover, shared toolbar capsule and generation/lifecycle guards. Its actual
   presented surface animates opacity/0.97 scale in 0.18s and out in 0.16s using a
   separately keyed Core Animation group, while
   the delayed native capsule morph remains disabled. Explicit close waits for this
   short animation before changing the native presentation binding. Actual layer
   opacity samples prove intermediate opening/closing frames, and mount takes less
   than 0.3s in the focused check. Twenty-cycle reopen, queued reconstruction and
   background/foreground checks pass. The real Region-return/outside-dismissal UI
   check also passes; the outside path records the short layer animation starting
   and completing. Physical appearance/feedback remains unverified. See the native
   lifecycle baseline below before interpreting lifecycle duration as input latency.
6. **Round / All Results: rendered animation candidate.** The previous animation
   modifier was attached to the identity being replaced. A stable ZStack now owns
   the conditional crossfade/height update (0.24s); premeasurement remains keyed to
   content/width/language. Both directions produce more than three distinct rendered
   frames while retaining the same native modal, selection, outer alpha and transform.
   Existing outer card opening/closing durations and Profile wiring are untouched.
   Physical perceptibility and absence of flashes still need acceptance.

## Experiments Not Retained

- A SwiftUI overlay for disclosure still gave 1.77pt Makati title drift.
- A sibling native hosting-view experiment still gave 1.14pt drift.
- Temporarily toggling card interactivity during disclosure gave 7.73pt drift.
- Moving the independent hosting view beside the cell contentView, rather than
  inside it, still gave 1.35pt drift. This variant is also removed.

All these experiments are removed. Do not restore them or weaken the one-point
assertion to manufacture a pass. The expandable/wrapping geometry is unchanged;
its existing action was extracted for the DEBUG overlap hook without changing
duration, entry identity, wrapping, three-row counting, or expansion behavior.

## Verification Evidence

Evidence folder: `build/competition-physical-goal-oct15/`.

- `first-focused.log`: three rendering/navigation cases passed and List disclosure
  passed; Glass failed. The full run is **not** a pass.
- `native-disclosure-host.log`: pending-response/gesture test passed; failed native
  sibling-host disclosure experiment. The full run is **not** a pass.
- `back-and-filter.log`: five cases passed, including native no-card Back, modal
  exact-once Back, toolbar rebuilding, twenty-cycle Filter stress and reconstruction.
- `rendered-motion-and-cold.log`: four cases passed: actual intermediate Filter
  opacity with prompt mounting, forward/back rendered result transitions, and List/
  Glass cold publication during an interior drag.
- `disclosure-ownership-and-regressions.log`: scrolled-collapse, actual Detail Back
  and Filter scene recovery passed. The temporary interactivity-toggle experiment
  failed; the full run is **not** a pass. That experiment was then removed.
- `git diff --check` passed after removing experiments.
- `feedback/interactive-surface.log`: native feedback/control and Makati glass
  disclosure pass (3 tests).
- `feedback/navigation-and-drag-overlap-corrected.log`: actual Makati header
  navigation/return and mounted List/Glass narrow/dark layout pass. The two overlap
  checks failed an invalid finger-versus-presentation timing assertion; this whole
  run is not a pass. Model and GPU presentation coordinates can be one frame apart.
- `feedback/overlap-and-cold-regressions.log`: corrected List/Glass overlapping
  collapse checks and List/Glass interior-cold checks pass (4 tests). The one-point
  anchor/no-pullback tolerances remain; no offset compensation was introduced.
- `final-unsigned-generic-debug.log`: the one final unsigned generic iOS Debug
  build passed. No further generic build is permitted for this pass.

Frozen project/advancement/transport SHA-1 values remain:

```
0aadcf8c7dd61852886cb8babdfd4ca5ff2ad70f CubeFlow.xcodeproj/project.pbxproj
16a33ce2961ce6a2054ecf8fb5c3c62da2c9d905 CubeFlow/Views/Shared/CompetitionAdvancement.swift
f8c05909c7cb5e4fcc37302c0729a149a90f50f6 CubeFlow/Views/Shared/CubingChinaLiveTransport.swift
```

## Remaining Physical Acceptance

Check original-feeling glass feedback and header navigation, Makati disclosure in
both appearances, rapid upward scrolling during long collapse, and cold-arrival
frame pacing. Compare exposed native Back, separator shades in light/dark and
horizontally scrolled tables, immediate/repeated Filter with Region return, and
both internal result transitions. Passing geometry tests alone does not establish
subjective smoothness or perceptibility. No new native transport/data work is needed.

## Continuation: Interaction and Timing Controls

The previous goal turn made implementation/test progress; this continuation also
produced new counterfactual evidence. No process was restarted because a poll timed
out. All test sessions below completed before another session started.

- `continuation/ownership-and-outside.log`: original interactive Makati still fails
  (1.98pt title drift); the actual Filter Region/reopen/outside sequence passes.
  `original-interactive-ancestry.json` records the glass host and cell animating
  different height deltas (18pt and 47pt at the captured phase) on 0.44s springs.
  Recorded view transforms are identity. This does not support attributing the
  movement solely to a scale transform.
- `continuation/resize-owner-and-filter-duration.log`: programmatic disclosure with
  no explicit SwiftUI animation passes. `programmatic-animated-resize.log` also
  passes the programmatic animated control. Each exercises List and Glass. Thus a
  real press, not content expansion alone, remains a necessary discriminant in the
  current reproducer. Do not change all layout animation based on the height trace
  alone.
- `continuation/separate-host-and-layer-motion.log`: the cell-level sibling-host
  experiment fails (removed), while actual Filter Region/outside checks and opacity
  sampling pass with the separately keyed layer animation. The original
  `UIView.animate` attempt could finish in 30-50ms despite requesting 180ms; the
  explicit animation key retains the intended visible duration.
- `continuation/filter-anchor-transaction.log`: moving the popover anchor and adding
  scoped transaction modifiers did not remove the native lifecycle tail. That
  anchor experiment is removed; original popover attachment remains.
- `continuation/filter-controlled-timing.log`: newly added absolute native-phase
  limits failed for the original no-animation control too (open 0.548s, close
  0.538s). Those limits incorrectly equated `isBeingPresented` with input latency.
  They are not an established product invariant or evidence that animation alone
  introduced that full delay.
- `continuation/filter-relative-timing-and-ownership.log`: both selected tests pass.
  The DEBUG-only no-surface-animation control measures open 0.537s / close 0.536s.
  The animated path must mount within 0.3s, render intermediate opening/closing
  opacity, and stay within the same-runtime baseline plus its 0.18s/0.16s visual
  duration and 0.15s scheduling tolerance. Queued reopen after reconstruction also
  passes. Existing generation and cancellation guards are unchanged.

The layer group animates the existing native presented surface; it does not draw a
popover or simulate Liquid Glass. The no-motion switch is DEBUG-only, not a product
setting. Native lifecycle timing is now explicitly separated from first visibility
and the requested visual animation. Physical input responsiveness remains part of
acceptance, not inferred from these callback timestamps alone.

At this earlier stage the physical phone was unavailable. The subsequent device
run below supersedes that availability statement. No iOS 27.2 simulator is installed.

## Physical Device Run: October 16

The approved iPhone 17 Pro is running the exact acceptance OS, iOS 27.2 / 24B5084k.
The initial signed test attempt failed before installation because generated
`CubeFlow.app` carried Finder metadata. Only `com.apple.FinderInfo`/`ResourceFork`
metadata in that generated app was removed; source/project signing and app data
were not modified. The retry installed and ran the signed app.

`device/focused-device-retry.log`: all five selected mounted tests passed on device:
original no-card Back, modal exact-once Back, toolbar reconstruction, whole-window
background blocking/restoration, and intermediate Filter surface animation with
prompt mounting. The UI-test runner exited code 74 before establishing its IDE
connection, so that mixed command is **not** an overall pass and establishes no
physical glass/disclosure UI result. `device/glass-ui-retry.log`, the separate
no-rebuild UI retry, failed at the same IDE/runner handshake before executing any
tests. This is a tooling limitation, not a passed or failed product assertion.
After the user confirmed the phone unlocked and available, one further no-rebuild
attempt (`device/glass-ui-unlocked.log`) failed at the same refused
`XCTestDriverInterface:XCTestManager_IDEInterface` channel, before receiving its
test configuration or executing tests. That rules out an assumed locked-phone
explanation; it does not identify the underlying DTX/toolchain cause. No Xcode or
device service was restarted, no pairing/signing configuration was changed, and
no app data was erased. The signed debug app remains installed and was relaunched
normally for the requested hands-on acceptance. No further generic build ran.

### Completion Gate

The previous turn made progress through five passing physical mounted checks and
a successful final build. This continuation adds the unlocked-device control:
physical UI automation is still unavailable before any product assertion runs.
The six-area goal is not marked complete. Native glass feel, actual rapid-scroll
frame pacing, separator shade comparison, and animation perceptibility remain
physical-acceptance gates, not inferred passes from the existing focused tests.
The user has been asked to check these in the installed build. No production
changes are justified solely by the runner failure.

## Focused Files Changed in This Goal

- `CubeFlow/Views/iPhone/CompetitionTabView.swift`: active glass surface/header
  routing, native interaction-state delivery, stable internal result transition.
- `CompetitionTopCubersLoader.swift`: gesture-aware publication, not delayed fetch.
- `CompetitionExpandableTopCubers.swift`: extracted existing disclosure action and
  DEBUG overlap registration; no wrapping/three-row geometry redesign.
- `CompetitionNativePresentation.swift`: modal-only native Back visual exposure and
  press forwarding, retaining exact-once navigation and the original no-card path.
- `CompetitionResultsStyle.swift`: opaque globally pixel-aligned round hairlines.
- `CompetitionFilterPresentation.swift`: bounded animation of the real native
  surface, retaining the original popover and lifecycle/generation guards.
- DEBUG evidence hooks in `CompetitionDisclosureAcceptanceSurface.swift` and
  `CompetitionLongListAcceptance.swift`; focused regression tests in
  `CompetitionNavigationLoadingTests.swift`, `CompetitionPresentationBoundaryTests.swift`,
  `CompetitionDisclosureGestureTests.swift`, `CompetitionPhysicalFinalBrowserTests.swift`,
  and `CompetitionLongScrollAcceptanceTests.swift`.

Unrelated project, advancement, transport, Timer, Smart Cube, and Explore changes
were preserved. Final `git diff --check` passed. No commit or push.

No commit/push. All unrelated dirty-worktree work is preserved.
