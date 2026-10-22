# Explore Regional Events, Filter Isolation, and Smart Cube Lifecycle Audit

Date: 2026-10-20. Repository: `/Users/paulsun/Desktop/Projects/CubeFlow`.

This is a continuation of the existing dirty worktree. Development verification is not physical-device acceptance. No physical Apple device, signed build, devicectl, installation, device logs, commit, push, reset, revert, simulator deletion, or cache cleanup was used.

## A. Baseline and Task Delta

Task-specific evidence is under `build/explore-filter-lifecycle-oct20/`:

- `initial-status.txt`, `initial-tracked.diff`, `initial-sha256.txt`, and `baseline/` preserve the starting state, including previously untracked production files.
- `final-source-sha256.txt` records the source/test/project inputs frozen before final verification.
- The preceding pass's 141 distinct tests and successful build remain prior development results, not new results of this pass or physical acceptance.

Production source changes:

| File | This pass only |
| --- | --- |
| `CubeFlow/Views/iPhone/Explore/ExploreCompetitionEventStrip.swift` | Complete balanced rows, uniform family event reservation, DEBUG mounted-frame observation |
| `CubeFlow/Views/iPhone/Explore/ExploreModuleView.swift` | Regional-only equal-height horizontal family and bottom-aligned event areas |
| `CubeFlow/Views/iPhone/CompetitionFiltersView.swift` | DEBUG-only isolation controls; default/release colors, controls, selected-status animation and native presentation behavior preserved |
| `CubeFlow/Views/iPhone/SmartCubeManagementCard.swift` | Reuse the existing single-content overflow fitter instead of retaining two live ViewThatFits candidates |

Updated tests: `ExploreRegionPackingTests.swift`, `TargetedSmallUILayoutTests.swift`.
New tests: `CompetitionFilterIsolationTests.swift`, `SmartCubeOwnershipAuditTests.swift`.
This report and local test/measurement artifacts are also new.

Excluded and preserved: Published PR hydration/own selectors, official Results, Cubing Live/WCA Live transport and results, Results navigation/native Back, Browser List/Glass/Top Cubers/Filter selection, Timer Next/prewarming/inspection/Combined/persistence, BLE protocol mappings, canonical feeds, guidance target/settle/solver strategy, saved-device operations, glyph metrics, and nonregional Explore composition. The existing external project.pbxproj state is preserved.

## B. Explore Implementation

### Layout and Sizing

Only `module.titleKey == "explore.in_region"` changes. Normal card width remains 280 pt, accessibility width 310 pt, with the existing 16 pt surface inset: actual icon widths are **248 / 278 pt**, independent of phone width.

The existing registered Cubing Icons font, measured advance/ink-overhang cell convention, per-glyph centering, and normal **18 pt** icon size are unchanged. `@ScaledMetric(relativeTo: .footnote)` still handles text-size scaling. The glyph subtree retains the original `.large` environment to avoid double scaling.

`ExploreEventPacking.rows` uses measured widths and contiguous partitions:

1. Keep the entire list on one row if it fits with the existing 6 pt gap.
2. Otherwise find the minimum feasible number of rows with at least 1 pt between complete cells.
3. Minimize the sum of squared differences from the rows' balanced ideal occupied widths, preserving event order. Equal-cost partitions prefer the longer first segment.
4. Keep the 6 pt gap in each row whenever it fits; tighten only the row that requires it.

This is not a count-to-layout lookup. The unequal-width regression deliberately chooses a different split from a count-only balancer. All official events are rendered; the old prefix/overflow-marker APIs and `+N` presentation are removed. No clipping, icon scaling, fading, negative spacing, or nested icon scrolling is introduced.

The event area reserves at least two rows, using the complete official family at the current width/text size. At larger accessible sizes it reserves the additional rows needed by the family, even on a card with fewer events. Height is `reservedRows * max(iconSize + 6, labelFont.lineHeight) + (reservedRows - 1) * 6`. Standard height is 54 pt; XXXL is 66 pt. One-row entries occupy the first row, not a vertically centered row.

The regional carousel uses a real HStack rather than LazyHStack to negotiate the **same actual height** for its bounded family (composition already limits this family to eight cards). Card titles, dates and locations remain real SwiftUI text, without guessed line counts, text shrinking or fixed card heights. The subtitle region can absorb remaining vertical space while keeping its text at the top; event areas align across the family. Other carousel families retain their LazyHStack and previous layout.

