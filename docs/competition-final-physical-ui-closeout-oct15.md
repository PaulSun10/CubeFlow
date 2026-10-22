# Competition UI Closeout

October 15, 2026. Implementation and focused simulator verification; physical acceptance is not claimed. Current dirty worktree preserved. No commit/push. One final unsigned generic iOS Debug build passed.

## Corrections and Evidence

### Narrow Interactive Glass / Back Follow-up

The noninteractive glass workaround below is superseded. Competition cards again
use the existing `.regular.interactive()` compatibility helper, now on a separate
background surface rather than wrapping the resizing foreground. Card shape,
material, navigation, disclosure animation and measured three-row behavior are
unchanged. No scroll-offset compensation was added. Four alternating Makati
disclosures in each appearance passed; Glass viewport, title-origin, relative-title
and presentation drift were all zero in the recorded traces.

The production Back implementation required no further change: its interception
control exists only in the presented result navigation controller. A new mounted
regression confirms no interception control without a card and exercises the
original native Back. Existing exact-once, toolbar-rebuild, background-blocking,
real Detail Back, Profile-return and internal Back checks passed.

Follow-up evidence: `build/competition-interactive-followup/disclosure.log` (two
tests) and `navigation.log` (seven tests), all passed on iOS 26.5. No generic build
was run for this follow-up. Native interaction feel and physical iOS 27.2 beta
(24B5084k) still require device acceptance; simulator checks do not establish that.

| Area | Diagnosis and correction | Verification |
| --- | --- | --- |
| Filter | Reopening constructed content in about 20ms but native appearance completed about 1s later. Filter-only presentation transactions now disable that native transition. A local SwiftUI binding acknowledges framework changes outside the synchronous model-publishing setter, retaining generation/lifecycle guards and avoiding redundant false publication. Original custom popover and shared Map/Filter capsule remain. | Reopens reached native didAppear in 48-92ms, rather than about 1.01s. Twenty-cycle queued/external dismissal stress, parent reconstruction, Region return, actual toolbar reopen, and background/foreground recovery passed. No publication warning appeared in the latest focused logs. |
| Top Cubers disclosure | Whole-card `.regular.interactive()` glass stretched title/content when a disclosure button was pressed, even with a stationary cell and viewport. Competition cards now use noninteractive regular glass; material, shape, navigation and container resize animation remain. Removed the separate entry opacity/4pt slide transition. | Four Makati toggles in both actual Browser appearances passed. iOS 26.5 Glass title origin/relative/presentation drift became effectively zero, versus about 1.49pt before. Three actual wrapping rows, ordering, counts and retained disclosure model are unchanged. |
| Cold Top Cubers loading | Raw model-offset changes initially suggested snapback. A warm no-publication control reproduced the same coordinate rebase while the presentation-layer cell position remained constant. Thus response overlap alone was an invalid causal attribution. No speculative loading gate, artificial delay, offset compensation or invalidation-mode change is retained. | First-gesture and interior cold arrivals, plus warm no-publication controls, passed the same one-point visible-motion tolerance in List/Glass. Interior captures release data during the second drag after title collapse; DEBUG-only trailing footer space isolates loading from bottom clamping. Raw offset and visible geometry remain recorded. Physical recheck is still important. |
| Original Detail Back | UIKit can replace the native Back control while retaining the source controller. With the card open, the previously captured weak control disappeared: its frame became zero while the visible Back remained 44x44pt. | Before/after mounted rebuild test reproduced and corrected the failure. Frame and activation now resolve the current native control against the retained source/navigation context. Native event forwarding, actual measured hit region, blocked Refresh and exact-once dismissal/exit passed. Real published Detail UI test passed on iOS 26.5. No unconditional pop or background touch-through. |
| Champions | Lazy table container extended 0.666667pt below its 34pt row/Button: a real two-pixel unfilled strip at 3x, missed by the original row-only check. Champions/Podiums small final tables now use eager sizing with the same shared header/row builder; ordinary Results stay lazy. | Marietta, Minnesota and Beijing passed enclosing-boundary and final-green-pixel checks in light/dark. Row height, text, green RGB, masks and shadows are unchanged. No cosmetic line was added. |
| Round boundaries | Native header Divider and Canvas round strokes had different contrast. Header and round boundaries now use the same adaptive full-row Canvas stroke with a one-pixel-sized gap. | Short/multi-round, light/dark and rightmost horizontal-scroll pixel comparisons passed. Wang OH and verified Tymon 3x3 use the same renderer. Current official data has no Tymon OH entries; none were fabricated. On-screen native compositor check also passed. |
| Round / All Results | Existing loading already retained the round summary. Added only a 0.16s internal opacity transition. All Results is measured invisibly before replacing an already-rendered round, and measurements are keyed by content/width/language to reject stale exiting content. | Retained loading-summary geometry, direct Sum/All Results semantics and round-origin Back passed. Native continuity test retains the same modal, selection, outer alpha and transform through forward/back navigation; no card re-presentation. Reduce Motion branches use the existing system environment; actual setting-on validation remains in the hardware checklist. |

