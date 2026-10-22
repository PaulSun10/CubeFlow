# Smart Cube Current-State Guidance, Device Card, and Scoped Refinements

## Scope and Evidence

This pass continues the existing dirty worktree. It does not restart the earlier Competition/Results passes. The original brief is the attached `3dd4fe1b-8342-4f0e-b355-e24952ce11eb/pasted-text-1.txt`.

Artifacts: `build/smart-cube-root-oct20/`. `initial.diff`, `initial-status.txt`, `initial-sha256.txt`, and `baseline/` distinguish this goal's changes from the substantial existing work. No commit, push, reset, revert, cache cleanup, signed build, or physical Apple device access was performed.

Physical acceptance is **not claimed**. The user's counted 19-turn failure is accepted as real; its exact packet/solver timeline was not captured, and this report does not invent one.

## A. Root Cause Addressed

### Complete Production Chain

1. `SmartCubePeripheralSession` assigns updated canonical facelets/revision before synchronously emitting its canonical move. Parser/attempt-generation protection remains unchanged.
2. `SmartCubeBluetoothManager` routes only the selected connected session through the existing active feed. Inactive sessions continue tracking separately. Canonical delivery does not depend on a later SwiftUI redraw.
3. `TimerTabView.consumeSmartCubeEvent` consumes the ordered epoch, then `handleSmartCubeMove` passes the verified event state into `handleSmartCubeFacelets` while scrambling.
4. The previous progress matcher could accept a historical checkpoint or a commuting later token. That establishes a valid route, not the quality of the route currently displayed. Timer previously searched only while `isDeviated` remained true.
5. Replan adoption called `epoch.establish(at: .now, ...)`, moving the input timestamp boundary even though the original target had not changed. A pending parser/coalesced move retained an earlier host-receipt timestamp: its newer canonical sequence was consumed, but `observePhysicalMove` rejected it. Replaying history could not recover that already-consumed sequence. The real feed/epoch/scheduler regression fails before the correction, retaining the old route after the final stopped state. This is a demonstrated integration-level event loss, not merely a solver-helper assertion.
6. Previous Timer code cancelled/recreated a search Task on each state. Synchronous native work already running inside the serial solver actor could not be interrupted. There was no explicit trailing-idle/latest-slot owner.
7. The old planner compared a candidate against historical correction plus remaining work and rejected equality. It could choose a valid known path over a long first-solution answer, then reject that same known path because it was not strictly shorter. Thus a completed search could publish **nothing new**. A valid fallback could continue looking final.
8. The old native source-to-target call used a fixed depth 21 and first two-phase solution, not global optimal search. The exact search stopped at HTM depth three.

These are demonstrated source-level defects, not proof of BLE lag. In the recorded solver benchmark, a fixed scrambled target plus the 19-move tail produced 21 moves in unconstrained first-solution mode, versus 18 with a known-route depth bound. That demonstrates why first-solution cost is not an appropriate freshness gate. It does not prove that the user's particular cube state was the benchmark state or that the code contained a literal 19-move threshold.

### Target and Timing Invariants

The original `currentScramble` and target facelets are never replaced by the guidance route. Rebased tokens are presentation/progress from the exact current source to that same original target. Scramble detail/export, solve scramble snapshots, reconstruction start-state ownership, final scramble move exclusion, inspection, and Timer-owned Combined timing remain on their existing paths.

Native WeiPo 2x2 progress remains state-based. No orientation-dependent physical six-face instructions or new decoder mapping were introduced.

## B. Scheduling and Publication

`SmartCubeGuidanceController` is the Timer's retained `StateObject`:

- Guidance rebasing preserves the original `establishedAt` time while retaining the existing baseline-ID, physical-evidence reset, monotonic canonical sequence, and new recovery identity safeguards. It no longer treats publication as the start of a new physical scramble.
- Before adopting a result, Timer drains already committed canonical history and validates against the manager's actual current state. The 3x3 facelet observer also reconciles the current trusted snapshot when a physical event was correctly ineligible for timing; it does not fabricate physical completion evidence or alter the 2x2 observation path.
- A first verified 3x3 snapshot exactly equal to the preserved target now completes directly before historical-progress matching, rather than requesting a zero-move search and waiting for a second observation. A before/after regression establishes this boundary defect.
- A 120 ms trailing-settle interval coalesces rapid **time-adjacent inputs**, not a move-count threshold.
- One search may be in flight and one latest request may be pending. New input invalidates the old publication ticket immediately and replaces the pending request.
- Cancellation does not pretend to terminate a C++ call. The in-flight owner remains until that call returns. Its stale answer is dropped; completion itself drains an already-settled latest request without another physical move.
- New source, target, epoch, generation, cancellation, and remount invalidate old responses. Timer checks actual manager facelets and canonical trust again at adoption, not merely BLE connection status.
- The worker publishes through `@Published publication`; Timer's `.onReceive` validates and rebases the production progress model immediately. SwiftUI does not wait for another move event.
- `SmartCubeScrambleProgress.needsGuidanceSearch` survives a historical checkpoint match or a valid out-of-order commuting move. Normal matching can remain valid while still requiring a fresh search. Following the displayed first move, including a quarter of a displayed half turn, does not spuriously invalidate it.
- Authoritative continuity boundaries and remounts also reschedule when this flag remains set, including a valid historical checkpoint. Completion clears it through existing target verification.
- A verified current-state result can publish even if equal in length to the fallback. Legacy strict-improvement APIs remain for their existing callers/tests; Timer no longer uses equality as a freshness gate.
- The best validated current route is selected from the solver answer and a replay-verified simplified known route. Malformed/failed native output cannot displace a valid known route merely because an error string has fewer tokens.
- Valid fallback corrections remain visible while searching. A quiet localized Updating Guidance indicator is shown. Exhaustion/failure has a concise unavailable state and preserves any verified fallback, rather than pretending it is still searching or claiming optimality.
- DEBUG emits scheduled/started/discarded/published/unavailable marks with epoch/version/generation through the existing bounded 2,048-entry diagnostic ring. No new packet dump or unbounded diagnostics store was added.

### Search Strategy

1. Exact HTM source-to-target search through three moves, off the main actor.
2. Longer 3x3 paths use the existing Min2Phase actor and existing 1,000,000-probe primary ceiling, with depth capped by a validated known route when available (and by 21).
3. A second strictly smaller depth bound gets a 10,000-probe improvement attempt. It replaces the first candidate only when valid and shorter.
4. Every adopted token sequence is replayed from its exact source and must end at the exact preserved target. An invalid candidate, stale answer, untrusted state, or ineligible timing state cannot be adopted.

A failed bounded search is not a proof that no shorter solution exists. A valid historical route remains an upper bound, not an optimality certificate.

## C. Solver Audit

### Existing Inventory

| Engine | Role and supported state | Isolation / limitations |
| --- | --- | --- |
| TNoodle native bridge | Official Timer scramble generation: 2-7 cubes, BLD variants, FMC, Pyraminx, Square-1, Megaminx, Clock, Skewb; 15 embedded registry entries | Existing serial generation queue, lock, Graal isolate/native dynamic library. Simulator branch explicitly returns unavailable. Exposed API produces scrambles, not arbitrary current-2x2-to-target guidance. |
| Min2Phase C++ bridge | 54-facelet 3x3 solve and arbitrary same-frame source-to-target relative cubie transformation | Tables initialized once; full cubie validity checked by the bridge. Existing synchronous native calls isolated from MainActor. First two-phase solution is not globally shortest. |
| `SmartCubeTargetPath` | Exact source-to-target paths through 3 HTM, 24 or 54 facelets in a known canonical frame | 1-forward/2-backward exhaustive meet-in-the-middle; cancellation checks; no native actor wait for its own computation. A 2x2 mathematical path does not establish WeiPo physical face orientation. |
| Recovery engine | Verified inverse trails, checkpoints, boundary normalization and simplification | A valid executable upper bound; not a shortest-path solver. |
| FTO engine | Existing JavaScriptCore random-state scrambling plus notation/state interpretation | Two generation engines/pool and separate state interpreter queue; no arbitrary Smart Cube guidance API. Unchanged. |
| Fast 4x4 generator | Existing 40-move axis-filtered random-move scrambling | Not random-state solving or an optimal solver. Unchanged. |
| Square-1 canonical/CSP utilities and diagram engines | Existing state application/counting/recognition/curated or generated case infrastructure | Not used as a general source-to-target Smart Cube solver; no new integration or taxonomy changes here. |