An initial implementation used an explicit zero-minimum Spacer, which introduced an unnecessary extra 8 pt VStack gap. The final implementation avoids that extra gap. Mounted mixed-name/mixed-date/mixed-location fixture heights are:

| Phone viewport | Standard | XXXL | Accessibility 3 |
| --- | ---: | ---: | ---: |
| 320 pt | 210.33 | 258.33 | 532.00 |
| 393 pt | 210.33 | 258.33 | 532.00 |
| 440 pt | 210.33 | 258.33 | 532.00 |

These are measured heights for the deliberately long-name fixture family, **not fixed production constants**. Every one of its eight cards has the same height; every event area's top and height are also asserted equal. Families with shorter text naturally require less height.

### Measured Event Packing

| Events | Standard, 18 pt / 248 pt | XXXL, 24 pt / 248 pt | Accessibility 3, 40 pt / 278 pt |
| --- | --- | --- | --- |
| 1 | 1 | 1 | 1 |
| 5 | 5 | 5 | 5 |
| 8 | 8 | 8 | 4 + 4 |
| 13 | 7 + 6 | 7 + 6 | 5 + 4 + 4 |
| 14 | 7 + 7 | 7 + 7 | 5 + 4 + 5 |
| 15 | 8 + 7 | 8 + 7 | 5 + 5 + 5 |
| 16 | 8 + 8 | 8 + 8 | 6 + 5 + 5 |
| 17 | 9 + 8 | 9 + 8 | 6 + 5 + 6 |

Standard gaps are 6 pt throughout. At XXXL, the first row of 17 uses 4 pt and its second uses 6 pt. At Accessibility 3 the listed rows retain 6 pt gaps. At Accessibility 5 the measured icon cell is 52 pt: nine cells alone require 468 pt, so two rows are mathematically impossible at 278 pt. All 17 use four balanced rows, with 4.5 pt gaps where a five-icon row requires them. Accessible fallback adds rows rather than hiding events or reducing readability; it is not universal two-row support.

The final metric matrix covers all seven nonaccessibility sizes and all five accessibility categories. Mounted glyph/frame tests cover standard, XXXL and Accessibility 3 using actual card content widths; family tests cover 320/393/440 pt screens, both semantic color schemes, wrapped titles/locations and one-/two-day dates. Additional production sizing checks reuse the same hosting controller across content/width updates and compare it with a recreated host.

The exact 17-event accessibility boundary is also measured: Accessibility 1 has 29 pt cells and still fits 9+8 (2.125 / 6 pt gaps). Accessibility 2 has 33 pt cells; nine cells alone require 297 pt, exceeding 278 pt, and it uses three rows. Accessibility 3 also uses three; Accessibility 4/5 use four. At Accessibility 4, six 46 pt cells plus even five 1 pt gaps require 281 pt, so a three-row 17-event partition is impossible.

The existing competition Button, route, destination, event ordering and full localized event-name accessibility label are unchanged. Composition/destination round-trip and existing Coming Up/Browse/records rendering regressions are included. Actual glyph frames are checked for complete bounds and nonoverlap, not just arithmetic packing.

`preservation-audit.txt` independently verifies that the item Button helper, route destination and competition destination view are byte-identical to the baseline. This and the production composition round-trip cover the unchanged navigation path; this pass does not claim a new network-backed end-to-end UI tap test.

Screenshots are retained as XCTest attachments and exported under `verified-images/` in the artifact directory, with `manifest.json` mapping names to PNGs. Inspect `region-events-17-*`, `region-family-*-light`, and `region-family-large-dark`. No new Filter or Smart Cube visual design is proposed.

The standard full 17-event layout, normal/dark card surfaces and accessibility family were visually inspected. The isolated dark fixture applies dark mode to the module but resolves its outer page canvas in the hosting environment; its light surrounding canvas is a fixture limitation, not evidence about full-page dark Home appearance. Existing whole-Explore light/dark regressions also pass. Card/icon bounds and uniform-height assertions do not depend on that canvas.

## C. Filter Investigation

### Physical Evidence Revalidated

