# Targeted Reliability and UI Corrections

Date: 2026-10-20. Continued from the current dirty CubeFlow worktree.

## Status

| Issue | Implementation | Verification boundary |
| --- | --- | --- |
| Published/historical Results PR hydration | Known hydration, ownership, and cancelled-publication defects corrected | Focused mounted/cached/cancellation tests passed; repeat physical acceptance |
| Published own PR in selectors | Implemented from the same explicit PB evidence as rows | FMC, identity, precedence, scope, refresh/retraction tests passed |
| Native Filter rapid reopening | **Unresolved**; production presentation unchanged | Both real ZIPs inspected; diagnostics enhanced, native lifecycle regressions passed |
| Smart Cube current-state guidance | 3x3 replanning gates removed; direct exact short-path search and verified best-known longer path | Deterministic state and in-flight response tests passed; physical BLE acceptance remains manual |
| Device-name spacing | First identity line anchored to cube bottom + 4 points, not an estimated row centre | Mounted normal/accessibility-size geometry tests passed |
| Smart Cube battery text | Compact cube row: subheadline regular -> body medium, monospaced percentage | Moderate-size and clamping tests passed |
| Explore WCA Region event overflow | Width-measured complete entries plus exact `+N`, one row | Packing, real-width/Dynamic Type height tests passed |

No physical Apple device was accessed. No signed device build, installation, launch, device logs, or physical UI automation was performed. No commit, push, revert, reset, cache cleanup, simulator deletion, or unrelated worktree cleanup was performed.

## 1. Published Results PR Hydration

### Evidence and Actual Defects

International WCA and CubingChina published/historical Results mount the same `PublishedCompetitionResultsContent` and the same official-person historical PB enrichment. There is no separate CubingChina PR decoder to patch. The previously accepted authoritative contract is preserved: explicit provider PB-cell emphasis joined to the canonical person, competition, event, round, and displayed result. No inference from first participation, times, rank, or the competitor's name was added.

Three concrete lifecycle problems were found:

1. The Results child owned its enrichment `StateObject`. Conditional navigation could remove it and recreate an empty presentation owner later, even though the public profile cache had useful evidence.
2. Automatic loading was driven by appeared rows or an opened competitor. The signed-in person's row could be outside the initial viewport or a different round, so it was not a reliable initial hydration trigger.
3. `install` recorded new flags before awaiting the asynchronous canonical merge. If navigation cancelled that merge, `flags` could contain the evidence while published `data` still lacked it. On return, loading the **same cached flags** hit the equality early return and never finished publication. Another person's later update could make the merged flags visible, explaining an interaction-dependent appearance.

The third condition is reproduced by a deterministic suspended merge test, not inferred from the user's gesture alone. The exact interruption on the physical iPhone is not retrospectively observable; these are demonstrated defects and a supported explanation, not a claim to have reconstructed an uncaptured device trace.

### Changes

- Competition Detail retains one `PublishedCompetitionRecordEnrichment` across conditional Results mounting, passing it through the existing initializer. Standalone callers retain their existing default owner.
- Mount/source/identity changes request evidence for the verified signed-in WCA ID when it occurs in the authoritative competition dataset, without waiting for the row to become visible.
- Existing visible-person loading remains bounded to four concurrent profiles. No bulk competitor/round scan is introduced.
- Collected-but-unpublished evidence is tracked explicitly. An identical cached response can finish an interrupted merge; successfully published identical evidence still skips redundant work.
- Explicit refresh includes the verified own person even if their row has never appeared, so a fresh authoritative negative response retracts a cached selector PR.
- Public evidence is not deleted on sign-out. Ownership and selector eligibility are recalculated from current canonical authentication identity; public PRs remain available for gray badges on other people.
- Existing update IDs refresh an open Result Card and expanded All Results without re-presenting or resetting expansion heights.

A genuinely cold public-person request can still take time, fail, or be blocked by the provider. Available cached evidence is reused; successful arrival updates the visible Results body automatically. Unknown evidence is not fabricated.

## 2. Published Own PR Selector Propagation

### Root Cause

The published selector used `eventRecordTags` and `roundRecordTags`. Those properties intentionally contain **regional records only**, because they are also used in regional/global discovery. PR enrichment updated row badges but could not enter those regional-only summaries. This is a missing presentation propagation path, not missing PB evidence or an FMC first-participation rule.

