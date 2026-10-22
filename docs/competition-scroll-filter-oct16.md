# Competition Scroll and Filter Follow-up

October 16, 2026. Existing dirty worktree preserved. No commit or push.

**Subsequent physical acceptance FAILED in both List and Glass on iOS 27.2 beta.**
The simulator spacing correction below did not resolve the reported physical
pullback. It must not be treated as its established root cause. Follow-up owner
instrumentation and the unresolved physical gate are documented in
`competition-physical-scroll-owner-oct16.md`.

## Scope and Acceptance Boundary

The new physical-acceptance brief supersedes the earlier report's open status
for original interactive glass, Makati's fixedSize-based sizing, and native Filter
animation. Those implementations are accepted and retained. Separators are deferred.
No Detail Back, results-card, advancement, transport, Timer/BLE, Explore, signing,
deployment-target, or project-configuration correction belongs to this pass.

Evidence directory: `build/competition-scroll-filter-oct16/`.
Simulator: iPhone 17 Pro, iOS 26.5. This is NOT physical iOS 27.2 beta acceptance.

## 1. Ordinary Scrolling

### Reproduced Owner

The real active Browser, UICollectionView, self-sizing hosting cells, original
native Buttons and interactive glass were exercised with actual swipe gestures.
DEBUG observations independently record scroll offset, content size, cell and host
model/presentation rectangles, visible title/venue/cuber probes, glass ancestors,
loader publication, and dragging/decelerating/idle state. Idle coverage continues
for at least 0.65 seconds after native deceleration completion.

The initial captured summaries were unsuitable for the Past filter: only Beijing
was past. Those short-content bounce traces are not regression evidence. An early
runner also reported passes inconsistent with the newly added coverage assertions;
its artifacts were rejected. Explicitly refreshing the simulator test runner made
the current fixture setup/coverage prints observable. No app data or simulator was
erased. `fresh-runner-coverage.log` and `valid-baseline-remaining.log` provide the
accepted baseline, not the earlier reported green run.

The corrected test uses 41 captured summaries with explicitly synthetic past dates
and Beijing first. Both production date-filter stages remain enabled. Names,
venues and other wrapping inputs retain their captured values. Each of four
warm/cold List/Glass cases performs three upward swipes and a downward swipe,
without a disclosure interaction. Coverage requires genuinely long content,
multiple virtualized identities, real hosted-element probes, and idle frames.
This fixture is not evidence about date/filter correctness or every cold network
outcome: the known Beijing data arrives cold; other fixtures have cached empties.

The cause reproduced in BOTH appearances and BOTH cache modes:

1. An idle Top Cubers loader has a mounted but visually empty VStack.
2. The containing card VStack adds an 8-point gap before that zero-height child.
3. A cached empty answer arriving during scrolling is held by the existing gate.
4. At idle the loader publishes `.empty` and removes its child, including that gap.
5. Following visible cells move upward by 8 points per preceding empty section,
   although scroll offset does not move and the host remains fixed inside its cell.

Thus the gate postponed this layout change; it did not eliminate it. This is a
cell/self-sizing layout change, not an offset reversal or a disclosure-only bug.

### Targeted Correction

In `CompetitionTabView.swift`, the List and Glass card content stacks now have
zero automatic inter-child spacing. The venue owns its existing 8-point separation.
`CompetitionLoadedTopCubers` accepts `topSpacing`, set to 8 by the production card,
and applies that separation only to actual loaded/loading content. Idle/empty
observers have no transient section gap. Existing loaded and empty card geometry
is retained; no extra permanent blank space is reserved.

Original fixedSize modifiers, text widths/wrapping, disclosure identity, native
Button ownership, glass placement/effect, data fetching and the publication gate
are unchanged. No scroll resets, compensation, reload workaround, arbitrary delay,
or animation suppression was introduced.

### Measurements

Maximum same-cell upward MODEL step at unchanged offset, inside native bounds,
after drag/deceleration ends:

| Appearance/cache | Before | After |
| --- | ---: | ---: |
| Cold Glass | 24 pt | 0 pt |
| Cold List | 32 pt | 0 pt |
| Warm Glass | 32 pt | 0 pt |
| Warm List | 32 pt | 0 pt |

All 16 after-gestures have zero measured idle pullback. Each gesture has 190-280
qualifying same-cell idle comparisons. Raw snapshots and independent scripts are
retained in `before/`, `after/`, `idle-before-after.txt`, `analyze-owners.rb`, and
`check-idle-pullback.rb`. The independent checker verifies the new assertion's
invariant directly against exported data; runner output must not be substituted
for actual artifact inspection.

Content-size changes from virtualization/estimated sizes are recorded separately;
they are not automatically called visible jumps. During native Glass drag/press,
title-in-cell observations still vary by roughly 1-4 points, with much smaller
venue movement. They do not establish a new SwiftUI layout fault or prove physical
compositing stability. The accepted native interaction is not modified to remove
that separate observation. The reproduced idle cell jump is fixed in simulator;
the entire physical scrolling complaint is not declared resolved.

## 2. Filter Response Versus Native Transition

No production Filter timing, state-machine, generation guard, binding semantics,
attachment, adaptation, capsule, or animation changed.

