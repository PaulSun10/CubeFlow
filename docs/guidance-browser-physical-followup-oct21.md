# Guidance and Competition Browser Physical Follow-Up

Status: engineering corrections and focused verification complete, October 21, 2026. This report does not claim physical acceptance.

## Scope and Baseline

Continue the existing dirty worktree. Baseline status, complete tracked diff, source copies and hashes are in `build/guidance-browser-followup-oct21/`. Preserve prior scrolling, Top Cubers, card/navigation and protocol corrections. No TestFlight distribution work, physical-device operations, signed build, archive, upload, commit, push, reset, revert or cleanup.

## Physical Crash Evidence

Input: `/Users/paulsun/Downloads/CubeFlow-2026-10-21-112857.ips`.
The foreground app aborted on the main thread on iOS 27.2 beta (24B5084k), about 7.5 seconds after launch. Exception is EXC_CRASH / SIGABRT, not a Swift date-predicate or dictionary trap. Last exception backtrace includes:

```text
BUG_IN_CLIENT_OF_TARGETED_PREVIEW__VIEW_IS_NOT_IN_A_WINDOW
-[UITargetedPreview initWithView:]
UIKitPopoverBridge.dismissAndReset(viewController:animated:)
UIKitPopoverBridge.updatePopoverIfNeeded(...)
UIKitPopoverBridge.preferencesDidChange(...)
_UIHostingView.preferencesDidChange()
```

