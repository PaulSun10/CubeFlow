# Timer and Smart Cube Four-Issue Review

Date: 2026-10-30, Asia/Shanghai. Baseline: current local `main`, preserving the existing dirty worktree. No physical device was accessed. No commit, push, release, upload, or deployment occurred.

## Findings and Changes

### 1. Default scramble position: corrected

Both `SettingsTabView` and `TimerTabView` declared an independent `@AppStorage("timerScrambleVerticalPosition")` default of zero. No other registration, migration, initializer, reset, or writer for this key was found. Their normalization writes only when the normalized value differs from the current value.

The stored value is normalized to 0...1. Settings multiplies it by 100 for the percentage. `TimerArrangementLayout.scrambleTop` multiplies it by available vertical travel (available height minus content height). Therefore 25% means `0.25`, not `25` or a fixed point offset.

Both declarations now reference `TimerCustomizationDefaults.scrambleVerticalPosition = 0.25`. There is no migration or default registration. Explicit saved values, including zero, are preserved. There is no dedicated position-reset action to change; removing the preference restores the new default. Invalid-value clamping and all other customization behavior are unchanged.

### 2. Repeated scramble and Solve Detail ownership: one repeat defect confirmed and corrected

Traced generation/prefetch through `TimerScramblePipeline` and `TimerTabView`, target preparation/readiness, inspection/start, immutable `TimerSolveAssignment`, Smart Cube completion, Core Data persistence, `DataTabView`'s `solve.scramble` display, next advancement, navigation, and device/attempt changes.

Existing protections remain: foreground request-token/context validation, one-consumer prefetch slots, atomic text/diagram/target activation, immutable solve-start assignment, and refusal to activate new content during timing or while a result is pending. Guidance may display a different route to the same original target; this does not change the original scramble saved with the solve.

**Newly demonstrated defect:** complete a Smart Cube solve while its next prefetch is still pending, then switch away from Timer and back. Loading in Classic replaces text with the ellipsis. The in-memory snapshot may be cleared, but the persistent `smartCubeTimerScramble.<session>.<size>` value still contains the completed target. Returning runs `restoreStoredSmartCubePresentation`, which accepts that old target and suppresses fresh foreground generation. Cards retains the old presentation during loading and can also abandon the pending replacement after navigation.

The pre-fix mounted production-Timer test failed because `R U'` was restored after it had already been saved as a completed solve, with no new foreground generation. This establishes a repeat mechanism, not the cause of every historical physical report.

**Correction:**

- `scrambleNeedsReplacement` records an outstanding replacement independently of whether previous Cards content remains visible.
- On explicit/automatic Next, invalidate only the current session/puzzle's restoration cache through `SmartCubeTimerPresentationStore.discardScramble`.
- Do not recache the prior presentation while a replacement is outstanding.
- Returning to Timer or changing the device owner resumes generation for an outstanding replacement rather than treating retained text as completed work.
- Clear the flag only when the accepted payload commits. The DEBUG direct-assignment fixture clears it when explicitly supplying a target.
- Keep previous Cards text/diagram visible until replacement readiness. Do not change their animation or native refresh-button behavior.

No solve history is edited or deleted. Other sessions and puzzle-size caches remain separate. No new delay, broad synchronization, or generation queue was introduced.

The current tests do **not** reproduce a solve being persisted with a later scramble. Actual mounted Timer tests verify original text/target ownership, Core Data reload, and rendered Solve Detail across successive solves. Physical historical mismatch reports remain unconfirmed beyond the repeat defect above.

### 3. Guidance delay: physical cause still unconfirmed; scheduler unchanged

Read the previous October 20-22 guidance investigations and current `SmartCubeExperience`, canonical receipt/consumption, `TimerTabView.handleSmartCubeFacelets`, `beginSmartCubeGuidanceSearch`, `applySmartCubeGuidance`, `SmartCubeGuidanceController`, `SmartCubeReplacement`, and `SmartCubeTargetPath`.

The current implementation schedules latest-state work without a deviation-count threshold. Its exact <=3 HTM lane does not wait for native work. Longer native search follows an existing 120 ms trailing settle, cooperative cancellation, and the existing 350/100 ms primary/improvement budgets. An obsolete worker drains the newest settled request without another BLE move. Publication/adoption checks include request ticket, device, epoch/revision, source, target, trust, and generation.