Both original archives are present and were read again, not assumed from an old report:

- `7B6FE08E-9A52-4C55-B344-9EFF96E38231.zip`: SHA-256 `c49fc15a3da0a699ac3baf9afffd6cce205f49a1048d8986aaa6596aba16f999`; 112 events, zero dropped, five dismissals: 1496.533, 2091.316, 1256.827, 1876.739, 1243.029 ms.
- `738DE9C9-7B4B-484F-8211-9558A0D6064E.zip`: SHA-256 `d0e9991421dfb27c797fd9f4f5ec3a89b17a7ae735b745841029be5320362461`; 256 events, zero dropped, six dismissals: 1519.441, 1708.902, 1609.138, 1242.705, 1732.844, 1255.739 ms.

These measure native will-disappear to transition-coordinator completion. In both, application completion follows in approximately 0.026-0.041 ms; queued reopen publishes immediately afterward. They do not reveal a second application cooldown. The second archive's four queued requests wait 1192.928-1485.916 ms.

Extracted copies are `physical-filter-first.json` and `physical-filter-second.json` in this pass's artifacts. The previous `competition-record-integrity-oct19.md`, `targeted-reliability-oct20.md`, and existing diagnostic reports/artifacts were reviewed.

### Actual Lifecycle Owners

- Filter Button calls `CompetitionFilterPresentation.open`; Close synchronously sets its requested/presented state through `close`.
- `CompetitionFilterPopoverModifier.synchronizeIntent`, observed through `native-binding-request`, passes the epoch-captured native Boolean to SwiftUI's original `.popover`.
- `CompetitionPopoverCompletion.Controller` is a child of the actual native presentation. It finds the native container; `viewWillDisappear` supplies transition start and registers on its real transition coordinator.
- `native-did-disappear`, `transition-completion`, and `completion-accepted` are separate observations. Completion validates that dismissal/detachment really occurred before releasing the state-machine gate.
- `dismissalFinished` can service one queued request and advances generation; stale binding/completion epochs cannot close that new surface.
- Region-sheet coverage is not treated as Filter dismissal. Cancelled transitions restore a new epoch. No second popover is presented while the first dismisses.

A separate presentation-controller delegate completion timestamp is not available in this instrumented SwiftUI-owned path without replacing/interposing its delegate. This pass does not mislabel coordinator completion as an independently observed presentation-controller callback. Native disappearance/window detachment are additional observable boundaries.

### Controlled Simulator Experiments

`CompetitionFilterIsolationTests` mounts the production `.competitionFilterPopover`, same toolbar anchor/native ownership and real completion observer in all four variants. Each variant performs three queued close/reopen cycles plus final close. Experiments were repeated during staged and final verification; per-run raw JSON attachments preserve each sample.

A: complete existing Filter, controls/tasks and semantic decorations.
B: minimal 290 x 348 placeholder, same native popover.
C: same Filter with nonessential control fills/strokes omitted through a DEBUG environment. The native popover/glass remains.
D: same Filter/native transition with supplementary content transaction/selected-status animation isolated in DEBUG. Native dismissal animation is not disabled. Source review also shows the selected-status 0.22 s animation is not a dismissal cooldown.

Final four-sample results from `verified-final` (zero dropped events in every variant):

| Variant | Native start -> coordinator ms, min-max | Mean ms |
| --- | ---: | ---: |
| A full | 776.39-795.94 | 789.72 |
| B minimal | 789.19-793.56 | 791.52 |
| C no control decoration | 791.21-794.25 | 792.90 |
| D no supplementary content animation | 789.22-795.13 | 792.28 |

Earlier complete experiments also yielded overlapping ranges of approximately 779-800 ms. The earlier `focused-final` per-cycle boundary timing is in `filter-controlled-timing.tsv`; final raw JSON attachments and `filter-verified-summary.txt` retain the later measurements above.

In the earlier TSV run, intent -> native start is 2.37-14.58 ms; coordinator -> application completion is 0.019-0.049 ms; application completion -> queued intent publication is 0.026-0.079 ms. Those exact events, not the coarser test poll, establish the earliest valid reopening. Reopen publication is not a claim that its presentation animation has already finished.