This proves dismissal tried to construct a targeted preview for a detached view. It does not identify which concrete source view or which application update detached it. Apple documents that this initializer creates a preview for a [view in the current window](https://developer.apple.com/documentation/uikit/uitargetedpreview/init(view:)). No private API, exception swallowing or disabled animation is used as a workaround.

## Confirmed Browser Lifetime Defect

`normalCompetitionBody` applied toolbar/popover modifiers directly to `competitionListSurface`, whose root changes from a SwiftUI loading `List` to a native collection-view representable. Cold status changes reset the list before an asynchronous cache/row-preparation result arrives.

New regression mounts the actual Browser and its actual toolbar/filter, using only injected list responses. It exercises Present/Past/Recent with List and Glass, keeps the popover open, then closes and immediately reopens it. Baseline v1 failed three assertions: native content remained window-attached while the presentation intent was already false. Baseline v2 reproduced the same three failures with lifecycle capture enabled.

The v2 trace records native generation 1 appearing, an unrequested dismissal on the first cold status update, content observer reconstruction/dismantling, and a replacement local native binding at generation 0. An observer that never joined a native container also acknowledged completion before the original native transition completed. Later warm-cache cycles do not reproduce the first-cycle mismatch. This is a demonstrated application ownership problem, not a conclusion that every UIKit failure is application-only or OS-only.

Correction: place the loading/loaded conditional inside a stable one-child `ZStack`, retaining toolbar/popover ownership above it. Preserve the same SwiftUI `.popover`, native Glass, anchors, transition callbacks and scroll implementation. No status date semantics or async request guard changes. Stable-root v3 passes the previously failing test: all 18 status selections across six List/Glass cycles retain the same modal and its current presentation generation. The trace has zero unrequested dismissals and zero native-binding resets to generation 0 after opening, compared with the baseline failure.

The physical crash's failure class is consistent with the invalidated hierarchy, but absence of the iOS 27.2 simulator and missing concrete source-view identity in the crash report remain limitations. The new regression is not yet a claim of a physical crash fix.

## Guidance Findings

The existing canonical event feed, session-to-active routing, Timer ingestion, current-to-exact-original-target reduction, controller scheduling and publication guards were inspected independently of the solver budget.

Confirmed scheduling defect: the independent exact-short lane was started only after the 120 ms trailing native-search settle. Repeated input resets that wait, so even an exactly short current state cannot begin its cheap search while input continues. A gate-based regression holds the native settle without releasing it; the old implementation fails to publish an exact one-turn answer. No solver-speed assumption is involved.

Correction: start cancellable exact-short work immediately; keep the trailing settle only for the heavier native lane. Obsolete tickets/source/target/device ownership checks remain. Exact success cancels the now-unnecessary settle; exact misses drain native work only once the current request is settled. The previously failing settle-gate regression passes, as does a 20-turn legal relative-state sequence while the native settle remains pending. Equal verified continuations remain quiet; diagnostic reuse now records known/candidate cost, origin and optimality.

This does not establish that the user's 15-20-turn physical observation has only this cause. Canonical ingestion, suppression, equal-path retention, native search, stale rejection and rendering must be distinguishable in the final diagnostics. No global optimality is claimed for bounded native answers.

## UI Corrections and the Cross-Row Acceptance Correction

- Regional Explore glyphs used advance-centered text inside accepted fixed square cells. Apply the negative measured glyph ink-center offset only in the regional strip; no per-event constant. Initial raster assertions established ink centering within each cell, but did **not** establish cross-row column alignment. The user correctly rejected the v3 gallery: row spacing was computed independently, so a full first row at 248 pt used 4 pt gaps while the shorter final row used 6 pt. That adds 2 pt displacement per subsequent column, including 4 pt at the third column. The final all-glyph layout reuses the first row's gap for every wrapped row. First-row packing, icon size, cells and reserved card height remain unchanged. Fallback variable-width text layout is unchanged. New mounted assertions compare every cell center to the first row (0.01 pt tolerance), in addition to actual raster ink-center checks (0.7 pt tolerance), across counts, widths and accessibility sizes. All final grid tests passed, including the unchanged family card heights. Final light/dark galleries were inspected at original resolution; the rejected v3 gallery is not represented as the final appearance.
- Management title now reuses a common modifier extracted without visual change from the WCA Results card: 24 pt bold, primary foreground, vertical wrapping, 38 pt close-button reserve, 22 pt content inset. Battery uses 24 pt regular monospaced digits, center-aligned with the title.
- Management Reset uses blue-tinted regular native Glass, Forget red-tinted Glass/red text, Disconnect neutral Glass; no glassProminent solid fill. Native `.glass(.regular.tint(...))` on iOS 26.1+, `.glass` with tint on 26.0, `.bordered` fallback on older supported iOS. Keep per-device actions, confirmations and single content ownership.
- Remove the misplaced `@ViewBuilder` from the Void-returning side-effect-only `configureWCALiveSession`. The warning is independent of the targeted-preview crash.

## Remaining Native Dismissal Interval

The stable actual-Browser v3 trace contains 366 events, zero dropped. Across 12 intentional native dismissals, native will-disappear to actual transition-coordinator completion is 794.92-925.34 ms on iOS 26.5. App completion is 0.013-0.031 ms after that coordinator callback. Native-declared duration is 0.34 seconds; do not substitute that nominal duration for measured elapsed time. The surface becomes window-detached approximately at native completion, but this is not proof of the first fully invisible compositor frame.

This is new full-Browser evidence after removing the ownership failure, not a rerun presented as a new independent SwiftUI/UIKit comparison. The remaining interval is still in the observed native lifecycle. It neither proves an OS-only fault nor justifies arbitrary delays, bypassed completion, a replacement presenter or disabled Glass/animation. Physical dismissal latency remains unproven after the ownership correction.

## Practical DEBUG Guidance Evidence

The existing general diagnostic ring retains 2,048 entries. A second bounded 2,048-entry lane retains only guidance and relevant protocol/canonical/coalescing/Timer move events, so continuous gyro packet traffic does not erase the useful timeline during navigation. Both stores and export UI compile only in DEBUG. No raw facelets, scramble text, persistent device IDs or personal names are added. Export formatting/sorting remains outside the lock and off the move-processing path.

New stages distinguish a newly received event, epoch ineligibility, canonical move consumption, lifecycle suppression, an already-covered snapshot, search scheduling, candidate identity checks, an equal verified continuation and accepted adoption. Existing solver durations/source-target digests and SwiftUI-update evidence remain. A SwiftUI update is not a GPU-present frame. `Copy Guidance Diagnostics` in the existing Smart Cube Protocol Debug controls copies this retained TSV without a debugger. A deterministic test floods the generic ring with 4,096 parser entries and verifies that move/guidance evidence remains available, private IDs remain shortened and the export remains bounded.

## Verification Ledger

- filter-baseline-v1: one actual Browser/Filter test failed three assertions; evidence retained.
- lifecycle-baseline-v2: two tests failed five assertions, reproducing Browser intent/native mismatch and exact-short work waiting behind native settle. No failed run counted as passing.
- stable-root-fast-v3: 27 XCTest passed (one actual Browser lifecycle, seven Explore including the original within-cell raster check, seven latest-guidance and 12 management). Its green Explore checks were insufficient to accept cross-row alignment; the user-provided counterexample and new assertions above supersede that conclusion.
- focused-v4: 83 XCTest passed, including 20 native/card/navigation boundary cases, eight date cases, five mounted async publication cases, nine Top Cubers sizing/animation cases, guidance lifecycle/latest/diagnostics/ownership and 13 management cases.
- grid-v5: 16 XCTest passed: seven Explore tests with final cross-row assertions, and nine current-state guidance regressions.
- filter-27-v6: the same actual-Browser lifecycle test passed on the already-installed iOS 27.1 runtime using `test-without-building`. Xcode logged a beta runtime build-number parsing warning; the xcresult summary independently confirms one executed/passed test, zero failures/skips. No new runtime was installed. This is a repeated test identity, not another distinct test.

Passing coverage union: **99 distinct XCTest**, not the sum of reruns. `verified-test-union.txt` lists every identity. This is focused subsystem/regression coverage, not the full project suite. Existing stale-refresh ABA negative control, native Result Card/Back tests, Top Cubers self-sizing and progressive animation tests passed without weakening their assertions.

The **one final unsigned generic iOS Debug build passed**, exit 0, on the frozen production source:

```sh
xcodebuild -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/competition-navigation-loading/DerivedData \
  -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
```

`final-unsigned-debug.log` / `.exit` retain the result. The ViewBuilder warning is gone. The remaining build warning is skipped AppIntents metadata extraction because the app has no AppIntents.framework dependency; no unrelated fix was added. App minimum iOS 15 and existing project settings remain unchanged.

Pre/postbuild SHA-256 and final `git diff --check` passed. Baseline comparison: **7,303 unchanged files, 14 scoped modified files, one added test file, zero missing files**. `project.pbxproj` remains byte-identical to the task baseline, including accepted external changes. No unrelated source changes, cleanup, physical-device operations, signing, archives, uploads, commits or pushes.

## Exact Changed Files

```text
CubeFlow/Views/Shared/SmartCubeDiagnostics.swift
CubeFlow/Views/Shared/SmartCubeGuidanceController.swift
CubeFlow/Views/iPhone/CompetitionBrowserPublicationAcceptance.swift
CubeFlow/Views/iPhone/CompetitionResultsStyle.swift
CubeFlow/Views/iPhone/CompetitionTabView.swift
CubeFlow/Views/iPhone/CompetitionUIDiagnostics.swift
CubeFlow/Views/iPhone/Explore/ExploreCompetitionEventStrip.swift
CubeFlow/Views/iPhone/SmartCubeLabView.swift
CubeFlow/Views/iPhone/SmartCubeManagementCard.swift
CubeFlow/Views/iPhone/TimerTabView.swift
CubeFlowTests/ExploreRegionPackingTests.swift
CubeFlowTests/SmartCubeGuidanceTraceTests.swift
CubeFlowTests/SmartCubeLatestGuidanceTests.swift
CubeFlowTests/SmartCubeManagementTests.swift
CubeFlowTests/CompetitionFilterLifecycleFollowupTests.swift (new)
docs/guidance-browser-physical-followup-oct21.md (new report)
```

Production Timer changes in this task are DEBUG observation only. The functional guidance scheduling change is confined to its controller. Protocol parsing, readiness, Combined, target semantics, native move animation and timing persistence are unchanged. WCA Results only replaces two identical title modifier chains and the same 22 pt content inset with their shared definition; tables, badges and navigation are not redesigned. Browser changes are the stable surface container and DEBUG test observation; UICollectionView scrolling/layout, card interaction, Filter presentation architecture and request/date policy are untouched.

## Visual Artifacts

Root: `build/guidance-browser-followup-oct21/`.

- Final aligned dark gallery: `final-grid-images/0BA9668B-DC4D-452C-A71B-D7625BD34515.png`.
- Final aligned light gallery: `final-grid-images/9529C225-4E4A-440F-821B-45DDA0AC5DB8.png`.
- Management title/battery/blue-neutral-red native Glass, light: `management-final-images/7E7E7E52-7892-464C-B3EC-E2848B52C2D0.png`.
- Same management fixture, dark: `management-final-images/E7BBD9ED-A301-4D74-98CB-E686E3A40B69.png`.
- Each directory's xcresult manifest maps original fixture names to the exports. The management typography fixture deliberately uses the existing disconnected cube symbol rather than claiming a live BLE renderer; separate connected/inactive 2x2 ownership and SceneKit regressions passed.

## Manual Physical Acceptance and Precise Diagnostics

Only the user should run/install the source on the physical iPhone. No device was accessed by this agent.

### Guidance

1. In the DEBUG app, enable Settings > Development > Debug Mode. Open Settings > Connected Devices > the current Smart Cube's existing diagnostic controls. Enable Protocol Debug **after** Debug Mode (toggle off/on if it was already enabled). Leave Verbose Packets off for the normal guidance reproduction.
2. Use an approved, trusted 3x3 and retain the current original scramble/reference. Do not use Mark Solved during this reproduction. Try one early deviation and one deviation with about five original moves remaining. Pause after the first wrong turn; do not make another turn merely to force an update.
3. Try a short deviation, rapid consecutive turns, then stop for about two seconds. The final state should receive guidance without additional input. A correct equally short continuation may intentionally remain unchanged; it is not evidence that no computation occurred. Complete the exact target and immediately get the next scramble: no old guidance/loading may carry over.
4. Return to the existing Protocol Debug controls and press **Copy Guidance Diagnostics before force-quitting or disabling Debug Mode**. Paste/export that text with the observed symptom and approximate action timing. No debugger is required. The in-memory ring survives this navigation but not process termination and is still finite.
5. Interpret the evidence by stage: protocol move absent means inspect raw protocol input; protocol move present but canonical missing points before canonical publication; canonical present but Timer event ineligible identifies epoch/trust/lifecycle gating; scheduled but no candidate separates search/cancellation from input loss; continuation-reused includes both verified costs; candidate/adoption identity checks explain rejection; adoption plus SwiftUI update separates publication from an unproven display/compositor issue.
6. Only if pre-canonical input is missing, use the already-existing Start/Stop/Copy Capture to accompany a short repetition with raw RX/decrypted timing. Do not guess protocol mappings or collect a broad calibration sequence. A valid exact state-to-original-target path remains mandatory; deep native answers are best verified, not globally proven optimal.

The settle-gate test now completes in 0.009 seconds and the 20-turn relative-state sequence in 0.094 seconds in focused-v4. These are entire simulator test-method durations, **not physical BLE-to-display latency measurements** and not proof that every far-from-target state fits a strict wall-clock budget. The native search budgets/table-initialization limitations from the prior pass remain unchanged.

### Browser / Filter

1. Test from a fresh app launch, both List and Glass. Open Filter while loading and after rows appear. Exercise Present -> Past -> Recent -> Present repeatedly, including a valid region/year/event combination that has not already been loaded. No cache deletion is needed. Warm-only switching is not a sufficient reproduction of the original cold-root failure.
2. Leave Filter open while changing status; it must remain interactive. Close and immediately request reopening; only one native popover may exist and reopening must wait for genuine native completion, not a fabricated acknowledgement. Navigate away/back and test again. Verify the existing native animation, Glass and scrolling are retained.
3. If a problem remains, enable the existing Development > Filter Capture before the short reproduction, stop afterward and share its JSON. The new `anchor-window-changed` entries identify passive toolbar anchor attachment/loss alongside existing intent/native callbacks. If the process aborts before capture can be stopped, share the new `.ips`; do not assume an unfinished capture was durably saved. No full private hierarchy or exact preview-source identity is available from the supplied `.ips` alone.

### Visual and Ownership Acceptance

Check the real 13-/17-event regional cards: compare the centers of corresponding columns across rows, especially Pyraminx/Skewb/Square-1, not only centering inside each glyph's own cell. First-row capacity, icon sizes and shared card height must remain accepted. Compare the management name directly with a WCA Result Card competitor title; confirm 24 pt name/battery balance, native blue Reset/red Forget/neutral Disconnect, independent viewed device, per-device actions and overflow behavior.

## Remaining Limitations

The supplied physical crash establishes a detached-preview abort; the application lifetime defect is reproduced and corrected on 26.5/27.1. Physical iOS 27.2 acceptance is still required, and no claim is made that all possible framework preview bugs are eliminated. The 15-20-extra-turn symptom may include causes beyond the proven exact-lane settle delay; the new diagnostics are intended to distinguish them. Native Filter dismissal latency remains unresolved physically. SCNView framework release timing is not equated to application subscription ownership, and no renderer lifecycle rewrite was made. This task does not reopen TestFlight distribution/security work.