The exact short lane proves shortest paths only within its supported depth. Longer native results are replay-validated upper bounds, not globally shortest-path proofs. Earlier controlled fixtures reproduced long fallback accumulation even though stationary search/publication worked. No new evidence establishes a lost shorter route, a physical BLE/state delay, or a new scheduling regression. Do not interpret passing tests as resolution of the physical 7-19-extra-moves report.

Added DEBUG trace stages for settling completion (`nativeBusy`, `exactBusy`), exact-lane start/miss, and cancellation. These complement existing native timing, request/source/target/version, candidate, adoption, and rendered-path evidence. No scheduling, solver, budget, or adoption behavior changed.

### 4. Virtual cube stutter/snap: no new execution defect established

Read the historical snapshot-before-event fix and traced ordered canonical delivery, `CubeTurnPresentation`, `SmartCube3DView.Coordinator` binding, snapshot staging/reconciliation, render ticks, visibility suspension, and SceneKit layer updates.

The historical ordering correction is present. Live snapshots cannot preempt their synchronous executable event; older snapshots cannot overwrite a newer sequence. Ordinary rapid bursts preserve every turn. Existing catch-up compresses remaining duration without changing progress. Exceptional floods remain bounded at 128 pending turns. Trust gaps, eventless authority, TPS zero, rebinding, and invisible-view resume intentionally resynchronize rather than inventing animation continuity.

No new evidence identifies which mechanism explains the user's intermittent physical stutter. Do not remove safety resynchronization or rewrite animation to fit an uncaptured observation.

Added opt-in DEBUG `animation.*` evidence: binding, queued move and receipt age, sequence/trust/window/TPS, pending/active counts, render transitions, hidden/untrusted/gapped move resyncs, eventless snapshot resyncs, suspension, and resume. State values are digests; identifiers are shortened by the existing exporter. No raw packets, original scramble text, device names, or tokens are added.

These events now survive raw-packet flooding in the existing bounded 2,048-entry capture ring alongside guidance. No new capture UI, timer, task, animation policy, geometry, or production logging was added. The ring is still finite and intentionally not persisted across force quit. Tick events are application SceneKit update evidence, not proof of GPU-presented frames.

## Focused Validation

Existing Xcode 27.2, SDK 27.2, iOS 15 deployment target. Mounted runtime checks use the existing iOS 26.5 simulator, not physical BLE or iOS 27.2 hardware. Generated payloads and radio input in lifecycle fixtures are injected; Core Data storage, Timer logic, Solve Detail rendering, scheduler/solver, and SceneKit presentation are production implementations.

- `negative.xcresult`: expected pre-fix failure, 1 test / 2 assertions, demonstrating restoration of the consumed target and absence of fresh generation.
- `focused.xcresult`: **65 XCTest + 17 Swift Testing passed**, no failures. Covers preference defaults/preservation, Timer lifecycle, prefetch ownership, native Cards refresh interaction, guidance current/latest/late/lifecycle/trace, canonical animation, and actual Timer integration.
- `lifecycle-final.xcresult`: an added mode-switch test initially expected fresh foreground generation. Source and runtime showed legitimate reuse of an identical in-flight context instead; one test failed. Production behavior was not changed to satisfy that assumption.
- `lifecycle-verified.xcresult`: **8/8 lifecycle XCTest passed** after correcting that expectation and retaining target/duplicate-completion assertions. Includes prefetch completion during active Smart Cube timing, ignored Next during timing, mode switching, device/reconnect ownership, remount, and rendered persisted Solve Detail.
- Distinct passing test count is **82**, not the sum of repeated runs.
- The one final unsigned generic iOS Debug build **passed**, exit 0, including the final production source. Command: `DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer xcodebuild -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/competition-navigation-loading/DerivedData -skipPackageUpdates CODE_SIGNING_ALLOWED=NO -jobs 4 build`. Log: `final-unsigned-debug.log`. No signed build, archive, or distribution was performed.
- `git diff --check`: passed before and after the final build.

Evidence directory: `build/smart-cube-four-issue-oct30/`. Each build/test log records its actual command. Tests use `-only-testing` selections and no broad UI suite. No new software/dependency was installed or downloaded. Existing simulator CoreBluetooth, WebKit process/QoS, and deprecated-API diagnostics are not treated as physical evidence or silently fixed.

## Physical Acceptance Still Required