## Focused Results

Evidence: `build/competition-final-ui-oct14/`.

- `ios26-visible-motion-matrix.log`: eight cases passed, covering both appearances, Makati disclosure, initial/interior cold publication and warm controls. Checks actual cell presentation at one-point tolerance, not only model offsets or response overlap.
- `ios26-neutral-glass-disclosure.log`: both four-toggle Makati checks passed.
- `ios26-current-back-and-loading-transaction.log`: both native Back cases passed; the unrelated loading-animation experiment failed and was reverted. Do not count this entire run as passed.
- `ios26-interior-cold-and-current-detail-back-corrected.log`: both interior cold checks and real published Detail Back passed.
- `ios26-rules-transition-scene-regressions.log`: five cases passed: separator equality, horizontal-scroll equality, retained loading geometry, direct/round-origin navigation, and Filter scene recovery.
- `ios26-internal-native-continuity-corrected.log`: passed. The earlier fixture attempted a read-only environment injection and nonexistent selection ID; corrected to use the production presentation modifier and result ID. No production test hooks were added.
- `champion-beijing-filter-stress-native-rules-corrected.log`: six light/dark Champions renders, twenty-cycle Filter stress and native compositor boundaries passed.
- `final-unsigned-generic-debug.log`: **BUILD SUCCEEDED**, Debug, generic iOS, signing disabled. This is the one generic build for this goal. AppIntents metadata extraction warning reports no AppIntents dependency; no UI compile errors.
- `ios26-existing-long-scroll-smoke.log`: both existing long-list checks passed (Glass warm 104.483s, List cold 92.414s), using `test-without-building` after the generic build. No source changes or additional build were performed.
- Final `git diff --check` passed. Frozen project, advancement and Live transport hashes match the saved baseline.

The isolated iOS 26.5 simulator supplements the existing iOS 27 evidence. Existing simulator data was not erased. Diagnostic fixtures/journals remain DEBUG-only. Failed animation experiments were removed. No production transport/cache/advancement, Timer/BLE/Gyro, Explore, signing or deployment-target changes were made.

## Physical Checklist

1. Reopen Filter rapidly; dismiss outside, visit Region and return, then background/foreground. Confirm immediate appearance, no jump/lockout and no publication warning when attached to Xcode.
2. Test cold Top Cubers while scrolling in List and Glass. Expand/collapse Makati, Tokai and Beijing, including collapse after scrolling through expanded entries. Titles/existing rows should stay fixed; new rows should uncover without a separate slide/fade. Native bottom-boundary clamping is not an app scroll compensation.
3. Open a result card from competition Detail, including the Settings -> My Competitions route. Tap the original dimmed toolbar Back: dismiss and leave exactly once. Refresh, tabs and other background controls must remain blocked. Recheck card Back/Profile independently.
4. Check Champions in Minnesota, Marietta and Beijing, both appearances. Green must reach the table bottom without the old strip.
5. Check short/multi-round tables, including OH where available, in light/dark and after horizontal scrolling. Boundaries must have consistent appearance and remain visible.
6. Switch Round -> All Results -> Round; repeat with Reduce Motion enabled. Confirm restrained internal transition, no empty/loading flash or re-presentation, and unchanged accepted card opening/closing/dimmer.

Detailed chronological investigation and failed experiments remain in `docs/competition-final-physical-ui-oct14.md`. Simulator checks do not establish physical-device acceptance.
