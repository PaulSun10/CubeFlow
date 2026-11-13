# CubeFlow Reliability and UX Audit

Date: 2026-11-02. Scope: the supplied comprehensive reliability brief, on the existing dirty `main` worktree. No physical devices were accessed.

## A. Executive Summary

The main scramble defect was integration, not defective TNoodle random generation. Swift treated native IDs as Java registry enum ordinals (minus FOUR_FAST). The exported C entry point actually indexes a separately ordered `Main.puzzles[]`. This explains the three reported blindfolded cross-puzzle outputs and Pyraminx receiving Skewb notation without tips. Runtime grammar-based index probing was also unsafe and has been removed.

A further audit found Multi-Blind used ordinary 3x3 instead of the no-inspection/random-orientation generator. This is corrected. FMC has a different limitation: the bundled C array does not expose the dedicated FMC generator at all. It now fails explicitly rather than returning Clock or ordinary speed scrambles. Consequently this is NOT a claim that all 19 options are now fully usable.

Other fixes cover per-player battle scramble ownership and contact feedback, measured PR placement, prepared regular/battle haptics, notes dismissal, native equal-width penalty selection, Algorithms row hit regions, Follow System defaults, WCA special regions, and official participation checkmarks. Record-marker latency and all seven evaluation-only topics are documented below, not presented as newly implemented features.

## B. Scramble Audit

### Evidence and boundary

The bundled dylib SHA-256 was freshly checked as `35ca5611930688d63e6e43b9e2a5d49d6c9dec08ca54a98a136645ce454b4103`. Existing provenance is in `docs/tnoodle-native-evidence-oct22.json`. The local pinned source archive is `ThirdPartySources/TNoodle/tnoodle-lib-native-v1-e50c528feb8220b99eb66575a748e88391300f1f.zip`.

