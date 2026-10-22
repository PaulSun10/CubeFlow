# Scramble Ownership, Live Animation, and Physical Guidance Evidence

Date: 2026-10-21. Continuation of the existing dirty worktree; no physical-device access, signed build, archive, commit, push, cleanup, or historical-solve migration.

## Outcome and Limits

Three production/observation defects were reproduced before their respective corrections: scramble text/target ownership divergence, mutable solve metadata during timing, and stale SwiftUI snapshots destroying live SceneKit animation queues. A fourth defect was in DEBUG observation: the Guidance update callback logged the previous view's captured context instead of its new argument.

These are established software defects, not a claim that every physical manifestation has been reproduced. In particular, the physical 15-20-extra-turn Guidance symptom is **not declared resolved**. The current Xcode installation is accepted as current; no outdated-installation explanation is used.

## Confirmed P0: Two Scramble Owners Could Diverge

`activateGeneratedScramble` previously changed `currentScramble`, while original-target creation waited for SwiftUI's later `onChange(currentScramble)`. A synchronous canonical move in that interval could publish/cache old progress with the new text. `SmartCubeTimerPresentationStore.save` accepted this mixed pair, and text-only restoration legitimized it on the next view update.

This also explains how visible Smart Cube instructions could remain on A while persistence used B: the Guidance view renders `progress.tokens`, whereas persistence formerly read current scramble text. It does not require TNoodle to produce duplicates.

The negative control mounted the real `TimerTabView`, used its real active-session router and persistence, assigned A=`R U'`, prefetched B=`L D2`, then emitted `R U' U R' L` synchronously. Completing A adopted B; the immediate L still acted against A's target, which remained authoritative after the render turn. Both target assertions failed before correction.

Corrections:

- Assign text and construct its original Smart Cube target synchronously in the same Timer owner turn, including ready-prefetch adoption.
- Do not redundantly rehydrate an already-current, matching presentation from `onChange`.
- Reject text/target mismatches when saving a presentation. Validation uses a single bounded last-validated pair, not an accumulating cache.
- Keep the context-bound prefetch optimization. Extend ownership to active Smart Cube device and connection attempt; invalidate obsolete foreground/prefetch callbacks on owner changes.
- Regenerate an unfinished/loading assignment when Timer returns after cancellation; retain a fully assigned scramble.

## Confirmed P0: Solve Metadata Was Not Immutable

Manual Timer and Smart Cube completion formerly read mutable current scramble state at save time. Manual Next could run during timing. The mounted negative control started with A, requested Next during timing, and saved B instead of A. Later iterations could save the loading placeholder. This is independent of random generator quality.

`TimerSolveAssignment` now captures scramble, event, session, request identity, and input source at start. Ordinary Timer, Smart Cube, GAN Timer, and existing Combined persistence use the frozen assignment; duration, penalty, completeness, anchors, and readiness rules are not redesigned. Typed entry snapshots the current valid assignment at submission. Next/adoption is blocked while timing or a result is pending. Saving clears pending state before performing exactly one automatic Next. Historical solves are untouched.

End-to-end tests exercise the production Timer handlers and Core Data rather than a generator-only helper:

- Three ordinary Timer solves with deliberately distinct scrambles; OCR verifies actual mounted Timer pixels, Core Data is refreshed, and the actual production Solve Detail sheet is rendered/OCR-checked for each saved scramble.
- Three Smart Cube solves through actual routed canonical events, immediate following-scramble turns, target checks, reconstruction initial-state checks, and production Solve Detail pixels.
- Next/foreground races, session and puzzle changes, actual UIKit tab leave/return while loading, and saving a pending result after switching selected session. The original session/event receives the result; an existing historical scramble is unchanged.
- Actual active-device replacement and a new connection attempt while generation is pending. Old callbacks cannot activate either before or after the fresh callback; the next prefetch belongs to the new owner.

The tests seed canonical session events and deterministic generator completions; they do not emulate encrypted BLE or physically tap through Data navigation. They render Data's actual private sheet through a DEBUG-only factory, with no replacement presentation or production styling changes.

## Confirmed P1: Animation Snapshot Race