A 10 ms MainActor observation loop saw maximum gaps of roughly 19-70 ms, including layout/render/scheduling overhead; even minimal content can show a gap. This is not a sampled stack profile and cannot assign the physical >1 s delay to a main-thread function. It does not demonstrate a continuous stall across the native waiting interval.

Native surface bounds remain 290 x 348 in the compared default Filter cases; ancestor samples identify `_UIPopoverView`, `UITransitionView` and the window. Stable origin/opacity and empty ancestor animation keys are **not proof of visual completion**: internal descendants, sibling snapshots and masks are not exhaustively sampled. No exact disappearance timestamp is invented from a stable frame. Ordinary polling/surface sampling is not a layout invalidation or an application geometry change.

### Conclusion

**Filter latency remains unresolved. No production dismissal fix was applied.** Minimal content has essentially the same delay in this simulator, so the full Filter content and its decorative layers are not necessary to reproduce that simulator interval. This does not prove an OS bug, nor explain the additional physical-device delay.

The test destination is the existing `24E6D520-DF19-4F61-89DB-55F2F418484E`, running **iOS 26.5 (23F77)** with the iOS 27.2 SDK. No iOS 27.2 simulator runtime is installed. The user's physical failure is iOS 27.2 beta (24B5084k); this platform difference limits attribution. The harness also isolates the Filter host, not all concurrent traffic in the full application.

Production presentation/state-machine code, native glass, safeguards and appearance are unchanged. The only Filter source additions are reversible DEBUG environment isolation options; their default is empty and there is no user-facing switch. Release/default control colors, border, geometry and animation values stay the same. No arbitrary delay, forced flag, parallel surface or native-animation suppression is introduced. No repeated identical physical capture is requested.

## D. Smart Cube Lifecycle Audit

### Guidance and Canonical Ownership

Actual `SmartCubeGuidanceController`, Timer adoption, manager/feed, session and saved-store source were inspected.

- One retained Timer StateObject, one in-flight worker and one replaceable latest request; no move-count threshold or growing per-input solver queue.
- New state immediately invalidates the publication ticket, replaces latest and cancels the previous settle/worker task. The 120 ms trailing settle is unchanged.
- A synchronous native solver already running cannot be preempted. Its handle remains owned until return; stale output is rejected and completion drains the settled latest request without another physical move.
- Weak captures span awaits. New tests release the owner while settle or search is suspended: it deallocates, and releasing the old worker cannot publish into a new controller.
- Timer drains pending canonical history before checking epoch, actual source facelets, exact original target, generation, trust and eligible timing state. Rebase preserves the original target's establishment time. New target/continuity boundary/navigation cancellation remains authoritative.
- The canonical feed keeps sequence monotonic across clear/reset and bounds event history to 120. Parser callbacks retain generation/attempt checks. No feed, protocol, solver strategy, 2x2 mapping or 120 ms policy was changed here.

### Device Operations

Reset resolves the explicit selected device and attempt; a stale/mismatched attempt returns instead of falling back to Active. Session Reset uses existing canonical continuity/read-back/local-reference handling, invalidating pre-reset guidance. It is state recalibration, not pairing/factory reset; no saved solve/history store is invoked. Existing firmware acknowledgement/read-back remains a physical validation boundary.

Disconnect targets one session, cancels its retry/reconnect intent and retains its saved association. Other connected sessions remain independent; existing compatible-device Active reconciliation is retained.

Forget uses the existing destructive confirmation and selected ID, disconnects that session, removes its subscriptions/gyro observer/peripheral delegate/session/transport metadata, clears only its saved association/preferences, and reconciles Active. A retiring/manual-disconnect gate blocks late connection callbacks; terminal callback retires the old connection. Discovery transport metadata cannot create a missing saved record. Explicit fresh discovery/connect can establish a new association. This is not iOS system Bluetooth unpairing.

The management card selection changes only its selected ID, never Active. Selected device content has stable per-device identity and directly observes that session, including inactive devices. Canonical 2x2 visual state and 3x3 state/revision remain separate. Historical solve data is not deleted by these operations. Existing management, stale-attempt, multi-device, inactive 2x2 rendering and guidance lifecycle regressions are included.

### Concrete Defect Found and Fixed