### Fix and Semantics

`PublishedCompetitionData.selectorRecordTags(ownWCAID:)` derives a separate user-scoped presentation summary:

- Start with existing regional summaries: `WR > CR > NR` from anybody.
- Fill a scope with PR only if no regional record exists and a row has explicit single or average/mean PR belonging to the canonically verified signed-in WCA ID.
- Event scope aggregates that event's rounds; a round scope includes only its own rows.
- Another person's PR, ordinary results, signed-out/missing/malformed identity do not produce a selector PR.
- Profile joins remain fail-closed for ambiguous result identity; existing ambiguous-join regression remains covered.
- Sign-out/account switch removes old personal selector eligibility immediately, without changing all-competitor public record data.

FMC single and mean evidence stay distinct in the canonical row and result components. Either explicit personal flag can justify the appropriate selector summary; first participation alone never does.

The existing `PublishedEventSelector`, `PublishedRoundSelector`, and `CompetitionWCARecordTagView` are reused. WR red, CR yellow, Results NR green, Top Cubers NR yellow, own PR blue/white, and other PR gray are unchanged. Global discovery remains regional-only. Modern Cubing Live and WCA Live implementation files were not changed in this pass; their regression suites passed.

## 3. Filter: Both Captures Actually Inspected

### Integrity

First ZIP: `/Users/paulsun/Downloads/7B6FE08E-9A52-4C55-B344-9EFF96E38231.zip`, previously analyzed in `competition-record-integrity-oct19.md`: 112 events, zero dropped, five measured dismissals, 1.243-2.091 seconds from native will-disappear to completion.

Second ZIP: `/Users/paulsun/Downloads/738DE9C9-7B4B-484F-8211-9558A0D6064E.zip`.

- SHA-256: `d0e9991421dfb27c797fd9f4f5ec3a89b17a7ae735b745841029be5320362461`.
- One entry: `738DE9C9-7B4B-484F-8211-9558A0D6064E/metadata.json`, 406,604 bytes.
- iOS 27.2, build 24B5084k; 256 events; zero dropped; six cycles; exactly 120 `dismissal-native-surface` samples.
- Extracted copy and timing TSV: `build/targeted-reliability-oct19/filter-second.json` and `filter-second-timing.tsv`.
- Two storage-order timestamp reversals are delivered `filter-touch-began` events carrying original touch times about 7.6-8.0 ms before a preceding display-link sample. They are not negative dismissal durations; comparisons use the actual timestamps and relevant lifecycle boundaries.

### Measured Second-Capture Timeline

All timestamps below are captured monotonic seconds, not wall-clock estimates.

| Cycle | Native will-disappear | Transition completion | Duration ms | Queued reopen wait ms | Samples | Last attached sample, elapsed s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 127472.845431 | 127474.364872 | 1519.441 | 1227.659 | 20 | 1.491045 |
| 2 | 127475.156255 | 127476.865157 | 1708.902 | 1485.916 | 23 | 1.680684 |
| 3 | 127477.456388 | 127479.065526 | 1609.138 | 1193.349 | 21 | 1.547583 |
| 4 | 127479.569849 | 127480.812554 | 1242.705 | No queued request in interval | 17 | 1.184494 |
| 5 | 127481.882935 | 127483.615779 | **1732.844** | 1192.928 | 23 | 1.705207 |
| 6 | 127484.277671 | 127485.533410 | 1255.739 | No queued request in interval | 16 | 1.227470 |

The actual maximum is 1.733 seconds, slightly larger than the preliminary 1.71-second description.

### What the Surface Data Does and Does Not Establish

Across all 120 samples:

- Local bounds remain `[0,0,290,348]`.
- Local position remains `[145,174]`.
- Local opacity remains 1; the local transform is the identity matrix.
- Projected window origin makes a small initial movement, generally settling near `[102,62]` in about 0.2-0.3 seconds, rather than tracing a full fade/shrink/disappearance.
- The native container/window relationship remains attached up to the last pre-completion display-link sample. The detached sample occurs with `didDisappear` just before transition completion.

The sampler selects `presentationController.presentedView` or the content controller's view. The trace shows a persistent non-fading content/container layer, **not proof that it sampled all visible animated glass/snapshot/mask layers**. Its projected origin includes ancestor geometry, but the previous capture did not enumerate ancestor opacity, transforms, animation keys, or the exact selected surface type.