`SmartCube3DView.Coordinator.receive` consumes canonical moves synchronously. SwiftUI can subsequently call `updateUIView` with an older captured facelet snapshot. Previously, any facelet disagreement was treated as authoritative resync, clearing an active animation and queued turns. Two U events could consequently show one animated U followed by a snapped final U2.

The negative control used the actual coordinator/SCNView: send U, update S1, send U, then deliver stale S1. It reproduced canonical rewind, lost current animation, and an empty pending queue before correction.

Live Timer/Lab/Management snapshots now carry their canonical sequence. The coordinator ignores a snapshot older than its already-consumed sequence. Equal/new authoritative corrections, boundaries, owner rebinding, trust loss, and lifecycle teardown still resync normally. Legacy snapshot-only callers retain their existing behavior. SceneKit rendering, BLE delivery, gyro, materials, and catch-up/backlog policy are unchanged.

Tests advance the actual renderer clock and inspect actual pivot rotation, both U/U animations, native U2, five rapid mixed turns, every target in order, queue drain, final canonical state, authoritative boundaries, and attempt rebinding. This does not promise rendering an unlimited severe backlog; the preexisting bounded catch-up policy remains.

## Git Attribution

| Change | What history establishes |
| --- | --- |
| `1844425d` (2026-09-05) | Introduced the presentation store and text-based matching without canonical text/target validation. |
| `8eb5369a` (2026-09-09) | Added context-bound single-slot prefetch and synchronous ready-payload adoption, exposing the deferred target-assignment window. Prefetch is retained, not blamed alone. |
| `d58f509c` (2026-10-08) | Extended Smart Cube session/persistence ownership around the existing store contract. |
| Current uncommitted Timer facelets fallback | Adds another legitimate current-state publication opportunity during this window. Its exact introduction cannot be attributed to a committed Git diff. |
| `4d83d3ed` (2026-09-15) | Already contains the dual animation authorities: synchronous event consumption and unconditional snapshot-disagreement resync. The latent race predates the latest dirty changes; the exact physical onset is unproven. |
| Older Timer start/save path | No immutable per-solve scramble assignment. This is a longstanding correctness gap, not evidence that TNoodle recently began repeating scrambles. |

No entire historical file was restored. Ordinary consecutive manual solves without Next passed even before correction; that control is retained and is not represented as a baseline failure.

## Complete Physical Guidance Export

Analyzed accessible user file `/Users/paulsun/Downloads/Untitled.txt`, preserved as `build/scramble-animation-regressions-oct21/physical-guidance.tsv`. SHA-256: `2aea3af5e841da18b063b6ea8b3c10b2076b1afe3ce3ea0fd5929b0f90726169`. All 2,014 retained entries were parsed, not only the last candidate. Derived summaries are `physical-summary.json` and `physical-correlations.txt` in that artifact directory.

- Span: 39.165433 seconds through Stop. Header counts: 920 RX/parser/main applications; 97 decoded moves, 97 canonical publications, and 97 Timer consumptions. Canonical sequences 109-205 are contiguous; baseline render is sequence 108.
- One target digest throughout: `9b0367c685d33648`. The trace lacks the visible original scramble digest, so this does **not** establish affinity to the user's intended displayed scramble.
- 97 schedules, 57 native starts, 58 candidate arrivals, 56 equal-cost valid continuation reuses, 11 obsolete/cancelled worker discards, and two checked/accepted adoptions. Reusing a replay-valid equal candidate is not itself a missed input or stale route.
- All 152 model `display-path` entries report exact-target replay validity. The 177 SwiftUI diagnostic entries include 76 intermediate false values. Last-per-sequence entries include 96 true and two false; each false precedes the next move by approximately 0.5 ms, not a stationary stall.
- Adoption at `269092.571370`: sequence 158, source `c667131ca5785db0`, generation 5, 20 moves; all identity/trust/eligibility guards passed. Model route digest became `6127c784a059cb72`.
- Final adoption at `269111.197502`: sequence 205, source `704fdd80ed97eb2c`, generation 6, 19 moves; all guards passed. Model route digest became `c9feddd73d7e3bcd`. Candidate receipt was 191.087 ms after receipt; primary native search 5.962 ms, improvement 22.933 ms. No further turn was required before this adoption or Stop at `269113.105128`.