The actual mounted oversized management-card test failed **before** correction: its Combine subscription counter remained **2**, and native lifecycle logs showed two live coordinators/renderers. `ViewThatFits` retained both its rejected natural-height candidate and the selected ScrollView candidate, each built from `content()` containing the real SmartCube3DView.

`SmartCubeManagementFittedContent` now reuses the already-existing single-content measured-overflow fitter on every supported iOS version, keeping the existing maximum-height and natural-height convention. The alternative branches mount one content tree at a time. Normal content wraps; actual overflow scrolls. No parallel hidden live renderer is kept for measurement. A branch switch can recreate its one renderer during initial overflow negotiation; it is not claimed to preserve that renderer's identity across the fit change. It does not change device selection, card appearance, native modal ownership or cube animation.

The same mounted regression passes afterward: normal 2x2 -> oversized 3x3 -> normal 2x2 maintains exactly **one** live subscription after layout; removing the content reaches **zero** each time. Existing natural-size and oversized-scroll geometry tests pass. No SmartCube3DView, BLE manager/session, saved-store or guidance production source change was needed.

### Renderer Lifetime Boundary

Coordinator teardown clears its tap closure, subscription and tick timer; device/attempt/size rebinding replaces—not accumulates—subscriptions. The new repeated creation/update/dismantle test verifies one subscription after repeat redraws, zero after dismantle, and released application coordinators.

An initial test also required SCNView itself to deallocate within approximately one second. That failed even after explicit autorelease-pool drainage. Controlled tests found the same short-lived retention for a **plain native SCNView**, including with no scene, while plain UIView releases; pausing or clearing scene did not distinguish the application case. Therefore this is not evidence of a CubeFlow retain cycle or measured background GPU leak. The unsupported deadline assertion was replaced by the actual application ownership invariant, and the controls remain documented/tested. SceneKit internal caching/release timing and physical GPU/RSS were not established; no speculative renderer teardown change was made.

## E. UI Performance and Resource Findings

Explore uses deterministic, synchronous width/partition math and normal SwiftUI layout. There is no GeometryReader -> State -> relayout sizing loop. DEBUG frame probes are inert without an observer and absent from Release measurement behavior. The DP operates on at most 17 official entries; the eager family is bounded to eight cards, not the full Competition Browser. There is no new persistent cache, task, subscription or external dependency. Existing stable competition IDs/order/routes survive refresh. Current width, type and content are inputs, so there is no stale measurement cache.

Smart Cube's proven ongoing duplicate renderer/subscription on overflow is removed by reusing its existing one-content architecture. Application tasks/coordinators/subscriptions clean up in focused lifecycle tests. Firmware transport, physical Metal/GPU performance and framework-internal SCNView retention are not equated with those tests.

Filter constructs one native surface per acknowledged generation. Dismissed representables dismantle after native completion; the transition observer is intentionally retained until its registered completion, then releases its callback. DEBUG records scalar/bounded evidence and uses existing bounded observation windows. Source/timing review did not identify synchronous content work responsible for the physical delay. No speculative caching, debouncing, dispatch, scroll manipulation or presentation replacement was added.

## F. Verification

Final verification on the frozen source: **115 distinct focused tests passed**, comprising 96 XCTest and 19 Swift Testing composition tests, zero failures. Reruns and experiment samples are not added to that distinct count. Log/result: `verified-final.log` and `verified-final.xcresult`.

| Suite | Distinct tests |
| --- | ---: |
| ExploreRegionPackingTests | 4 |
| TargetedSmallUILayoutTests | 4 |
| ExploreRenderingTests | 3 |
| ExploreCompositionTests (Swift Testing) | 19 |
| CompetitionFilterIsolationTests | 1 |
| CompetitionFilterEvidenceTests | 2 |
| CompetitionPresentationBoundaryTests | 20 |
| SmartCubeGuidanceLifecycleTests | 10 |
| SmartCubeCurrentStateGuidanceTests | 9 |
| SmartCubeManagementTests | 10 |
| SmartCubeOwnershipAuditTests | 5 |
| PublishedCompetitionPRTests | 9 |
| PublishedSelectorRegressionTests | 6 |
| CompetitionAllResultsTableTests | 7 |
| CubingLiveRecordDiscoveryTests | 6 |