DEBUG-only instrumentation adds a passive window touch observer for the Filter
hit region (never recognizes, prevents, cancels, or delays touches), intent and
local native-binding timestamps, and a bounded display-link observer of the first
nonhidden, nonzero-opacity native popover surface intersecting the window. The
latter is an observable surface proxy, not a photometric measurement of the first
readable text pixel. It stops on detection/disappearance/timeout.

`filter-lifecycle.json` and `filter-analysis.txt` separate these stages:

| Stage | Observed simulator time |
| --- | ---: |
| Touch timestamp to passive delivery | 1.3-7.5 ms |
| Touch-up to Button/open action | 5.0-20.1 ms |
| Open action to intent publication | 0.4-1.1 ms |
| Open action to native binding request | 2.6-5.1 ms |
| Open action to warm native will-appear | 24-30 ms |
| Open action to warm first observable native surface | 80.8-81.8 ms |
| Cold first observable surface | 248.7 ms |
| Warm native did-appear | 875-880 ms |
| Cold native did-appear | 1029 ms |
| Close action to native dismissal finished | 852-856 ms |

The measured approximately one-second lifecycle is not approximately one-second
Button input latency. No comparable avoidable model delay was reproduced here.
The observed UIKit/SwiftUI presentation owns that lifecycle; this does NOT prove
the user's beta-specific responsiveness complaint is entirely a platform limit.

Mounted tests verify queued reopening during native dismissal, a parent rebuild
while queued, native dismissal before binding acknowledgement, and retained native
animated transitions without a custom surface. The model reopens synchronously
from actual dismissal completion when intent is queued; no extra timer exists.
Those tests exercise early queued intent, unlike the UI route's normal XCTest
idle waits. The UI route verifies Region return, outside dismissal, repeated opens;
a separate test verifies background/foreground recovery without relaunch.

Native Filter screenshots from the route were inspected. Existing native popover
controls and presentation remain. Physical iOS 27.2 input/reopening remains open.

## 3. Optional Disclosure Polish

Source inspection confirms one stable disclosure Button. Its containing condition
depends on whether more rows exist, NOT expanded/collapsed state. There are not
separate Show More and Show Less Buttons, nor an expanded-state identity reset.
Inserted cuber entries explicitly use `.transition(.identity)`, which provides no
entry fade. This pass does not claim that view identity alone explains the user's
perceived disappearing control.

No speculative animation change was retained. The fresh Glass geometry test still
fails its unchanged one-point title limit at 1.52565 points (the prior native
baseline also failed around 1.24-1.52 points). Venue, heading and existing cubers
remain below 0.8 points; List reports zero through all four toggles. Rather than
weaken that assertion or add optional polish against an already-failing strict
baseline, the accepted 0.32-second disclosure behavior is preserved. No geometry
assertion was relaxed. Smooth inserted-row/control presentation remains deferred.

## Focused Verification

- Accepted baseline: four ordinary-scroll cases, with valid long-list data.
- Four mounted Filter lifecycle/reopen checks passed.
- Native Filter controls/Region/outside/repeated-open UI check passed.
- After correction: four ordinary-scroll cases passed; all 16 raw gesture traces
  independently satisfy zero measured idle same-cell pullback.
- Makati List venue/existing-row disclosure check passed.
- Makati Glass check FAILED its original title assertion at 1.52565 pt. Measured
  venue 0.44146, heading 0.16504, existing cubers 0.03623/0.41462/0.79302 pt. This
  mixed run is NOT reported as an all-green suite.
- Filter background/foreground recovery UI check passed.
- Three cache/fetch/gesture-publication model tests passed.
- `git diff --check` passed.
- The ONE final unsigned generic iOS Debug build PASSED, using Xcode 27.2 beta,
  `generic/platform=iOS`, Debug, and `CODE_SIGNING_ALLOWED=NO`. Evidence:
  `final-generic-debug.log`. No additional generic build was run.

Files changed for this goal: production section-spacing in `CompetitionTabView.swift`
and `CompetitionTopCubersLoader.swift`; DEBUG observations in those loader paths,
`CompetitionFilterPresentation.swift`, `CompetitionDisclosureAcceptanceSurface.swift`,
`CompetitionLongListAcceptance.swift`, and new `CompetitionScrollOwnerDiagnostics.swift`;
new `CompetitionOrdinaryScrollTests.swift`; this report. The unsuccessful temporary
unfiltered fixture switch was removed from `CompetitionPhysicalBrowserAcceptance.swift`.

Frozen `project.pbxproj`, `CompetitionResultsStyle.swift` and
`CompetitionNativePresentation.swift` hashes match this goal's before snapshot.
No separator or native Detail Back changes. No physical-device handshake retry,
installation or device interaction was made in this goal.

## Remaining Physical Acceptance

1. On iOS 27.2 beta, scroll a long mixed-height list in List and Glass, with Top
   Cubers enabled, both cached and newly arriving. Do not touch disclosure. Observe
   the end of deceleration and first idle frames separately from native press feel.
2. Repeat Makati Show More/Less; verify venue/heading/three existing cubers stay put
   and authentic glass feedback remains. Optional animation appearance is unchanged.
3. Open Filter, close and immediately request it again; repeat outside dismissal,
   Region return and background/foreground. Distinguish immediate touch/action
   acknowledgement from the accepted native animation and dismissal duration.

The reproduced idle-spacing fix is simulator-verified. Remaining beta-specific
visual/input behavior is explicitly unproven, not hidden by a native substitute.
