# CubeFlow Roadmap

This roadmap ranks unfinished work by user value, urgency, dependencies, and implementation risk. Priorities should be revisited after each release.

## P0 - Competition Day

### My Competition Dashboard

**Why it matters:** At a competition, the highest-frequency task is checking the next assignment and the latest result. Requiring repeated navigation between the WCA site, WCA Live, and Competition Groups is slow and error-prone when the user is preparing to compete or staff.

**Product direction:** Add a competition-day dashboard to My Competitions and make it the fastest route from the Competitions tab.

- Identify the signed-in competitor with the WCA profile `wcaId`.
- Load the selected competition's public WCIF and match the user's assignments.
- Show the next assignment first: event, round, group, role, station, room, start time, and end time.
- Show today's complete personal schedule, including competitor, judge, scrambler, runner, and other assignment codes.
- Show live personal results from WCA Live when the competition is available there.
- Refresh on foreground entry and with pull-to-refresh; retain the last successful snapshot for poor venue connectivity.
- Keep links to Competition Groups, WCA Live, and the official competition page as fallbacks.
- Clearly label scheduled data as provisional and show its last refresh time.

**Data strategy:** Competition Groups documents that it presents assignments stored in WCIF. CubeFlow should consume WCA WCIF directly rather than scrape or depend on Competition Groups' UI.

**First release completion criteria:** A signed-in user can open an upcoming or active competition and see their next group and latest result without leaving CubeFlow.

## P1 - Reliability And Release Readiness

### Data Tab Navigation Stability

**Why it matters:** Time, Average, and Record are core daily surfaces. A toolbar segmented control that shifts, clips, or becomes unreliable makes the main solve history feel broken.

- Replace geometry-derived toolbar sizing where a stable native layout is possible.
- Verify Time, Average, and Record in every supported language and Dynamic Type size.
- Verify selection mode, graph actions, rotation, sheets, and iOS 26/27 navigation transitions.
- Add a focused regression checklist before release.

### iOS 26+ Horizontal Selector Liquid Glass Unification

**Why it matters:** CubeFlow currently has several independently styled horizontal capsule selectors. On iOS 26 and later, these should follow the same native Liquid Glass language instead of mixing custom fills, materials, and simulated edge blur.

**Status:** Implemented. Horizontal peer selectors now share one availability-aware style: native Liquid Glass on iOS 26+, with their existing appearance retained on earlier systems.

**Product direction:**

- Introduce one shared horizontal selector component/style that owns availability checks, shape, spacing, selection state, animation, and feedback.
- On iOS 26 and later, use native SwiftUI Liquid Glass APIs, including `GlassEffectContainer`, interactive glass, native glass button styles where appropriate, and system-supported morphing rather than custom blur or material simulation.
- On earlier iOS versions, preserve the existing selector appearance and behavior. Do not spend additional time polishing the custom Competitors separator-edge blur solely for the fallback.
- Do not apply glass indiscriminately to read-only badges, status tags, table headers, date tabs, or horizontal data tables. This task is limited to interactive capsule/segmented selection controls.
- Verify light/dark appearance, Reduce Transparency, Dynamic Type, localization width, VoiceOver, selection feedback, rapid switching, and horizontal scrolling before replacing existing styles.

**Initial audit scope:**

- `AlgTabView`: all three hybrid subset selector contexts currently using duplicated `hybridSubsetPicker` / `hybridSubsetCapsule` implementations.
- `WCAMyResultsView`: the horizontal event selector in Results.
- `CompetitionTabView`: `CompetitionDetailTabStrip`, the Competitors event selector, and the Cubing China schedule event selector.
- Native segmented controls with custom surrounding surfaces in `DataTabView`, `CompetitionTabView`, and `AlgTabView`: confirm whether the system already supplies the correct iOS 26 Glass treatment and remove conflicting custom chrome rather than wrapping Glass twice.
- `TimerLocalBattleView`: audit event and handicap selectors for inclusion if they function as peer capsule choices rather than menus.

**Completion criteria:** Every interactive horizontal capsule selector uses the shared abstraction; iOS 26+ receives native system Glass without custom blur/tint simulation, earlier systems retain their current fallback, and no page contains a one-off availability branch for the same selector pattern.

### Performance And Energy Follow-up

**Why it matters:** Previous hangs were reduced substantially, but sustained High Energy Impact still affects battery life and confidence during competitions.

- Re-profile tab switching and idle behavior on device.
- Eliminate remaining repeated main-thread view recomputation.
- Confirm no Core Data context is retained or disposed from the wrong executor.
- Set measurable idle CPU and tab-switch latency targets.

### Competition Data Resilience