Exactly **one final unsigned generic iOS Debug build** was run in this pass: **BUILD SUCCEEDED**, exit 0. Command: `xcodebuild build -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/competition-navigation-loading/DerivedData -skipPackageUpdates CODE_SIGNING_ALLOWED=NO`. Log: `final-unsigned-generic-debug.log`; successful completion recorded 2026-10-20 around 13:16 CST. Simulator test compilations below are not additional generic builds.

Existing nonfatal diagnostics include the large CompetitionTabView's explicit-return ViewBuilder warning and skipped App Intents metadata extraction without an AppIntents dependency. No production or test source was modified after the source freeze or final successful build; only this closeout documentation/artifacts were completed.

`git diff --check` and whitespace checks for the task's untracked additions passed. The task-delta/hash audit found **six initial source/test files changed, two test files added, zero removed, and 7,301 other initial source/resource/project files unchanged**. `project.pbxproj` matches the initial hash. All frozen input hashes still match. Final status and the preservation evidence are retained in `final-status.txt` and `preservation-audit.txt`; the worktree intentionally remains dirty.

All earlier stages remain in the artifact directory; failed stages are not reported as passes.

Staged findings:

- `layout-isolation-v1`: 9 XCTest tests, one newly written unequal-width expectation failed. The real balancing cost favors a one-item first row for that synthetic width sequence, not the expected two; the expectation was corrected without changing production layout to fit it. Other glyph/family tests and four isolation variants passed.
- `focused-final`: 94 XCTest plus 19 Swift Testing composition tests; one new ownership test failed with eight assertions about the unsupported SCNView release deadline. Other tests passed.
- `layout-ownership-final` and `ownership-weak-observation`: retained that failing assertion while isolating autorelease behavior; not passing verification runs.
- `scenekit-isolation`: controlled pause/detach experiment passed as evidence collection, not proof of a leak or fix.
- `scenekit-controls-mounted`: plain UIView/SCNView controls passed; actual mounted oversized content exposed two active subscriptions and failed its one-owner regression.
- `single-content-fit`: **19 XCTest tests passed** after the single-content correction, including 10 existing management tests, five ownership/audit tests and four regional layout tests.

The final source is frozen before the final test/build sequence. Existing unrelated test assertions have not been weakened. Only the earlier one-row/+N tests changed to the newly approved complete-events product contract. The new ownership deadline was corrected based on native controls, not by hiding the two-subscription failure.

## G. Remaining Risks

- Physical Filter delay remains unresolved. The simulator isolation rules out none of the unmeasured physical-only native coordination causes; it does not justify opening a second native surface early.
- Extreme Dynamic Type intentionally needs more than two rows; icons remain readable and complete, with uniform family height. VoiceOver and real localized competition names still merit manual acceptance.
- Original Smart Cube 19-turn behavior is not physically revalidated. Native firmware reset/reconnect/late callback behavior, hand gestures, minimum-iOS runtime and device GPU/RSS cannot be proven by these simulator fixtures.
- The management overflow fitter now has one ongoing content owner but may remount once when switching between natural and overflow branches. Preserve the normal card appearance/scrolling and confirm no perceptible fit flash on the physical phone.
- Native SceneKit view caching/release timing is an explicit unproven resource boundary, not a claimed application leak or a fabricated successful cleanup.

## H. Short Physical Acceptance Checklist

1. In Explore's regional carousel, check 8/13/17-event competitions at default and larger text: every icon visible, stable neighboring card heights, ordered balanced rows, expected competition destination and full VoiceOver names. At extreme accessibility sizes, expect additional readable rows, not +N.
2. Repeat Filter close/rapid reopen on the actual iOS 27.2 beta. Delay is still unresolved; do not interpret the simulator's shorter interval as a physical fix. No identical capture is required merely to reconfirm it.
3. On the physical Smart Cube setup, check a stopped deviation still publishes guidance without another move, then Reset/new target/navigation during a pending search rejects old guidance. This is a short regression boundary, not a substitute for the earlier hardware acceptance plan.
4. Open/close the management card repeatedly, including an accessibility-size overflow case; verify one visible cube, unchanged drag/animation/card appearance, normal wrapping versus scroll, and no visible fit flash. With two devices, viewing/resetting/disconnecting/forgetting B must not redirect Timer from A or erase solve history.