Therefore, stability after 0.3 seconds is not evidence that a new popover can safely be presented then. The source still has a live UIKit presenting/dismissing relationship. Nominal coordinator duration 0.34 seconds cannot substitute for completion. The excess delay lies before UIKit's native completion acknowledgement, not in an additional application cooldown after it. The exact animated owner and why native coordination lasts that long remain unknown; UIKit/glass presentation coordination is an investigation boundary, not a proven OS defect.

### Decision

**No production Filter change.** No forced flag clearing, guessed delay, second presentation, custom animation, new popover, native animation suppression, Back change, or timer was introduced.

DEBUG observation now additionally records the chosen surface's type/identity and up to 16 ancestor views, including presentation-layer bounds/position/opacity/transform and active layer-animation keys. Existing 12 Hz/eight-second observation bounds, cancellation, recording-off handling, and the 512-event store limit remain unchanged. The capture store's 64 MiB budget remains unchanged. This fills an actual measurement gap without affecting production dismissal or touches.

## 4. Smart Cube Current-State Guidance

### Root Cause

The existing 3x3 pipeline maintained a verified inverse deviation trail to a historical checkpoint. However:

- Timer scheduled replacement only when the correction cost reached three moves (or no trail existed), ignoring the remaining original workload.
- The replacement planner repeated that correction-count gate.
- An additional short search was aimed at **any old recovery checkpoint**, not necessarily the target scramble state.
- An inverse-move hysteresis could reject a genuinely shorter valid candidate if its first move undid the user's last deviation.

Thus a short reverse trail could remain primary even when the full route to target was unnecessarily long. This is a demonstrated scheduling/cost-policy defect; the inspected code does not require blaming stale BLE state. Existing source/version/target/trust checks were already valuable and are preserved.

### New Lifecycle

1. Every verified deviated current state can schedule target replanning immediately, with no correction-count threshold.
2. Search directly from current facelets to the preserved target using a bounded exact short-path mechanism.
3. If a route of at most three HTM moves exists, use the shortest such route without waiting for the general solver actor.
4. For a longer 3x3 route, reuse the existing isolated Min2Phase source-to-target solver. Also simplify and replay any known executable correction + remaining original path; select the shorter valid available candidate.
5. Replay every candidate from its exact source to its exact target. Adopt only if valid and shorter than the existing full route when a comparable known route exists. An immediate inverse is not penalized merely for being an inverse.
6. If the current valid fallback is already equally short, keep it. Following a valid/rebased route uses normal progress tracking, not repeated expensive solving.
7. Reached target uses the existing completion/readiness path. Unknown/untrusted state cannot adopt a candidate.

The display may keep a compact valid recovery fallback visible while searching. Its small-display policy is **not** a scheduling or optimality gate. Historical inverse trails remain useful verified fallbacks, not the sole answer or a proof of optimality.

### Metric and Guarantees

`SmartCubeTargetPath` uses **HTM / face-turn metric**: `U`, `U'`, and `U2` each cost one, with the corresponding 18 face-turn moves. It is not quarter-turn metric.

A one-forward/two-backward meet-in-the-middle search exhausts all paths through length three. Distance zero/one/two is checked before length three, so a returned short path is mathematically shortest in that metric. This does not claim that every state is within three moves. Tests independently rule out shallower routes for a three-move scrambled-target example.

For longer 3x3 paths, the unchanged native bridge uses depth bound 21, phase-two probe budget 1,000,000, and `INVERSE_SOLUTION`, **not** `OPTIMAL_SOLUTION`. The returned route is verified and compared with the known valid route, but is **not guaranteed globally optimal**. No UI was added that falsely labels it optimal. The existing native solve is synchronous inside its background actor and cannot be pre-empted halfway through a native call; cancellation/currentness checks prevent its stale result from publishing. The independent short search can satisfy a new near-target state without joining that long-solver queue.

### 2x2 Boundary

The mathematical short-path helper also supports 24-facelet states in a **known fixed canonical frame**, and those tests pass. This must not be conflated with physical WeiPo move-face identity.