The new bridge overload exposes depth, probe limits/minimum, and the existing `OPTIMAL_SOLUTION` flag. Old bridge callers still delegate with their original parameters. Primary ordinary scramble generation and `solveFacelets` behavior are unchanged.

The integrated `Search.cpp` really branches to `searchOpt()` when that flag is present and deepens from zero. The audit exercises it at bound five and replays every answer. Arbitrary deep global-optimal search is **not enabled** in production: phase-one work between probe checks is not a hard wall-clock deadline, and deep exact search can grow dramatically. Task cancellation remains cooperative around, not inside, a native call.

Host-side `sizeof` against the integrated headers: `coords_t = 991,712 bytes`, `Search = 2,224 bytes`. This is static type storage on arm64 macOS, not peak iPhone RSS or a promise about every transient allocation. The short-path dictionaries and all worker results are per request; the scheduler retains one latest slot, not an accumulating solve cache.

### Representative Measurements

Simulator tests on this Mac; times are not physical-iPhone performance guarantees. Fixed target: `R U F L D B R2 U2 F2`. Input tails are 1, 2, 3, 5, and 19 moves; these are known upper bounds, not a claim that each arbitrary tail has that optimal distance.

| Input tail length | Default first / known-bound native output | Production hybrid output | Latest warm hybrid elapsed |
| --- | --- | --- | --- |
| 1 | 1 / 1 | 1, exact through three | 0.73 ms |
| 2 | 2 / 2 | 2, exact through three | 2.66 ms |
| 3 | 3 / 3 | 3, exact through three | 21.43 ms |
| 5 | 5 / 5 | 5, validated upper bound | 22.29 ms |
| 19 | 21 / 18 | 18, validated upper bound | 487.62 ms |

Cold native initialization plus the first one-move native solve was about 116 ms in `solver-audit-v1`. The latest 19-input lifecycle run, starting one HTM from target and then stopping completely, published **one** latest-state answer about **662 ms after the final input**, including the 120 ms coalescing interval and bounded improvement. Earlier overlapping runs measured approximately 669-701 ms. Gated in-flight tests prove that no extra physical input is needed when an old worker completes; cancellation/remount/new-target and settle-boundary races are deterministic, not inferred from stopwatch measurements.

These samples are neither exhaustive worst-case timing nor global-optimality proofs for long states. The independent short-search proof and shallower-path checks cover the claimed <=3 HTM guarantee only.

### cubing/twips: Actual Upstream Review

Pinned source: `a9d702a2a3edfea7ddec001c8e1d037214705903` (workspace version `0.12.5-dev`). The reviewed source copies are diagnostic artifacts under `upstream/`, **not vendored application code or a new dependency**.