Crucially, the old SwiftUI callback still logged generation 5/count 20 after the final generation 6/count 19 model adoption. A mounted production-view regression reproduced exactly this observation defect: `.onChange(of: diagnosticContext)` ignored its new value and logged the previous closure's context. It now records the actual callback argument. This corrects DEBUG evidence; it is not proof that physical pixels previously matched either the old or new logged row.

New bounded DEBUG evidence records `target-assigned`, original scramble digest, shortened generation-request token, and active/fallback recovery presence alongside model/view source/target/path digests. No raw scramble, facelets, full UUID, new poller, timer, or unbounded storage is introduced. The request token identifies generation/cancellation ownership, not a permanent device identity or persistent solve ID.

Unproven: whether the captured target was the intended visible original scramble; whether a stationary physical view failed to adopt a valid model; the exact contribution of the proven P0 race to that physical recording. No solver budget/settle change, relaxed replay validation, speculative protocol change, or global-optimality claim is made.

## Management, Diagnostics Navigation, and Filter

Reset retains the accepted UIKit native prominent Glass configuration and system-blue tint, now using native `.large` sizing and the existing full-width proposal. Focused mounted tests verify at least a 44 pt touch height. Neutral Disconnect, red Forget, equal lower widths, and confirmation are unchanged.

Battery is 22 pt regular monospaced digits, compared with the unchanged 24 pt bold Results-derived device-name style. An actual two-connected-device Menu card is rendered, not merely a modifier fixture. Measured dark glyph ink is 16.0 pt for battery versus 17.67 pt for name, vertically centered. OCR's raw typographic bounding boxes overstated the percent-sign box; the regression compares actual pixel ink instead. No Menu font replacement bug was established or "fixed". Light/dark screenshots and native configuration/geometry checks are retained.

Current capture path remains **Settings > Development > Guidance Capture** in DEBUG, independent of Protocol Debug, master Debug Mode, puzzle, and connection status. The real Settings-to-Timer navigation case passed in the previous integration pass (`docs/guidance-integration-diagnostics-oct21.md`); that hierarchy/store was preserved unchanged here, not claimed as a newly repeated UI test. Recording is process-owned, survives tab navigation, and retains evidence after Stop; force-quit discards it.

Filter is unchanged. The preceding measured simulator long interval was native will-disappear to completion (794.92-925.34 ms), not an application delay after acknowledgement (0.019-0.269 ms). This is historical measured evidence, not a fresh iOS 27.2 physical result or an OS-only attribution. No bypass of the crash-safe presentation owner was attempted.

## Changed Files in This Pass

Production ownership/presentation:

- `CubeFlow/Views/iPhone/TimerTabView.swift`
- `CubeFlow/Views/iPhone/TimerScramblePipeline.swift`
- `CubeFlow/Views/Shared/SmartCubeExperience.swift`
- `CubeFlow/Views/iPhone/SmartCube3DView.swift`
- `CubeFlow/Views/iPhone/SmartCubeLabView.swift` (sequence input only)
- `CubeFlow/Views/iPhone/SmartCubeManagementCard.swift`
- `CubeFlow/Views/iPhone/SessionNativeActionStyle.swift`
- `CubeFlow/Views/iPhone/SmartCubeScrambleProgressView.swift` (DEBUG callback only)

DEBUG evidence/test seams:

- `CubeFlow/Views/Shared/SmartCubeGuidanceTrace.swift`
- `CubeFlow/Views/Shared/SmartCubePeripheralSession.swift` (seed battery only)
- `CubeFlow/Views/iPhone/SmartCubeTimerGuidanceProbe.swift`
- `CubeFlow/Views/iPhone/DataTabView.swift` (actual Solve Detail factory only)

Tests:

- `CubeFlowTests/TimerScrambleLifecycleRegressionTests.swift` (new)
- `CubeFlowTests/SmartCubeAnimationRegressionTests.swift` (new)
- `CubeFlowTests/TimerScramblePrefetchTests.swift`
- `CubeFlowTests/SmartCubeGuidanceTraceTests.swift`
- `CubeFlowTests/SmartCubeManagementTests.swift`
- `CubeFlowTests/SmartCubeTimerIntegrationTests.swift` (probe cleanup only)

## Verification

Final focused run: **62 XCTest + 46 Swift Testing = 108 passing tests**, zero failures, in `focused-final-v2.xcresult`. Includes production lifecycle, actual animation, current/latest Guidance, controller lifecycle/ownership, management rendering, device integration, Combined readiness/lifecycle, reconstruction, and prefetch. Two specifically selected existing presentation-store Swift tests additionally executed and passed in `presentation-store-final.xcresult`: **110 distinct final passing tests**. Tests were not counted by summing reruns.

Negative-control artifacts are retained. Earlier failures include the established defects, an empty in-process accessibility observation replaced by real pixel OCR, a simulated appearance toggle that did not actually remove the host (replaced by actual tab switching), OCR typographic-box mismatch (replaced by pixel ink), and Swift Testing macro compilation for mutating calls (evaluate before assertions). These are not counted as passing runs. The first two individually selected Swift tests without `()` selected no cases; the final run with parentheses confirms both actually executed.

The **one actual unsigned generic iOS Debug build passed**, exit 0, in `build/scramble-animation-regressions-oct21/final-generic-debug.log` (`CODE_SIGNING_ALLOWED=NO`, destination `generic/platform=iOS`). The only reported build warning is skipped AppIntents metadata extraction without an AppIntents.framework dependency. A preceding shell wrapper used zsh's reserved `path` variable during hashing, exited 127, and never launched Xcode; its failure is separately retained in `build-wrapper-not-started.log`, not counted as a build or hidden as a passing attempt.

All 7,328 source/configuration hashes match before versus after the final build. Against this pass's starting dirty tree, 7,559 baseline files are unchanged, 16 scoped existing files changed (listed above), and none are missing. Additions are the two regression files and this report. `project.pbxproj`, Explore glyph alignment, Browser/Filter production code, WCA Results styling, protocol decoding, solver scheduling/budgets, and unrelated changes are preserved.

Final `git diff --check` passes. Additional no-index whitespace checks of both new tests and this report produce no diagnostics. No task-owned Xcode/test process remains active. No broad unrelated test suite or physical UI automation was used.

## Manual Physical Acceptance

1. Install this source manually through Xcode. Connect the same Smart Cube normally; do not redefine its state with Mark Solved just to make a test pass. Use the existing correct connection-state policy.
2. In ordinary Timer, record the visible original scramble, start/stop/save three consecutive solves, and compare each Data > Solve Detail scramble to the one assigned before start. Verify one Next per save and no mid-solve Next activation.
3. In Smart Cube mode, complete three scrambles/solves. Compare saved originals, next visible instructions, and reconstruction initial state. In one iteration make the first next-scramble turn immediately after the previous solve ends. The new target must already own it.
4. On the live virtual cube perform slow U/U, moderately fast U/U, one U2, and `R U F' L2 D`. Check both same-face turns and mixed turns animate, with the exact final state. Also leave/return once and reconnect normally; a genuine resync remains a snap.
5. For Guidance evidence, open **Settings > Development > Guidance Capture**, Clear, enable Record Guidance, then return to Timer. Capture the current visible scramble/instructions in a screenshot or screen recording. Make one deviation and pause about one second; no further 15-20 turns are required. If the instructions look stuck, leave the cube stationary and record the screen, then return to the capture page, Stop, and Copy. Retain the screenshot/video together with the text export. New scramble/request/target digests distinguish wrong-target ownership; model and corrected view records distinguish adoption from view-update observation, while video establishes actual pixels.
6. Verify Reset height/full width and title/battery balance in the actual multi-device management card in both appearances. Check existing neutral Disconnect, red Forget confirmation, and that browsing another device does not change Timer selection.

These checks remain manual. Passing simulator tests does not establish physical BLE, compositor, or iOS 27.2 acceptance.