**Why it matters:** Competition pages combine WCA, WCA Live, and regional sources that may be slow or temporarily unavailable at a venue.

- Standardize cache age, refresh, stale-data, and offline states.
- Preserve the last successful competition-day snapshot.
- Surface source-specific errors instead of generic empty content.
- Detect loss of connectivity before starting uncached requests and show an explicit offline state instead of an indefinite loading indicator.
- Keep cached competition pages usable offline, label stale content clearly, and provide a native retry action when connectivity returns.

## P2 - Smart Cube Usability

### Project State (2026-09-05)

- **Phase 0: complete.** Existing afedotov-based GAN/MoYu BLE protocol foundation, packet/history recovery, normalization into canonical moves/state, Virtual Cube tracking, and Bluetooth Timer support. Do not rebuild discovery or protocol detection.
- **Phase 1: complete.** State-based scramble progress; completion enters Ready/Inspection, and the next physical move starts timing. The final scramble move is excluded. Physical solved state completes and automatically saves the solve. Manual Entry remains independent. Collapse/Trail transitions and URF orientation are physically validated; freeze URF.
- **Phase 1.5: complete.** Consumer Device Identity is layered above protocol detection. Preserve verified GAN mappings and honest generic MoYu identity when model discrimination is unreliable. Current Move Highlight follows the authoritative verifier token index; preserve its validated customization.
- **Phase 2A: complete; physically validated checkpoint.** Canonical deviation trail inversion guarantees immediate Recovery; same-axis/opposite-face simplification reduces it. Bounded BFS is an optional <=3 HTM shortcut, not the recoverable-deviation limit. It runs off MainActor with cancellation and epoch/version/source-state checks. Ordered move-plus-corresponding-facelet publication preserves rapid turns. Genuine continuity breaks invalidate the old trail and abort an affected unsaved solve; normal packet-history waiting is not a break. Reset/resync snapshots never count as finishing moves. Only Separate and Inline remain; legacy Focus migrates to Inline. Separate wraps without widening the Timer root. Ready Sound prepares audio off-main. DEBUG diagnostics are implemented.
- **Phase 2A.1: complete; passed physical validation.** GAN Gen3/Gen4 history recovery scheduling and H-perm/M-slice recognition latency. Do not begin Phase 2B or change normal timing/coalescing based on speculation.

### Layering And Ownership

Earlier hardware notes recorded working protocol paths for GAN 16 UI, GAN 12 UI Maglev, GAN i4 Maglev, MoYu V10 AI, V11 AI and Super WeiLong V2 AI. This is protocol compatibility evidence, not permission to infer an exact consumer model from a generic advertisement. The 3D palette follows the existing csTimer reference; gyro-driven presentation and perfect M/E/S notation remain deferred.

BLE packet -> existing packet-loss/history recovery -> device normalization -> ordered canonical move/state with timestamp provenance -> scramble verification / solve lifecycle / later analysis.

Upper verification/Recovery must not know device-specific packet quirks. Trustworthy current facelets are distinct from trustworthy continuous history. Facelets remain the 3D rendering truth; do not reintroduce an animation queue that loses rapid publications. Keep diffuse/emission and existing palette behavior. TimerTabView currently orchestrates the session; avoid a parallel owner/state machine. Revisit a single owner only if Phase 2B requires correctness across view lifetimes.

### Phase 2A.1 Evidence And Implementation

User-supplied physical diagnostics: normal BLE-to-parser work is sub-millisecond, parser-to-main about 10-15 ms, protocol-to-canonical about 3-13 ms, and upper consumption/recognition effectively immediate. Normal device-clock solves showed stored == local first-to-last == device first-to-last, difference zero. An extreme H-perm showed approximately 3600 ms recognition latency with repeated history request/receive cycles; coalescing was disabled. Recovered history lacked device timestamps and used reconstructed/canonical-local fallback. These observations do not prove reconstructed absolute timing accuracy.

Local source inspection corrected the initial delay hypothesis: requests were already immediate. The 0.65 s hold only extends the optional coalescer's pending-move flush, and does nothing when coalescing is disabled. The old DEBUG `history.wait` label was misleading. Actual recovery liveness weaknesses were response-side draining with further requests disabled, head-adjacent-only history acceptance, and no idle lost-response retry.

Current change: Gen3/Gen4 share requested-range/deduplicated history backfill, modular ordered draining, immediate next-gap requests after a response, normalized-window throttling, and up to six requests per unresolved window with a single 0.3 s idle retry callback. This interval is a lost-response retry, never a pre-request hold. Progress reopens the budget. Reset/connection generation changes invalidate queued application/retry results. Existing buffer-loss continuity notification and timestamp provenance remain. No normal timing or slice behavior was changed.