The decisive source is [pinned PuzzleRegistry.java, including class Main](https://github.com/CubeLabsNZ/tnoodle-lib-native-v1/blob/e50c528feb8220b99eb66575a748e88391300f1f/scrambles/src/main/java/org/worldcubeassociation/tnoodle/scrambles/PuzzleRegistry.java). Its `tnoodle_lib_scramble` calls `puzzles[id].generateScramble()`, NOT `PuzzleRegistry.values()[id]`.

The table's old number is the previous preferred ID. Special-puzzle probing could sometimes find a different ID at runtime; it was not trustworthy device classification. M = exhaustive event mapping test; N = injectable native-call/notation fixture; L = shared mounted lifecycle and prefetch coverage, NOT a separate mounted run of every listed event. Native iOS TNoodle execution was NOT performed: the simulator deliberately reports that engine unavailable. These fixtures prove dispatch and preservation, not the distribution of every random sample.

| CubeFlow event / WCA identity | Expected implementation | Old preferred routing | Corrected routing / verified behavior | Coverage |
| --- | --- | --- | --- | --- |
| 2x2 / 222 | TwoByTwoCubePuzzle | 0 | 0, unchanged | M/N/L |
| 3x3 / 333 | ThreeByThreeCubePuzzle | 1 | 1, unchanged | M/N/L |
| 4x4 Standard / 444 | FourByFourCubePuzzle | 2 | 2, unchanged | M/N/L |
| 4x4 Fast / custom 444 variant | Existing local 40 random turns | Local branch | Retained local branch; not native FOUR_FAST or random-state Standard | M; existing 40-token generator test |
| 5x5 / 555 | CubePuzzle(5) | 3 | 3, unchanged | M/N/L |
| 6x6 / 666 | CubePuzzle(6) | 4 | 4, unchanged | M/N/L |
| 7x7 / 777 | CubePuzzle(7) | 5 | 5, unchanged | M/N/L |
| One-Handed / 333oh | Ordinary 3x3 | 1 | 1, unchanged | M/N/L |
| 3BLD / 333bf | NoInspectionThreeByThreeCubePuzzle | 6 = Square-1 | 12, preserves native random orientation | M/N/L |
| 4BLD / 444bf | NoInspectionFourByFourCubePuzzle | 7 = Megaminx | 13, preserves native random orientation | M/N/L |
| 5BLD / 555bf | NoInspectionFiveByFiveCubePuzzle | 8 = Pyraminx | 14; the suspected mismatch is confirmed by C-array dispatch | M/N/L |
| Multi-Blind / 333mbf | N copies of no-inspection 3x3 | N copies of 1 | N copies of 12; count remains part of request ownership | M/N; count/prefetch tests |
| Megaminx / minx | MegaminxPuzzle | 12, then probing | 7 | M/N/L |
| Pyraminx / pyram | PyraminxPuzzle | 10 = Skewb, accepted by permissive grammar | 8, native tips preserved verbatim | M/N/L |
| Square-1 / sq1 | SquareOnePuzzle | 11, then probing | 6 | M/N/L |
| Clock / clock | ClockPuzzle | 13, then probing | 9 | M/N/L |
| Skewb / skewb | SkewbPuzzle | 14, then probing | 10 | M/N/L |
| Fewest Moves / 333fm | Dedicated ThreeByThreeCubeFewestMovesPuzzle | 9 = Clock | Explicit unavailable: slot 11 is ordinary 3x3, not FMC | M; fail-closed fixture |
| FTO / fto | Existing local JS random-state engine | Local branch | Unchanged, no native C index | M; four existing independent geometry/notation/state/prefetch tests |

### Pyraminx

The pinned native Pyraminx generator includes unsolved tips in its random-state solution. A legitimate state can have no tip moves, so requiring a lowercase tip in every scramble would be incorrect. The prior slot 10 returned Skewb, whose R/U/L/B tokens passed Pyraminx's permissive check. No lowercasing/uppercasing removal was found in the Timer formatting, payload, cache, or saved text path. The corrected boundary returns the native string unchanged, including lowercase tips, primes, whitespace, and newlines. No tips are invented or appended.

### Blindfolded and Multi-Blind

[WCA rule 4b3a](https://www.worldcubeassociation.org/regulations/#4b3a) requires random orientation for blindfolded events. [TNoodle's event table](https://github.com/thewca/tnoodle/blob/master/server/src/main/kotlin/org/worldcubeassociation/tnoodle/server/model/EventData.kt) explicitly maps Multi-Blind to the same no-inspection puzzle family as 3BLD. Its native implementation already constrains the solver appropriately when applying orientation; CubeFlow must not approximate this by appending arbitrary moves. All blindfolded paths now select the appropriate native implementation.

### Standard, Fast, and FMC

Standard 4x4 uses the native solver-based generator. Fast is an existing local random-turn training variant with 40 moves and adjacent-axis rejection; it is not an alternate native random-state solver. Keep it for compatibility/training, but do not describe it as equivalent to Standard or as a competition-certified generation mode. No option or persisted event ID was deleted.

The Java enum declares a dedicated FMC class, but the C array does not instantiate it. That dedicated implementation uses solver axis restrictions as well as its FMC prefix/suffix. Simply wrapping an ordinary 3x3 scramble would not reproduce that implementation. Restoring FMC requires a separately justified native capability/build decision, not index guessing. No framework was replaced or rebuilt.

This audit validates CubeFlow's integration against its pinned implementation. It does not certify an older bundled TNoodle build for generating official WCA competition scramble sheets; [WCA rule 4b](https://www.worldcubeassociation.org/regulations/#4b) separately requires the current official scramble program.

### Ownership and failure

Regular requests retain session/event/count/device/connection context and request tokens. The existing stale-response, session-switch, event-switch, and one-shot prefetch tests remain in place. Text/diagram activation stays atomic. A retained Cards presentation awaiting replacement can no longer become a fresh solve assignment. Persisted regular/manual solves still use the captured assignment, not a later selected event or text. Generation failure does not probe other puzzle slots or fabricate a fallback.

## C. Implemented Fixes

| Issue | Root cause | Implementation and regression protection |
| --- | --- | --- |
| Wrong native puzzles | Wrong C ABI ordering; grammar probing confuses compatible token alphabets | Fixed enum, checked native bounds, removed probing; exhaustive mapping, native fixtures, no-probe failures |
| Consumed Cards scramble reuse | Old visible snapshot could still satisfy assignment creation while replacement pending | `currentSolveAssignment` now rejects pending replacement; mounted consumed-target regression |
| Battle scramble advancement | Event-keyed shared cache; both scrambles reset on preparation | `LocalBattleScrambleState` owns per-player request/displayed/active/completed assignments; finishing advances only that player |
| Battle touch feedback | Drag gesture recognition and readiness state doubled as contact visualization; no explicit cancellation route | Direct UIKit contact surface; separate per-player contact set; immediate down/up/cancel; no duration threshold |
| PR collisions | Fixed -90-point offset | Measured banner/timer/upper content/bottom obstacles; place in free interval per arrangement |
| Regular haptic perception | No distinct weaker style found; both modes allocated rigid generators at each call | Shared prepared rigid generator, explicit full intensity; one impact per existing readiness callback |
| Notes keyboard | No focus binding/dismissal toolbar | FocusState, keyboard Done, appropriate scramble tap dismissal, interactive scrolling on iOS 16+; existing save normalization retained |
| Unequal penalty controls | Content-sized, uniformly prominent buttons | Native equal-width/fill-height UIStackView, Sessions action configuration, selected tint, separate destructive Delete |
| Algorithm blank row areas | Plain NavigationLink label lacked a full-width explicit hit shape | Expanded shared overview label's content shape; no gesture overlay or spacing change |
| English on first launch | Hardcoded fallback with no system registration policy | Register resolved system default without persistence; explicit overrides retain priority |
| XW label | ISO locale lookup cannot name WCA fictive countries | Shared authoritative eight-region mapping plus localized display names |
| Participation absent | No official-result membership attached to My Competitions | Shared public profile cache, ID/path-based result evidence, request/account/publication-revision protection |

Battle timing origins, valid-start guard, scoring, handicap math, and the rule for beginning a subsequent scored round were not redesigned. Scramble advancement itself does not wait for both players. The pre-existing local battle mode has no Core Data solve-history writer. Its new bounded completed assignment retains the exact event/request/text; this task does NOT invent persistent battle history or claim to have tested nonexistent saves.

The full-width native penalty stack was necessary because independent hosted native buttons could have equal widths but heights differing by 20 points when No Penalty wrapped. The mounted regression now checks both dimensions. The native style policy itself and other Smart Cube action buttons remain unchanged. Applying a penalty still saves and dismisses as before; Delete's existing confirmation is unchanged.

## D. UX Behavior

Cards and Split put PR between the measured Timer bottom and the top of lower cards/statistics/diagram. Classic puts it below the actual upper scramble content and above Timer. Banner height is measured even when no legal interval exists, avoiding guessed-size dead ends. Extremely constrained/custom arrangements with no room suppress the banner rather than overlap controls; detection and notification lifetime are unchanged. Physical layout acceptance is still needed.

The regular and battle Timer share prepared rigid feedback. No separate in-app Timer haptics preference was found or removed. There is no second impact or timing-rule change. Subjective strength cannot be verified on Simulator.

Contact green now represents actual contact, separate from readiness/running state. Release/cancel removes contact immediately; cancelling does not start a timer. Both players still need the original valid-start relationship, and each release establishes only that player's own start date. Native menus and exit controls remain above the contact surface.

Notes Done saves the normalized comment and ends editing without closing Solve Detail. Scroll dismissal is availability-gated. Penalty capsules have native tint only for the current selection and non-prominent native backgrounds otherwise. Labels include localized No Penalty; Delete stays separate/red. Overview categories share the same full-row hit region.

Follow System is represented by absence of a persisted `appLanguage` override, not a raw `system` language flowing into existing language-specific branches. Supported localization matching handles zh-Hans/zh-Hant and region preferences. Registration refreshes on foreground; iPhone also handles locale-change notifications. Manual overrides are never rewritten. Persisted English cannot retrospectively be distinguished from an intentional old choice and is therefore preserved. English is the unsupported-language fallback.

WCA API was directly checked for FMC under the Mistletoe 2026: city Multiple Cities, `country_iso2: XW`. The official website displays Multiple Countries (World). The eight special codes come from [WCA countries.fictive.json](https://github.com/thewca/worldcubeassociation.org/blob/main/lib/static_data/countries.fictive.json); normal ISO country presentation remains localized. New primary-language strings cover English, Simplified Chinese, and Traditional Chinese, with the existing localization fallback for other languages.

Participation is sourced from rows in the signed-in WCA ID's official person results, not registration, dates, competition totals, or completion status. Reuses the public profile cache's 15-minute freshness and request coalescing. Explicit refresh can force current evidence. No per-competition scan is added. Missing/unavailable evidence creates no checkmark; account/session changes clear it and delayed old responses cannot republish it.

### PR/NR delay investigation

Official competition result JSON supplies regional record flags. Historical PR presentation additionally joins server-authored `pb/wr/cr/nr` cells from the official person HTML. This is a separate publication and cache dependency, not a local comparison of numbers. `WCAPublicProfileCache.pageFreshness` is 15 minutes; visible enrichment has a 60-second attempt throttle and up to four concurrent requests. Explicit results refresh calls `refreshVisible`, bypassing the throttle/cache for relevant people. Nine existing PR tests cover this publication/cache/retraction path and exact result matching.

No concrete competition/provider snapshots establishing the reported timing sequence were supplied. A delayed upstream person page or a still-fresh cached page can explain later PR appearance, but that is a supported dependency, NOT proof of this incident's cause. NR normally comes from competition metadata and should not be conflated with the PR enrichment delay. No numerical record inference, cache-policy speculation, or broad source rewrite was added. Next evidence should be the same competition/result payload and person-page marker, with cache/refresh timestamps, before and after the discrepancy.

## E. Technical Evaluations Only

### 1. Opposing-orientation event selector

Feasible, medium complexity. Current `TimerLocalBattleView` rotates the opposing panel, but system Menu presentation belongs to system presentation coordinates. Do not retry rotation modifiers on Menu. Use a single small custom selector surface, shared event model and 4x4/BLD groupings, with explicit owning player and 0/180-degree content orientation. Reuse native materials/buttons, bounded adaptive width, 44-point targets, VoiceOver ordering, and outside dismissal. Keep the entire selector outside/above the Timer contact surface and clear contact on presentation. A player-owned overlay is more predictable than trying to force popover/system-menu orientation. Worth a focused next UX pass; not implemented here.

### 2. Handicap controls

Retain the 0...10-second model and existing scoring calculation. The current setting on one player subtracts time from the opponent's adjusted result, i.e. giving the opponent an advantage, and current strings are Chinese-specific. Make the giver/receiver explicit in a localized selector and summary. Reuse the future event-selector shell with correctly oriented content and minus/value/plus or bounded native selection; no accidental swipe adjustment over Timer. Medium complexity; implement with selector work, not by changing competition rules now.

### 3. Battle layout

The split VStack/HStack, per-player controls, own elapsed values, handicap, and scores are reusable. Long Megaminx/Multi-Blind text is currently limited to four lines at 18 points with a 0.58 scale floor; small landscape halves cannot guarantee comfortable full visibility. Preserve timer touch priority and move detailed scramble reading into a bounded, explicit non-timing surface in a later pass. Do not blindly enlarge overlapping targets. Test small/large landscape phones, opposing orientation, Dynamic Type, and two contacts together. Medium complexity; targeted iteration soon, no broad rewrite.

### 4. Inline manual keypad

Feasible, medium complexity, optional rather than replacing current input. Existing `manualTimeInputField`, `parseTypedTime`, `saveTypedTime`, and `currentSolveAssignment` should remain the only parsing/saving path. A later input strategy can feed the same string through digits/colon/backspace, with explicit submit and penalty controls. Backspace edits input, never deletes a saved solve. Reserve keypad height in layout/safe-area calculations, not over Cards/Split components or PR. On narrow screens prefer a compact dedicated entry region or existing keyboard. Include VoiceOver, hardware keyboard, DNF/+2 meaning, invalid-input feedback, and repeated-entry focus. Defer until dedicated interaction acceptance.

### 5. Nearby / NameDrop-like pairing

Feasible public-API approximation, high complexity; exact system NameDrop behavior is not a promised third-party API. Current `NearbyBattleManager` already uses Multipeer Connectivity with required encryption and round-ID/scramble messages, but auto-accepts invitations. Future deliberate pairing needs mutual confirmation/session identity, not proximity alone as authentication.

[Apple's NI session guidance](https://developer.apple.com/documentation/nearbyinteraction/initiating-and-maintaining-a-session) requires app-chosen discovery/handshake and NI permission. Check feature capabilities (iOS 16+) or `isSupported` on iOS 15; not every device supports UWB. [Apple's MPC token exchange guide](https://developer.apple.com/documentation/nearbyinteraction/discovering-peers-with-multipeer-connectivity) provides the network transport pattern and local-network/Bonjour requirements. Use existing encrypted MPC as transport, optionally NI to rank/confirm nearby peers, and a manual-confirmation fallback without UWB. CoreBluetooth is optional, not a way to invoke NameDrop; direct Bluetooth use brings its own permission/energy costs.

No fixed latency or background-discovery guarantee. Exchange protocol version, match nonce, round ID, event, immutable scramble/hash, sequence numbers and ready acknowledgements. Measure local solve durations with monotonic clocks in the future protocol, never network arrival timestamps. Recover by exchanging agreed round state; reject stale/replayed or mismatched scrambles and surface disconnect/ambiguous rounds instead of inventing a fair result. Do not transmit WCA credentials or location history. Defer to a standalone networking/security/physical-device milestone.

### 6. Native minimizing Tab Bar and right action

Feasible with limits, medium complexity. `IPhoneContentView` already owns a single conditional bottom accessory and `.tabBarMinimizeBehavior` (iOS 26+). The enabled accessory overload is gated at iOS 26.1. [Apple's placement API](https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement) exposes expanded/inline placement inside the accessory, not a continuous minimization fraction or stable public exact bar frame.

Prefer a system-managed accessory composition that adapts its own content. It shares the existing accessory slot and cannot simply be stacked as a second accessory. A separate overlay can observe placement propagated from the accessory and move between two safe-area-relative targets, with Reduce Motion, but that is discrete coordination, not evidence for frame-perfect synchronized circles. Exact system search-tab circle behavior should not be repurposed as an arbitrary action. No private hierarchy inspection. Older OS versions need a stationary safe-area-aware fallback. Prototype/verify on iOS 26/27 before promising the requested choreography; not implemented.

### 7. iPad readiness

High overall complexity, deferred. `IPadContentView` and `MacContentView` are currently Coming Soon placeholders, so this work is not a production iPad port. The new measured PR geometry, flexible native penalty stack and full-width hit regions avoid new device-width constants. A future iPad milestone must mount actual Timer/Algorithms/Solve Detail, review sheet widths and popovers, independent two-player surfaces, rotation/size classes and split-view resizing, keyboard/pointer/accessibility, and native top-tab/sidebar behavior (not assume the iPhone collapsing bottom bar). Start full adaptation after phone correctness/physical acceptance; reuse content components before choosing new navigation architecture.

## F. Validation

All validation is local automated evidence, not physical acceptance. Xcode: `/Applications/Xcode-27.2.app`. Runtime: existing iPhone Simulator, iOS 26.5. App compiles with iOS 15 deployment target; availability guards retain the iOS 15 notes editor/native button fallback.

Final successful evidence (repeated checks are not counted as additional distinct tests):

| Run | Actual result | Evidence |
| --- | --- | --- |
| Coordinated focused set | 40 XCTest + 17 Swift Testing, all pass | `complete.log`, `complete.xcresult` |
| Final Multi-Blind mapping / prefetch | 6 XCTest + 7 Swift Testing, all pass | `final-mapping.log`, `final-mapping.xcresult` |
| Final PR / notes / penalty / language / battle recheck | 9 XCTest, all pass | `final-ui.log`, `final-ui.xcresult` |
| Distinct relevant automated checks across those runs | 58 pass, none skipped or counted from failed runs | 57 in coordinated set, one additional Multi-Blind test; superseded mapping rechecked |
| First unsigned generic Debug build | Passed, before final Multi-Blind/PR measurement corrections | `debug-build.log` |
| Final unsigned generic Debug build | Passed, final production source | `debug-build-final.log` |
| iOS 15 compile compatibility | Passed, final build compiles `arm64-apple-ios15.0` | Final compiler invocation; NOT an iOS 15 runtime test |
| `git diff --check` | Passed | Final worktree check |
| Frozen-file integrity | Passed: Confetti, CubingChina Live/advancement/navigation and other unrelated initial paths unchanged | SHA-256 comparison against task-start `baseline.json` |

Logs/result bundles are local ignored outputs under `build/reliability-nov02/`. Tests used `xcodebuild test -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug`, the existing simulator ID `24E6D520-DF19-4F61-89DB-55F2F418484E`, explicit `-only-testing` selectors, `-parallel-testing-enabled NO`, `-skipPackageUpdates`, and unsigned settings. Final rechecks enabled 60-second per-test limits and disabled diagnostic collection. The final build command was:

```sh
DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer xcodebuild build \
  -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/competition-navigation-loading/DerivedData \
  -skipPackageUpdates CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
```

Earlier runs are not hidden: one initial run had 2 failing tests (asynchronous presentation test timing and changed simulator unavailable diagnostic). A later run had a mounted timeout plus an aborted persistence test. The saved crash report proves an existing simulator audio-service RPC timeout in `AURemoteIO::Cleanup` through `SmartCubeReadySoundPlayer.Audio.init`, not a demonstrated scramble failure. The scramble fixture now disables/restores unrelated ready sound. Mode-transition tests wait for outgoing native views to leave before measuring hit ownership. A final control test exposed a real 20-point native capsule height mismatch; the shared native stack corrected it. No unrelated production audio or existing unrelated assertions were changed to manufacture green results.

The source-only Algorithms hit-shape correction still needs actual navigation acceptance. PR geometry tests prove interval math, not every rendered customized screen. Haptic intensity and ultra-short physical contact presentation are not measurable on Simulator. No device TNoodle samples were collected. No OAuth regression suite, broad UI suite, or unrelated Explore tests were run.

## G. Git and Worktree

Modified relative to this task's saved baseline:

```text
CubeFlow/CubeFlowApp.swift
CubeFlow/Views/Shared/AppLocalizationSupport.swift
CubeFlow/Views/Shared/CompetitionService.swift
CubeFlow/Views/Shared/TNoodleNativeBridge.m
CubeFlow/Views/Shared/TNoodleScrambler.swift
CubeFlow/Views/iPhone/AlgTabView.swift
CubeFlow/Views/iPhone/DataTabView.swift
CubeFlow/Views/iPhone/IPhoneContentView.swift
CubeFlow/Views/iPhone/SettingsTabView.swift
CubeFlow/Views/iPhone/TimerLocalBattleView.swift
CubeFlow/Views/iPhone/TimerScramblePipeline.swift
CubeFlow/Views/iPhone/TimerTabView.swift
CubeFlow/Views/iPhone/WCAMyResultsView.swift
CubeFlow/en.lproj/Localizable.strings
CubeFlow/zh-Hans.lproj/Localizable.strings
CubeFlow/zh-Hant.lproj/Localizable.strings
CubeFlowTests/TimerScrambleLifecycleRegressionTests.swift
```

Added in this task:

```text
CubeFlow/Views/Shared/WCACompetitionPresentationSupport.swift
CubeFlow/Views/iPhone/BattleContactSurface.swift
CubeFlow/Views/iPhone/LocalBattleScrambleState.swift
CubeFlow/Views/iPhone/LocalBattleTestProbe.swift
CubeFlow/Views/iPhone/SolvePenaltySelector.swift
CubeFlow/Views/iPhone/TimerPBPlacement.swift
CubeFlowTests/ReliabilityUXTests.swift
CubeFlowTests/ScrambleNativeMappingTests.swift
CubeFlowTests/WCAOfficialParticipationTests.swift
docs/reliability-ux-audit-nov02.md
```

The task-start baseline contains 24 tracked dirty paths and 15 untracked paths. Existing CubingChina Live/advancement/navigation, Smart Cube Guidance/visual changes, Info.plist, scheme-management state, screenshots, reports, and other dirty tests were preserved. The previously dirty Settings, Timer, and scramble lifecycle test files received only the additive scoped corrections above. No existing path was deleted. Testing/baseline/log artifacts are ignored, not proposed for source control.

Final branch remains `main`, HEAD `82b455c39`: 38 tracked dirty paths and 25 untracked paths in total, comprising the original work plus this task's 17 modified and 10 new paths. No staging or history operation was performed.

No commit, push, tag, release, upload, deployment, physical-device operation, software installation, TNoodle replacement, or backend/OAuth modification occurred.

## H. Outstanding Risks and Manual Acceptance

Confirmed fixed at source/automated boundaries: C ABI dispatch, Pyraminx preservation, blindfolded/Multi-Blind generator choice, stale ownership and failure routing, consumed Cards assignment, per-player advancement/contact callbacks, notes saving/dismissal state, equal native penalty geometry, language override policy, WCA region/result membership.

Requires physical acceptance:

1. Generate several scrambles for every usable event. Check 3/4/5BLD use their cube size and native orientation; verify Multi-Blind count and numbered saved text; Pyraminx includes appropriate native tips across multiple samples (not necessarily every sample).
2. Rapidly switch event/session and Next, including pending Cards replacements; solve and inspect the saved event/text. No old cross-event or consumed pending target may be reused. FMC must show unavailable, not a substitute puzzle.
3. In both battle modes, hold both, release A then B later, and verify independent start times. Cancel a contact; no stuck green or advancement. Finish A while B runs; only A's scramble changes. Finish B; only B changes. Switch/reset events during idle and test generation failure recovery via reselecting the event.
4. Compare regular/battle haptics and very short taps on iPhone. Verify menus/exit do not start timers. Do not interpret a sub-frame physical tap as a guarantee of a visible display refresh; callbacks have no artificial minimum duration.
5. Trigger PR in Cards/Classic/Split, small/large phones, large text and custom scramble positions. Confirm no collisions; extremely packed configurations may have no legal banner space. Confetti should be identical to the accepted implementation.
6. Edit notes, use keyboard Done, scroll-dismiss (iOS 16+), tap scramble, and close/reopen. Check trimmed notes persist, penalty selection and base time are correct, and Delete still confirms separately. Tap blank parts of every Algorithms overview category.
7. Fresh install with system zh-Hans/zh-Hant/other supported and unsupported languages; choose manual override; change system language; return to Follow System. Verify no stored manual override changes.
8. Verify XW competition location, a normal country, and official-result checkmarks against the signed-in WCA person's results. Change account/log out during a delayed public fetch. Check marks must not leak accounts or be derived from registrations.

Investigation-only: delayed PR/NR incident cause without paired provider snapshots; seven future UX/technical features. Intentionally deferred: dedicated FMC native capability, persistent battle history, full iPad/Mac content, networking/proximity and tab-bar choreography. Existing historical solves were not rewritten; old cross-puzzle records cannot safely be converted after the fact. Simulator audio-service behavior remains an unrelated validation limitation, not declared fixed.
