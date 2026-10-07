# Smart Cube Phase 7/8 Design

Research/design only, 2026-10-05. No production phase-analysis, BLE, Combined, readiness, Replay or move-animation behavior is changed by this document.

## Current Foundation

`SolveReconstruction` version 1 stores puzzle size, initial canonical facelets, ordered moves, relative timestamps, timestamp-source/device-clock/canonical-sequence provenance, completeness/continuity reason and optional Combined timing anchors. `isReplayable` verifies facelet conservation, legal moves and nondecreasing times; equal timestamps are permitted. A replayable trace is not automatically complete or physically accurate at every timestamp.

`SmartCubeReconstructionCapture` owns capture trust; `Solve.reconstructionData` remains the raw record. Replay's raw TPS is gated by complete replayable moves and positive actual duration. `facelets(afterMoveCount:)` replays from the start: calling it for every prefix would be quadratic. Analysis must instead advance one state once per move.

Authoritative canonical history, native device state, physical orientation and visual gyro are distinct. WeiPo 2x2 native tracking is not a license to infer an arbitrary physical six-face frame; 2x2 traces must never receive 3x3 CFOP labels. No gyro stream is needed to falsify or rewrite canonical move truth.

## Eligibility And Output Contract

Inputs: immutable reconstruction bytes, solve ID, actual timing interval, completeness/trust flags, optional user-selected method and frame. Full phase statistics require trusted, complete, replayable canonical 3x3 history. Incomplete traces can expose explicitly partial state observations; they cannot manufacture full phase duration/TPS. Penalty/DNF is separate from completeness.

Proposed derived `SolvePhaseAnalysis` sidecar:

- Raw-data hash, analysis/schema version, metric/frame definitions and input trust summary.
- Candidate method/frame interpretations with reason/confidence, plus optional explicit user confirmation.
- Half-open move ranges, state-boundary evidence, timestamp bounds, skip/AUF policy and uncertainty per segment.
- Move counts, timing intervals, observable pause intervals and total/overhead reconciliation.
- Unknown/ambiguous segments rather than forced CFOP labels.

This is a proposal, not an added persistent entity. Cache by raw reconstruction hash + solve duration + algorithm version + metric definition + selected interpretation. Changing a penalty need not recompute cube states; replacing trace/time/frame must invalidate the appropriate derived result. Never save inferred labels back into raw canonical moves.

## Deterministic State Facts Versus Method Inference

For a chosen canonical frame, evaluate state after each move:

| Fact | Predicate | Boundary policy |
| --- | --- | --- |
| Cross | Four selected-face edges correctly oriented/permuted against adjacent centers | Last completion after the final violation, not the first transient cross. |
| F2L | Cross and four adjacent corner/edge pairs solved | Preserve pair state transitions; do not equate every first pair completion to a sequential F2L slot. |
| OLL | F2L solved and remaining last-layer stickers oriented | May already hold at F2L completion: explicit skip, not an invented algorithm. |
| PLL | Last layer permuted up to the declared AUF equivalence | Record whether final AUF remains. |
| Solved | Exact solved state in the selected normalized frame | Must agree with raw capture's accepted endpoint, not a visual animation completion. |

These predicates are deterministic; calling the solve CFOP is not. Evaluate six cross colors / relevant 24-frame orientations without assuming white cross or physical holding. A stage can be solved then deliberately broken; choose stable completion boundaries and retain violations as evidence. Multi-slotting, pseudo-F2L, ZB/ZBLL, skipped phases and mixed methods can admit several explanations. Prefer the user's selected method; otherwise show candidates conservatively and allow confirmation without mutating history.

For AUF, adopt one versioned policy: either include it in PLL execution or show an explicit final segment, never count its moves/time twice. An initially satisfied phase is zero/skipped only if its predicate remains satisfied to the next boundary. Do not claim the cuber recognized a skip from state alone.

Roux can use deterministic left/right block, CMLL corner and LSE piece predicates in a chosen frame. Inferring that those structures were intentional Roux phases remains heuristic. Do not label a CFOP solve Roux because blocks happen to appear, or force ZZ/Petrus solves into either model. Start Phase 7 with explicit-method CFOP; broaden only with labelled fixtures and honest confidence.

## Time, Move Counts, TPS And Pauses

Recorded event count, HTM and QTM are different quantities; define them separately. Keep current raw TPS unchanged. Slice/wide turns and batched half-turn notation must use a versioned metric rather than silently counting each token alike.

Timestamp boundaries measure observable movement intervals, not thought processes. Device-clock, canonical-local fallback and recovered history have different precision. Equal/batched timestamps are legal; zero-length segments produce unavailable TPS, not infinity. A gap between recorded moves can support a pause observation only with suitable timestamp trust; local delivery bursts or recovered history cannot prove a physical pause.

Recognition versus execution cannot generally be separated from cube state + move times. Report pre-algorithm gaps as observed inactivity, not recognition time or a causal mistake. Thresholds, minimum gaps and noise handling must be explicit/versioned; only infer bursts when timestamp precision supports them.

Combined official total belongs to the external Timer. First-to-last cube movement is a separate interval, with trusted anchors for start/stop overhead. Phase sums plus explicitly unassigned intervals must reconcile to movement time; start/stop delays must not be redistributed into OLL/PLL to make a table total equal official time. Preserve the current Timer-owned lifecycle and official persisted result.

## Replay, Performance And Storage

Compute states/predicates in one background pass, O(N * 54), with cancellation and solve-ID/hash guards. Retain bounded state checkpoints for seek, not every facelet prefix in an unbounded cache. Use a bounded actor-owned derived cache and invalidate on version/raw-data change. Do not run a solver per move or block the Timer/BLE consumer.

Replay phase markers reference canonical move indices and timestamp bounds. Seeking continues to use raw truth; analysis is optional, so a missing/obsolete sidecar cannot prevent Replay. Ambiguous segments display uncertainty, not arbitrary cut points. Persist user method/frame confirmation separately and invalidate only when its raw-data identity changes.

## Implementation Sequence And Gates

1. Pure state predicates and explicit-method CFOP fixtures; no automatic classification.
2. Stable phase boundaries, skip/AUF handling, interval reconciliation and trust-aware metrics.
3. Bounded/cancellable analysis cache and read-only Replay markers in Data.
4. Candidate method/frame scoring, optional confirmation and later Roux support.

Required fixtures: color-neutral frames/regrips; transient cross/F2L completion; repeated or simultaneous pairs; zero OLL/PLL; AUF variants; incomplete/reset/gap traces; equal timestamps; batched fallback times; unknown method; DNF versus complete; Combined delays with trusted/untrusted anchors; cancellation when solve/context changes. Validate state facts against known reconstructions before claiming human method detection. Physical timestamp experiments are needed separately from deterministic state tests.

References for facts/model definitions, not imported implementations: [WCA notation regulations](https://www.worldcubeassociation.org/regulations/#article-12-notation), [cubing.js KPuzzle model](https://github.com/cubing/cubing.js/tree/main/src/cubing/kpuzzle), and the current local raw reconstruction/capture code. No new method classifier is certified by these references.