Reference inspected: [current csTimer GAN source](https://github.com/cs0x7f/cstimer/blob/master/src/js/hardware/gancube.js), architecture only; no GPL implementation copied. It also requests live gaps immediately, uses idle state checking separately, and calls response-side eviction without requesting more history. CubeFlow deliberately makes response-side progress self-driving rather than copying that liveness dependency.

Limits: history responses carry only low-byte counters, no request/generation identifier or original device timestamps. Current-generation requested-range checks reject unsolicited, completed and out-of-window responses, but cannot prove the age of a delayed wire packet that exactly aliases a newly requested counter window. Half-range modular ordering assumes fewer than 128 unresolved counter steps. Bounded retry exhaustion preserves the unresolved gap; it does not invent continuity or a finishing move. The targeted multi-second recognition regression did not reproduce in the physical tests recorded below; this does not rule out all possible GAN history-recovery stalls.

Physical validation reported by the user at checkpoint closeout:

- Several normal device solves used `deviceClock`, with `stored_minus_move_s = 0` and stored == local first-to-last == device first-to-last.
- One H-perm solve and a stress solve containing roughly five H-perms completed without perceptible solved-recognition stalls. Rapid Recovery remained functionally correct.
- The heavier solve recorded `history.gap=104`, `history.gapRequest=48`, `history.request=52`, `history.received=45`, `history.backfill=42`, `history.retry=4`, and `canonical.publish=153`; `recognition_after_canonical_ms` was approximately -41 ms.
- Another H-perm-heavy solve had 35 gaps and 17 requests, with approximately +64 ms recognition-after-canonical. No `retryExhausted` was observed; `history.coalescingHold` remained `applied=false`. Observed timing provenance remained `deviceClock`, with matching stored/local/device intervals.
- Compared with the earlier approximately +3600 ms pathological case, the targeted regression did not reproduce under substantially heavier history-recovery stress. The negative estimate is not negative physical latency: canonical timestamps are clock estimates, not an independent physical reference. Retain the protocol/timestamp limitations above.

For future regressions, collect `[SCDEBUG] START`, `FINISH`, `DISPLAY`, `TIMING`, `PIPELINE`, `GAP`, and `STAGE` for a normal solve and a solve ending in H-perm with the same device/settings. New stages: `history.gap`, `gapRequest`, `retry`, `retryExhausted`, `received`, `backfill`, `drain`, and `coalescingHold` (requested versus actually applied). Compare recognition latency, stored-minus-move interval and timestamp source; canonical timestamp latency is not an independently measured physical-turn latency.

### Subsequent Phases (Not Implemented Here)

1. **Phase 2B, after 2A.1 validation/checkpoint:** compare Recovery correction cost plus remaining original scramble workload with replacement scramble workload from current state; use hysteresis to avoid oscillation. No full solver/Replan in 2A.1.
2. **Phase 3:** real Virtual Cube layer-turn animation and polish, without sacrificing facelet truth.
3. **Phase 4:** simultaneous Smart Cube + Bluetooth Timer. External timer supplies official total; cube first-to-last interval measures start/stop overhead.
4. **Phase 5:** Smart 2x2/additional hardware, prioritizing the user's MoYu smart 2x2.
5. **Phase 6:** timestamped solve reconstruction/replay.
6. **Phase 7:** CFOP/Roux phase analysis.
7. **Phase 8:** TPS, move counts, pauses, phase times and trends.
8. **Phase 9:** algorithm recognition, PLL/OLL execution, recognition versus execution, TPS bursts, pause heatmaps, AUF, efficiency and case statistics.

Do not optimize the extreme long-deviation trail merely because cumulative work may approach O(N^2); preserve correctness and let Phase 2B address normal user workload first.

## P3 - Training And Data Depth

### Scramble And Training Controls

**Why it matters:** These improve deliberate practice, but they are less urgent than making competition-day and core timer flows dependable.

- Color-neutral and equal-probability scrambles.
- Configurable pre-scrambles.
- Training-aware completion for OLL, PLL, F2L, CMLL, and related subsets.
- qCube, qLast, and q2Look-style virtual cube views where they fit the native app.

### Advanced Statistics

- Configurable trimmed statistics and custom average lists.
- Reconstruction and phase analysis in solve details.
- Metronome and focused training tools.

### Backup Automation

- Optional automatic export and backup intervals.
- Clear success, failure, and last-backup states.

## Non-goals

- Do not copy web-only csTimer settings such as ads, floating browser windows, or desktop keyboard layout controls.
- Do not depend on private CubeStation protocols or undocumented account/server behavior.
- Do not scrape Competition Groups when the authoritative WCIF assignment data is available directly from WCA.