1. In a test profile without the position preference, verify Settings shows 25% and Timer uses it. Verify existing saved 0% and custom values remain unchanged. No user-data reset is needed or authorized by this report.
2. In Classic and Cards Smart Cube mode, complete successive solves; check their original scrambles and reconstruction initial states in Solve Detail. Immediately leave/return around completion or rapid Next while generation is pending. Confirm the completed target is not restored as Next. In Cards, the prior text/diagram must remain paired until replacement.
3. Repeat with reconnect, session/puzzle/input-mode changes, and a rapid first turn after the next target appears. No old completion may replace the active assignment or new target.
4. Use the existing Development guidance capture. Clear, start, follow an original scramble until one turn remains, deviate, then stop moving. Let the current-state work settle without extra turns. Stop/copy promptly. Capture the original-target identity, final move, search decision, and visible route; long valid fallback alone is not proof of missed scheduling.
5. In the same short capture, perform an ordinary rapid turn burst, then stop. Compare physical and virtual final state; note visible snap/stutter times. Repeat leaving/returning to Timer and opening/closing management. New animation events distinguish queued turns from lifecycle/canonical resync; physical/GPU continuity still needs observation.

## Task-Delta Files and Preservation

Production files changed:

- `CubeFlow/Views/iPhone/TimerCustomization.swift`: shared 25% default.
- `CubeFlow/Views/iPhone/SettingsTabView.swift`: use that default only.
- `CubeFlow/Views/iPhone/TimerTabView.swift`: same default and outstanding replacement/cache lifecycle.
- `CubeFlow/Views/Shared/SmartCubeExperience.swift`: scoped recovery-cache invalidation.
- `CubeFlow/Views/Shared/SmartCubeGuidanceController.swift`: DEBUG trace stages only.
- `CubeFlow/Views/iPhone/SmartCube3DView.swift`: DEBUG trace stages only.
- `CubeFlow/Views/Shared/SmartCubeDiagnostics.swift`: bounded retention of animation evidence.

Tests changed/added:

- `CubeFlowTests/TimerScramblePositionTests.swift` (new).
- `CubeFlowTests/TimerScrambleLifecycleRegressionTests.swift`.
- `CubeFlowTests/SmartCubeGuidanceTraceTests.swift`.
- `CubeFlowTests/SmartCubeAnimationRegressionTests.swift`.
- This report (new).

Unrelated pre-existing changes remain: `Config/Info.plist` key reordering; local `xcschememanagement.plist` buildable-autocreation entries; eleven untracked screenshots under `docs/assets`. No staging or source-control history mutation occurred. No changes to Inspection, Combined readiness/timing, BLE/protocol mapping, generic turn presentation, WCA authentication, backend, website, TNoodle, or privacy declarations.

The complete pre-existing untracked screenshot list is unchanged:

```text
docs/assets/competition-focused-polish-oct12/heading-aligned-333.png
docs/assets/competition-focused-polish-oct12/heading-aligned-smart.png
docs/assets/competition-focused-polish-oct12/selector-list-shadow-equal-false.png
docs/assets/competition-focused-polish-oct12/selector-list-shadow-equal-true.png
docs/assets/competition-results-refinement-oct12/me-320-zh-Hans.png
docs/assets/competition-results-refinement-oct12/selectors-actions-false.png
docs/assets/explore-restoration-oct11/fixture-peru-dark.png
docs/assets/explore-restoration-oct11/fixture-peru-light.png
docs/assets/unified-results-oct12/header-complete-false.png
docs/assets/unified-results-oct12/shadow-off-false.png
docs/assets/unified-results-oct12/shadow-on-false.png
```

## Final Verification

All requested local investigation/implementation/verification is complete. The source change is intentionally narrower than a claim that all historical physical symptoms are fixed. Final working tree: 12 tracked modified paths (two pre-existing plus ten task changes), 13 untracked paths (eleven pre-existing screenshots plus the new test and this report), no staged changes or deletions. No implementation/build/test process from this pass remains active at closeout. The simulator booted for this pass is shut down without erasing its data.

Confirmed corrected: missing-preference default and consumed-target restoration during pending Next. Code-level validated but awaiting hardware acceptance: that navigation/cache correction. Unconfirmed physical causes: historical saved/displayed mismatch beyond that repeat mechanism, Guidance's extra-turn report, and intermittent animation stutter/snap. Intentionally unchanged: solver guarantees/budgets, animation policy, authoritative synchronization, native refresh interaction, and all excluded functionality.