The current WeiPo 2x2 production progress path deliberately verifies target state up to its existing state equivalence and does not claim fixed physical token order (`currentMoveTokenIndex` stays nil; it does not mark arbitrary native turns as a 3x3-style deviation). The bundled TNoodle bridge exposes scrambling, not a general current-2x2-to-target solving API. Min2Phase accepts 54-facelet 3x3 states only.

This pass preserves native 2x2 state-only guidance/completion and does not guess a six-face decoder or physical orientation mapping. It does not claim a new general optimal 2x2 physical guidance feature. Native 2x2 progress and target-reached behavior are tested. BLE tracking, active-device selection, gyro presentation, and generic move animation are untouched.

### Async Safety

- Previous guidance tasks are cancelled on new canonical state/epoch changes.
- State/version identity, exact source facelets, target facelets, replan generation, trust, deviation status, and solve/inspection eligibility are checked before publication.
- `SmartCubeReplacement.canAdopt` remains the final gate.
- Short search runs with `@concurrent`, with cancellation checks and an off-main assertion. The existing long solver stays in its actor. Ordinary Timer scramble generation and the native bridge were not modified.
- New deterministic tests suspend the actual candidate-solver await boundary, deliver a newer state's result first, then release the old response. Another test cancels during that await. Both verify rejection rather than relying on arbitrary sleep ordering.

## 5. Smart Cube Small UI Adjustments

The old identity position used `cube bottom + estimated identityHeight/2 + 4`, while the view had its natural intrinsic height. The estimated 44/88-point row centre was not necessarily the real content centre, leaving unnecessary top space.

`SmartCubeIdentityAnchor` attaches naturally sized identity content by its **top edge** at `cube bottom + 4`. There is no guessed negative offset or fixed-height clipping. It remains free to grow with text size. Width, left device name/right battery, multi-device selector, row spacing, virtual cube, side timer, and statistics are unchanged. With virtual cube disabled, the original centred identity placement is explicitly retained.

Only the compact Smart Cube row passes `isProminent: true` to the shared battery component. Typography changes from subheadline regular (normally 15 pt) to body medium (normally 17 pt), still dynamically scaled and monospaced digits. It remains percentage-only, clamped 0-100, with the existing low-battery color and accessibility value. Other battery contexts keep their default typography.

## 6. Explore WCA Region Overflow

The existing general event component is a wrapping adaptive grid. That is not a bounded single-line representation for a fixed-width horizontal region card. Region cards now use `ExploreCompetitionEventStrip`; **Coming Up and other existing wrapping callers remain unchanged**.

- A fixed one-row GeometryReader receives the actual card content width; it does not assume device width or store a late measured width in state.
- Registered Cubing Icons advance and ink-overhang metrics determine complete cell widths. Existing glyph-centering/grid code is not changed; no per-event offsets are added.
- The packing calculation tries the largest complete prefix and reserves both the gap and the measured actual `+N` text width. The reserve changes correctly when N changes digit count.
- The row keeps the existing six-point gap. Its height depends on text metrics, not event count, so thirteen events cannot add a second row or make the card grow taller.
- Scaled icon/text metrics handle Dynamic Type. An exceptionally narrow row can show only the counter with native text scaling, never half an icon.
- VoiceOver receives the complete localized event-name list, including visually hidden events. The competition button/navigation and underlying event data remain unchanged.

## 7. Tests and Outcomes

Artifacts are under `build/targeted-reliability-oct19/` (the pass crossed midnight).

| Run | Outcome |
| --- | --- |
| `published-v1` | 11 XCTest tests passed |
| `guidance-v1` | 7 XCTest + 27 Swift Testing tests passed |
| `layout-v1` | 9 XCTest tests; one packing-test assertion failed because it assumed the 25-point ideal width of `+13` must fit in a synthetic 24-point row without the existing native text scaling |
| `focused-final` | **91 XCTest + 36 Swift Testing tests passed**, zero failures |
| `async-guidance-final` | **8 XCTest + 27 Swift Testing tests passed**, zero failures; includes the added in-flight-cancellation test |

The packing assertion now tests unscaled packing from the **measured marker width** upward and separately verifies that a narrower-than-marker row omits all icons and uses only the text-scaled marker. Maximum-fitting-prefix, gap, hidden count, and feasible-width bounds remain asserted; no production geometry was changed to satisfy it.