- It is a general permutation/KPuzzle search library, not merely a 3x3 scrambler. Its experimental `search` API accepts a source `KPattern` and an explicit `target_pattern`. A correct CubeFlow pattern/frame adapter would still be required. [Search API](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/src/lib/experimental_lib_api/search_api.rs).
- `Hand` enumerates nontrivial powers of a generator at unit cost; `Quantum` uses forward/inverse unit powers. With the six ordinary 3x3 face generators these correspond to HTM and QTM respectively. Arbitrary generators change what the metric means. [Generator construction](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/src/lib/_internal/canonical_fsm/search_generators.rs), [metric definition](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/src/lib/_internal/notation/metric.rs).
- Its iterative deepening can establish a shortest first answer only when all lower depths in the intended generator/metric space are exhausted, with no skipped minimum depth, restrictive masks/FSM constraints, continuation gap, or prematurely terminated search. A restricted subgroup optimum is not the unrestricted cube optimum. Its multi-phase first-answer chaining does not establish a global optimum across phases. [Iterative search](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/src/lib/_internal/search/iterative_deepening/iterative_deepening_search.rs), [multi-phase chaining](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/src/lib/experimental_lib_api/multi_phase_search.rs).
- Search is pull-based. Continuation can resume enumeration, but `.next()` may block inside deep recursion. The inspected request options expose depth/solution/FSM controls, not an application cancellation token or hard deadline. A production iOS wrapper would need explicit cooperative cancellation/resource policy and stale-result validation. [Individual search](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/src/lib/_internal/search/iterative_deepening/individual_search.rs).
- Prune tables trade memory for search work and can be reused for a compatible puzzle/generator/metric/target scope. The hash table starts at `1 << 20` byte-depth entries; the default maximum is absent. That is not total/peak memory and must not be treated as a mobile memory cap. Changing the target requires correct table ownership. [Prune table](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/src/lib/_internal/search/hash_prune_table.rs).
- The event enumeration includes all official WCA events and some unofficial puzzles. Scrambler strategies/status differ by puzzle; the README's minimum-distance scramble checks are not promises that generated scrambles are globally shortest solutions. [Event source](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/src/lib/scramble/event.rs), [upstream overview](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/README.md).
- Rust supports iOS/device and simulator targets, so an XCFramework/C ABI integration is technically plausible. The existing twips FFI is a `cdylib` exposing scramble generation/derivation and scramble-finder cache release, **not** the general state-search API. Its returned C strings currently have an explicit leak/free TODO. A static-library/search-handle/free/cancellation shim, build reproducibility, allocator ownership, panic handling, per-search concurrency and frame validation would be required. No such integration was built here. [FFI implementation](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/src/ffi/lib.rs), [FFI manifest](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/src/ffi/Cargo.toml), [Rust iOS targets](https://doc.rust-lang.org/rustc/platform-support/apple-ios.html).
- The upstream README offers MPL-2.0 OR GPL-3.0-or-later; workspace crates declare MPL-2.0. It is not MIT. An MPL distribution path still requires preserving notices and making covered source/modifications available under that license; it is not permission to silently copy code into proprietary files without obligations. Transitive licenses would need a release audit. [Manifest](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/Cargo.toml), [MPL text](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/LICENSE-MPL.md).

No Rust toolchain was available on PATH. Binary size, iOS peak RSS, end-to-end timings, concurrency safety and older-iOS deployment behavior of a twips integration were therefore **not measured**. No faster-than-Min2Phase or universal mobile-optimality claim is justified. The integrated Min2Phase vendor README itself contains both GPLv3 and MIT sections while C++ files retain separate copyright notices; this pass does not silently resolve that existing provenance/distribution question or import additional GPL code.

**Recommendation:** keep the verified short-search + bounded Min2Phase hybrid for this fix. Evaluate twips separately only with the required adapter/FFI/resource/license work and same-state device benchmarks. It may meaningfully broaden generic puzzles or explicit optimal search, but cannot repair the application scheduler, stale-result publication, or an unknown physical 2x2 reference frame by itself.

## D. Smart Cube Management Card

- Reuses `CompetitionNativePresentation(.results)`, its dimmer, native present/dismiss ownership, Reduce Motion behavior, and card-motion environment. The former inline Results surface, close control, width/height and shadow constants are extracted **without changing their values** and used by both cards.
- Shared geometry: width `min(max(windowWidth - 32, 280), 430)`, height ceiling `min(max(windowHeight - 64, 180), 680)`, 14 pt continuous corners, secondary-system background, separator stroke 0.5 pt at 0.55 opacity, black shadow 0.24/radius 24/y 10. Existing native fade/scale transitions remain unchanged.
- The card wraps normal content, using vertical scrolling only for actual overflow. An iOS 15 compatible measured branch follows Results' natural-content/overflow convention. A regression catches the initial over-large 680 pt card and verifies oversized content remains reachable by scrolling.
- Timer's virtual cube tap and name button open the same card when a known device exists. With no saved/connected device, the name retains the original connection/discovery link instead of presenting an empty card. The renderer's existing one-touch pan is unchanged; the optional tap waits for pan failure and is disabled during timing/inspection/result popup states. No new Reset shortcut was added outside the card.
- Device selection is a small existing-style name Menu over connected and saved devices. It changes only card selection, never `selectActiveDevice`. The Timer's separate existing Active Device menu remains explicit and unchanged.
- Connected content directly observes the selected `SmartCubePeripheralSession`, including inactive sessions. Its existing canonical event stream, trusted state, revision, actual puzzle size and renderer are reused. WeiPo 2x2 uses the existing native visual facelets/revision path. There is no independent cube-state model.
- Unknown live state shows progress instead of a fabricated solved cube. Disconnected saved devices show only a neutral placeholder/name, no stale percentage or claim of live updates; Reset/Disconnect are disabled.
- Reset is one prominent tap, no confirmation, and leaves the card open. It delegates to existing reset/recalibration. Manager routing now strictly matches an explicitly supplied attempt and device; a stale attempt can no longer fall back to a different/new active connection. Existing parser-generation/reset-identity checks remain. Transient move-history clearing is existing recalibration behavior; historical solves/statistics are not accessed.
- Disconnect affects only the selected session and retains the saved association. Active reassignment uses the existing current/remembered/sole-compatible rules.
- Forget requires destructive confirmation, disconnects only the selected device, clears its saved alias/auto-connect/color/transport metadata and matching last-active preferences, removes session subscriptions/gyro observation and peripheral metadata, and preserves historical data.
- A retiring-peripheral gate blocks late connect restoration and reuse until a terminal disconnect/failure callback (or radio teardown). Manual-disconnect state continues rejecting late callbacks afterward. Restore requires a saved association. Fresh rediscovery plus explicit connection can create a new association; forgotten transport metadata alone cannot. No system-pairing API is claimed.

Mounted screenshots verified compact card shape/controls and a native SceneKit snapshot with **8 cubies / 24 facelets** for the selected inactive 2x2. UIKit `drawHierarchy` omits the Metal-rendered cube layer; the separate `SCNView.snapshot()` is retained and inspected rather than treating that empty raster area as a successful 3D screenshot.

## E. Timer Identity Insets

Only the compact Timer Smart Cube row receives symmetric horizontal padding `min(12, identityWidth * 0.06)`. The left name moves inward from the leading edge and the right percentage from the trailing edge. `Spacer(minLength: 4)`, name font, prominent percentage-only battery font, active selector, cube anchor, and natural vertical sizing remain unchanged. This is padding inside the existing row, not a centered combined group or a positional offset.

Classic and Cards share `smartCubeCenterComposition`; no separate layout fork or change to ordinary Timer geometry was added. Existing identity/battery sizing regressions cover normal and large text; full physical layout acceptance remains listed below.

## F. Explore Region: Measured Limits

Only `explore.in_region` uses this packing path. Coming Up and other wrapping event lists, glyph-centering, per-glyph offsets, card size/height, data and navigation are unchanged.

Actual region cards are fixed at 280 pt normally, 310 pt for accessibility, with 16 pt surface padding per side. Consequently narrow/standard/wide iPhones (320/393/440 pt screen fixtures) all provide **248 pt** normal content width, or **278 pt** accessibility content width. A wider phone does not silently enlarge these fixed cards.

The real font at standard size has 18 pt advances for all 17 official glyphs. Measured ink widths are 14.625-18 pt (Pyraminx reaches 18); 666/777/Minx reach 16.3125. There is no horizontal overhang outside the chosen complete cells. Font scaling produces 24 pt cells at XXXL and 40 pt in the tested accessibility category. Full per-event ink bounds and all configurations are in `[RegionInk]` / `[RegionPacking]` test output.

| Text category / available | Events | Max gap that permits all icons | Result |
| --- | ---: | ---: | --- |
| Standard / 248 | 8 | 14.86 pt | All 8; keep existing 6 pt gap |
| Standard / 248 | 13 | 1.17 pt | All 13; adapt gap to 1.17 pt, no +N |
| Standard / 248 | 17 | -3.63 pt | Cannot fit even at zero gap; show 12 +5, 1.25 pt gap |
| XXXL / 248 | 8 | 8 pt | All 8; keep 6 pt gap |
| XXXL / 248 | 13 / 17 | -5.33 / -10 pt | 9 +4 / +8; about 1.11 pt gap |
| Accessibility / 278 | 8 / 13 / 17 | -6 / -20.17 / -25.13 pt | 5 +3 / +8 / +12; 6 / 6 / 4.4 pt gaps |

Packing considers the complete list before hiding anything, reduces gap from 6 pt to a 1 pt minimum when necessary, then reserves the exact measured +N width and chooses the largest complete prefix. It never shrinks icons, overlaps/clips glyphs, adds a second row, fades, or introduces horizontal scrolling. The one-row height remains text-metric-based. Icons are decorative inside the existing competition navigation target; VoiceOver continues to receive all localized event names, including visually hidden ones. At 17 standard icons the cells alone require **306 pt**, so hiding none would require changing size or presentation, which was not approved.

## G. Saved-Information Notice

Two independent owners were exposing cache state:

1. `PublishedCompetitionRecordEnrichment` marked an expired cached profile as saved/offline evidence before any refresh had failed.
2. The published Results footer used `publishedStore.isStale`, also true during normal stale-while-revalidate.

Cached profile evidence still installs immediately, but age/cache hit no longer marks failure. Only a real non-cancellation refresh error with usable saved flags adds the fallback notice; successful cache reuse/load clears it. The Results footer now requires actual `failed` plus saved data, not age alone. The wording does not assert offline merely because the request failed.

PR joins, single/average separation, canonical ownership, regional discovery, own selector propagation, bounded profile loading, retained parent ownership, cancelled-merge recovery and fresh negative retractions remain unchanged. Relevant mounted/selector/cache tests pass.

## H. Verification

All runs use the single explicit simulator destination, never a physical device. No broad UI suite was run.

- `solver-audit-v1`: 1 native solver benchmark test passed.
- Initial lifecycle simulator compilation exposed a MainActor default-argument initializer and a wrong test font-style member; fixed in the fixture. These were compile failures, not passing tests.
- `guidance-layout-notice-v3`: 38 XCTest + 36 Swift Testing passed.
- `management-presentation-v1`: 34 XCTest + 8 Swift Testing passed, including 20 existing native presentation/Back boundaries and 7 All Results table regressions.
- A later optional-tap ternary exposed a Swift beta diagnostic-generation failure in Timer's large view expression. A typed optional callback property resolved it without compiler-setting changes.
- The first gesture assertion counted SCNView's own camera pan as the application's pan. The corrected assertion identifies the existing CubeFlow one-touch owner, rather than removing native recognizers to satisfy the test.
- `focused-final`: 49 XCTest + 52 Swift Testing passed, zero failures. Covers the real planner/scheduler/renderer chain, 19-input stop, inverses, historical checkpoints, in-flight/settle-boundary/new-target/remount races, device actions, PR/cache and event packing.
- `fit-and-bridge-final`: 10 XCTest passed after the final small card-fit/bridge argument-clamping updates.
- `card-overflow-check`: 1 additional production-fit regression passed; oversized content has a real native vertical ScrollView and valid content extent.
- `latest-guidance-final`: 19 XCTest passed after retaining the existing primary probe ceiling, explicit canonical trust at adoption and fallback-state handling.
- Final audit added two genuine boundary regressions: the first exact-target snapshot failed before correction (one test/five assertions); delayed canonical delivery across replan publication failed before correction (one test/four assertions). No assertion was weakened to make either pass.
- `target-boundary-after`: 18 XCTest + 36 Swift Testing passed after the exact-target check.
- `management-entry-final`: all 10 management tests passed, including the no-known-device entry regression.
- `canonical-guidance-final`: 19 XCTest + 53 Swift Testing passed with the actual canonical feed/epoch in the lifecycle harness, including delayed pre-publication receipt/post-publication delivery, and unchanged Smart Device integration/readiness/discovery regressions.

These overlapping runs cover **141 distinct tests**, not the sum of reruns: 80 XCTest plus 61 Swift Testing. The XCTest method union is recorded in `passing-xctest-methods.txt`. Non-fatal existing beta toolbar/actor/deprecation and simulator CoreBluetooth XPC messages remain in logs; simulator XPC messages are not physical BLE verification.

`git diff --check`: passed. An initial-hash audit confirms 22 frozen Filter/Top Cubers/scroll-owner/WCA Live/modern Cubing Live/Combined lifecycle files remain byte-identical for this goal. Whole worktree remains dirty with all previous accepted changes preserved.

Unsigned generic iOS Debug builds `final-unsigned-generic-debug.log` and `final-current-source-debug.log` passed at their recorded source stages. The first predates the final audit's target/epoch corrections; the second includes those corrections. The final verification build after the no-known-device entry guard **passed** in `final-verified-source-debug.log`. Earlier successes are not substituted for verification of later source. All use `CODE_SIGNING_ALLOWED=NO`; no physical or signed build was performed.

## I. Remaining Limits and Manual Acceptance

- The precise user's uncaptured 19-move hardware trace is not reconstructed. The scheduling/quality/publication defects are fixed and tested; this is not a physical acceptance claim.
- Only paths returned by the exhaustive <=3 HTM search are explicitly certified shortest. Longer answers are verified upper bounds. One native call cannot be interrupted mid-recursion; latest-state invalidation and automatic handoff prevent stale publication but do not impose a strict millisecond deadline on that call.
- twips iOS binary/peak-memory/latency and distribution integration remain unbuilt and unmeasured; it was not imported.
- Native BLE reconnect/reset/late-callback timing, device-firmware recalibration and minimum-OS runtime behavior still require physical/older-OS acceptance. DEBUG fixtures simulate session state and action ownership, not a BLE radio or firmware.
- Filter's native rapid-reopen latency remains unresolved and completely out of scope. Its production behavior and diagnostic instrumentation were preserved.

### Exact Physical iPhone Checklist

1. Use a trusted 3x3 Smart Cube and an original target scramble. Follow until one HTM move remains. Make one wrong turn, then stop completely. Updating should settle into a verified current-state route **without another turn**. Follow it to the same original target.
2. Also try turning during the Updating indicator, with a final turn just before the route appears. A pending/coalesced turn must not disappear merely because its receipt timestamp preceded publication. Repeat with a wrong turn/inverse, repeated same-face turns, and 19 arbitrary turns. Record the last physical-turn and visible publication times. Rapid input must not cause a later stale path to overwrite the last state's guidance.
3. While a longer search is running, make another short stream and stop. Repeat leaving/returning to Timer and changing the target. Verify no old epoch/source/target result appears. Reset during a search; pre-reset guidance must not return.
4. Tap the virtual cube and name area in Classic and Cards. Both open the same compact card. Dragging the virtual cube still rotates it; active timing/inspection/result popup must not open the card. Check large Dynamic Type, light/dark, outside-tap/Close and Reduce Motion.
5. With two connected devices, leave A Active and view B in the card. Turn B: its correct-size cube must update; Timer remains A. View a 2x2 and a 3x3. No protocol/BLE IDs, rename, redundant Connected/Active fields or fake offline live state should appear.
6. On each supported connected device, tap Reset once. No confirmation; card stays open; connection stays. Confirm solved tracked state after the existing authoritative recalibration, then make physical turns and verify tracking. Historical solves/statistics must be unchanged. In particular exercise GAN and WeiPo's existing local-reference reset separately.
7. Disconnect selected inactive B: A keeps tracking and B stays saved. Reconnect B by the existing model. Forget B with confirmation, including while connecting; no late callback/auto-reconnect should re-add it. Rediscover and explicitly connect again to create a fresh association. Forget Active A and verify the existing compatible-device reassignment rule, without touching other sessions/history.
8. Open a 13-event region card at default type: all icons should fit at the tighter gap. Inspect 17 events and accessibility sizes: safe +N, no half icons, overlap, extra row or changed height. VoiceOver should announce all event names.
9. Open the physically accepted CubingChina published PR case. Normal cached/online viewing must be quiet, and own row/event/round PR still automatic. Exercise genuine failed refresh with saved evidence, then successful recovery; only the real fallback can show the concise saved-data notice, and recovery clears it.

## J. Task-Delta Files and Worktree

Existing files changed during this goal (against initial file hashes, not all pre-existing Git changes):

- `CubeFlow/Min2PhaseBridge.h`, `CubeFlow/Min2PhaseBridge.mm`
- `CubeFlow/Views/Shared/SmartCubeExperience.swift`
- `CubeFlow/Views/Shared/SmartCubeReplacement.swift`
- `CubeFlow/Views/Shared/SmartCubeBluetoothManager.swift`
- `CubeFlow/Views/Shared/SmartCubePeripheralSession.swift` (DEBUG fixture hook only)
- `CubeFlow/Views/Shared/SavedSmartCubeDevices.swift`
- `CubeFlow/Views/Shared/PublishedCompetitionRecordEnrichment.swift`
- `CubeFlow/Views/iPhone/TimerTabView.swift`
- `CubeFlow/Views/iPhone/SmartCubeScrambleProgressView.swift`
- `CubeFlow/Views/iPhone/SmartCube3DView.swift` (optional management tap; animation/gyro code unchanged)
- `CubeFlow/Views/iPhone/ConnectedDevicesView.swift`
- `CubeFlow/Views/iPhone/CompetitionNativePresentation.swift` (shared unchanged card primitives)
- `CubeFlow/Views/iPhone/CompetitionTabView.swift` (shared primitives and Results fallback-notice condition only)
- `CubeFlow/Views/iPhone/Explore/ExploreCompetitionEventStrip.swift`
- `CubeFlow/en.lproj/Localizable.strings`, `CubeFlow/zh-Hans.lproj/Localizable.strings`, `CubeFlow/zh-Hant.lproj/Localizable.strings`
- `CubeFlowTests/PublishedCompetitionPRTests.swift`
- `CubeFlowTests/SmartCubeCurrentStateGuidanceTests.swift`

New files for this goal:

- `CubeFlow/Views/Shared/SmartCubeGuidanceController.swift`
- `CubeFlow/Views/iPhone/SmartCubeManagementCard.swift`
- `CubeFlowTests/SmartCubeGuidanceLifecycleTests.swift`
- `CubeFlowTests/SmartCubeManagementTests.swift`
- `CubeFlowTests/SmartCubeSolverAuditTests.swift`
- `CubeFlowTests/ExploreRegionPackingTests.swift`
- This report and diagnostic/build artifacts under `build/smart-cube-root-oct20/`.

`project.pbxproj` was not edited. No unrelated Explore, Rankings, Records, protocol mapping, Combined readiness, Timer persistence, Top Cubers, Filter, result navigation or scroll-physics implementation was rewritten.