Final combined coverage: **128 distinct tests**, not the sum of overlapping reruns.

| Suite | Count |
| --- | ---: |
| PublishedSelectorRegressionTests | 6 |
| PublishedCompetitionPRTests | 6 |
| CompetitionRecordIntegrityTests | 9 |
| CompetitionWCALiveIntegrityTests | 9 |
| CubingLiveRecordDiscoveryTests | 6 |
| CubingLiveSessionCacheTests | 9 |
| TargetedSmallUILayoutTests | 4 |
| ExploreRenderingTests | 3 |
| CompetitionFilterEvidenceTests | 2 |
| CompetitionPresentationBoundaryTests | 20 |
| CompetitionAllResultsTableTests | 7 |
| CompetitionSeparatorEvidenceTests | 3 |
| SmartCubeCurrentStateGuidanceTests | 8 |
| SmartCubeReplacementTests | 27 |
| SmartCubeHardeningTests | 9 |

New named regressions include:

- `testOwnFMCFlagsPropagateToScopedSelectorsWithoutChangingGlobalDiscovery`
- `testOtherPRMissingMalformedAndChangedIdentityFailClosed`
- `testRegionalPrecedenceAcrossRoundsAndOnlyOwnPRWithinRound`
- `testCancelledMergeCanPublishIdenticalCachedEvidenceOnReturn`
- `testMountedOwnEvidenceHydratesWithoutVisibleOwnRowOrNavigationAndSurvivesRecreation`
- `testExplicitRefreshRetractsCachedOwnEvidenceEvenWhenOwnRowWasNeverVisible`
- `testExactHTMShortPathsForBothCanonicalPuzzleSizes`
- `testShortPathComparesActualScrambledTargetNotHistoryCheckpoint`
- `testOneMoveDeviationDoesNotWaitForThreeMoveThresholdAndAdoptsShortenedFullRoute`
- `testArbitraryTurnsNearCompletionReplanFromEachLatestState`
- `testTargetReachedUnknownAndBeyondShortBoundAreNotInvented`
- `testDelayedOldResponseCannotAdoptAfterLatestStateOrTargetChanges`
- `testCancellingInFlightSolverRejectsItsLaterResponse`
- `testNativeTwoByTwoKeepsStateOnlyGuidanceWithoutGuessingPhysicalMoveFrame`
- `testPackingFitsCompleteIconsAndReservesExactDigitCountForOverflow`
- `testMountedRegionStripHasStableOneRowHeightAtRealCardWidthsAndTextSizes`
- `testIdentityTopIsAnchoredWithoutEstimatedRowHeightForDifferentTextSizes`
- `testCompactBatteryProminenceIsModerateAndClampingIsUnchanged`

Two old Smart Cube policy tests were updated because the requested behavior explicitly removes correction-count gating and inverse hysteresis. They still assert normal commuting progress, strict improvement, valid target reachability, bounds, and stale/trust rejection. Other meaningful assertions were not weakened. Existing Competition native transitions, Back, independent no-bounce solves, separators, live caches, and Explore Browse/Coming Up regressions passed.

These automated results do not declare physical acceptance passed or establish the exact physical Filter animated-layer owner.

## 8. Final Build and Diff

- `git diff --check`: **passed**, including the final check.
- Exactly one final unsigned generic iOS Debug build for this pass: **BUILD SUCCEEDED**, exit 0.
- Command: `xcodebuild -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/competition-navigation-loading/DerivedData -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build`.
- Log: `build/targeted-reliability-oct19/final-unsigned-debug.log`. Simulator test compilation/reruns are listed separately above, not represented as generic builds.
- Non-fatal existing diagnostics remain: the earlier `configureWCALiveSession` ViewBuilder annotation is disabled by its explicit early return; App Intents metadata extraction has no AppIntents dependency. No production source changed after this successful build.
- Final source hashes are in `build/targeted-reliability-oct19/final-verified-source-sha256.txt`: 12 existing files updated, five Swift files added, zero baseline files removed. No other source changed relative to the start-of-pass manifest.

## 9. Changed Files

Repository root: `/Users/paulsun/Desktop/Projects/CubeFlow`.

Updated source:

- `CubeFlow/Views/Shared/PublishedCompetition.swift`
- `CubeFlow/Views/Shared/PublishedCompetitionRecordEnrichment.swift`
- `CubeFlow/Views/iPhone/PublishedCompetitionView.swift`
- `CubeFlow/Views/iPhone/CompetitionTabView.swift`
- `CubeFlow/Views/Shared/SmartCubeReplacement.swift`
- `CubeFlow/Views/iPhone/TimerTabView.swift`
- `CubeFlow/Views/iPhone/ConnectedDevicesView.swift`
- `CubeFlow/Views/Shared/DeviceBatteryIndicator.swift`
- `CubeFlow/Views/iPhone/Explore/ExploreModuleView.swift`
- `CubeFlow/Views/iPhone/CompetitionFilterPresentation.swift` (DEBUG observation only)

New source:

- `CubeFlow/Views/Shared/SmartCubeTargetPath.swift`
- `CubeFlow/Views/iPhone/Explore/ExploreCompetitionEventStrip.swift`

Tests:

- `CubeFlowTests/PublishedSelectorRegressionTests.swift` (new)
- `CubeFlowTests/SmartCubeCurrentStateGuidanceTests.swift` (new)
- `CubeFlowTests/TargetedSmallUILayoutTests.swift` (new)
- `CubeFlowTests/SmartCubeReplacementTests.swift` (policy expectations)
- `CubeFlowTests/CompetitionFilterEvidenceTests.swift` (new DEBUG schema assertions)

This report and local evidence/test/build artifacts are also new. Initial status, tracked diff, and source hashes are retained in the artifact directory. Hash comparison found only the intended source/test edits, with no unrelated source removal. BLE managers/protocols, SmartCubeExperience/native 2x2 progress, Min2Phase/TNoodle bridges, ordinary scramble generation, modern Cubing Live/WCA Live implementations, Browser scroll/sizing owners, Top Cubers, native Result Card/Back, and separator rendering files were not edited.

## 10. Manual Acceptance Checklist

The user alone performs these physical checks:

1. Open CubingChina published/historical Results at the previously affected FMC competition. Do not scroll, change round, or open a profile to trigger evidence. Cached/arriving own PR should update the row and appropriate event/round selector automatically; allow a genuine cold request time to finish.
2. Leave Results for Info and return, including a quick navigation while evidence is loading. Known PR should remain/reappear without another interaction. Keep an already-open card visible during arrival and verify its summary/All Results update without reopening or losing expansion.
3. Check single-only FMC PR, mean-only PR, another person's PR, ordinary results, and rounds with NR/CR/WR. Own selector PR is blue only below regional precedence. Sign out/switch accounts: no stale own selector PR, while public gray PRs remain valid.
4. Explicitly refresh after a known provider correction/retraction, including when the user's row is below the viewport. Do not infer retraction from a network error.
5. On a trusted 3x3 Smart Cube, follow a scramble until one move remains. Make arbitrary turns, inverses, and repeated face turns; pause briefly. Guidance must solve from the **current** state to the same target, with no three-error threshold. A shortest route may legitimately undo a turn; an inverse is not inherently a bug.
6. Exercise a demonstrably one-, two-, or three-HTM move route to target (half turn counts one). Follow the hint; target verification must be correct. Make fast turns while a longer replan is in progress, then stop: no old source/target route should replace the latest one.
7. Keep ordinary Timer scrambling/timing, inspection, BLE reconnection/device switching, and existing 2x2 native target-state verification unchanged. No new fixed-face 2x2 turn hints are claimed.
8. At narrow and normal widths and larger text sizes, check the cube/name gap, left name/right percentage, readable percentage-only battery, active-device menu, and centred no-virtual-cube case. Confirm Classic/Cards layouts and cube rendering are otherwise unchanged.
9. In Explore > In Your WCA Region, inspect Hong Kong Championship 2026 or another many-event competition. Complete icons and exact `+N` must fit in one row, with stable card height and unchanged tap navigation. Check larger text and VoiceOver's complete event list. Coming Up/Browse must retain their existing presentation.
10. Filter rapid reopen remains an unresolved item. If collecting further evidence, use the existing short Filter capture (two or three cycles) and export it. New surface identity/ancestor animation fields help locate animated ownership, but are not a census of sibling/descendant snapshot or mask layers and may not establish the visible owner alone. No device collection was done by the agent, and no physical fix is claimed.
