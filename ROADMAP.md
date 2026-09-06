# CubeFlow Roadmap

This is CubeFlow's durable product and engineering planning reference, consolidated on 2026-09-06. Preserve implemented behavior; revisit priorities after each release. Documentation is not authorization to implement or deploy.

## Product Boundaries And Planning Status

**Implemented/accepted foundation:** current Timer customization, numeral presentation, Data functionality, Competition browsing/details, Smart Cube Phases 0/1/1.5/2A/2A.1, and iPhone Draw Scramble default 275. These are not new TODOs. The Smart Cube checkpoint is `1844425d`; its architecture and physical evidence remain below.

**Near-term engineering:** Smart Cube Phase 2B is the next Smart Cube phase, only on explicit request. Existing P0/P1 priorities below remain important product/reliability work, not an instruction to interrupt that sequence. P2/P3 are retained topic/priority labels, not a sprint schedule.

**Planned product work:** Competition Day, private sync, training, public Explore content and Weekly. **Long-term direction:** shared rules/session semantics, Community, cross-platform clients and advanced analytics. **Exploratory:** exact Explore composition, proximity UX, richer social discussion and rolling video capture. None becomes the next sprint by being listed here.

Current tabs: **Timer | Data | Alg | Competitions | Settings**. A future candidate is **Timer | Data | Alg | Explore | Settings**, but do not rename Competitions until enough Explore content exists.

| Destination | Responsibility |
| --- | --- |
| Timer | Solving and activity execution |
| Data = Me | Personal solves, sessions, averages, records, graphs and later Smart Cube analysis |
| Alg | Learning and training |
| Explore = Everyone (planned) | Public competitions, rankings/records/stats, Weekly, Community and appropriate challenges/battles |
| Settings | Configuration |

Keep customization strong but Automatic/default behavior useful without configuration. Prefer native SwiftUI/system behavior; do not expose settings for every decorative detail.

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

### Other Planned Competition Work

- Post-competition Results experience and China competition filtering by province.
- Preserve the current browser's Large Title, context/subtitle/count, Map, Filter and full list. A future Explore layer leads into this destination, not a cluttered replacement.
- Keep WCIF/WCA Live dashboard planning above and existing accepted Competition UI intact.

## P1 - Reliability And Release Readiness

### Data Tab Navigation Stability

**Why it matters:** Time, Average, and Record are core daily surfaces. A toolbar segmented control that shifts, clips, or becomes unreliable makes the main solve history feel broken.

- Replace geometry-derived toolbar sizing where a stable native layout is possible.
- Verify Time, Average, and Record in every supported language and Dynamic Type size.
- Verify selection mode, graph actions, rotation, sheets, and iOS 26/27 navigation transitions.
- Add a focused regression checklist before release.

### iOS 26+ Horizontal Selector Liquid Glass Unification

**Why it matters:** Previously independent horizontal selector styles needed a common native Liquid Glass language instead of mixed custom fills/materials/edge blur.

**Status:** Implemented. Horizontal peer selectors now share one availability-aware style: native Liquid Glass on iOS 26+, with their existing appearance retained on earlier systems.

**Established design constraints (maintenance, not a new migration):**

- Preserve the shared horizontal selector component/style that owns availability checks, shape, spacing, selection state, animation, and feedback.
- On iOS 26 and later, use native SwiftUI Liquid Glass APIs, including `GlassEffectContainer`, interactive glass, native glass button styles where appropriate, and system-supported morphing rather than custom blur or material simulation.
- On earlier iOS versions, preserve the existing selector appearance and behavior. Do not spend additional time polishing the custom Competitors separator-edge blur solely for the fallback.
- Do not apply glass indiscriminately to read-only badges, status tags, table headers, date tabs, or horizontal data tables. This shared style is limited to interactive capsule/segmented selection controls.
- Verify light/dark appearance, Reduce Transparency, Dynamic Type, localization width, VoiceOver, selection feedback, rapid switching, and horizontal scrolling before replacing existing styles.

**Original audit scope, retained as regression coverage rather than unfinished feature work:**

- `AlgTabView`: all three hybrid subset selector contexts originally using duplicated `hybridSubsetPicker` / `hybridSubsetCapsule` implementations.
- `WCAMyResultsView`: the horizontal event selector in Results.
- `CompetitionTabView`: `CompetitionDetailTabStrip`, the Competitors event selector, and the Cubing China schedule event selector.
- Native segmented controls with custom surrounding surfaces in `DataTabView`, `CompetitionTabView`, and `AlgTabView`: preserve intended surfaces without duplicating system Glass or adding conflicting chrome.
- `TimerLocalBattleView`: retain coverage for event and handicap selectors where they function as peer capsule choices rather than menus.

**Maintenance invariant:** Every interactive horizontal capsule selector uses the shared abstraction; iOS 26+ receives native system Glass without custom blur/tint simulation, earlier systems retain their current fallback, and no page contains a one-off availability branch for the same selector pattern.

### Performance And Energy Follow-up

**Why it matters:** Previous hangs were reduced substantially, but sustained High Energy Impact still affects battery life and confidence during competitions.

- Re-profile tab switching and idle behavior on device.
- Eliminate remaining repeated main-thread view recomputation.
- Confirm no Core Data context is retained or disposed from the wrong executor.
- Set measurable idle CPU and tab-switch latency targets.
- Known cold-launch debt: initial scramble plus diagram can take roughly three seconds to become ready. Profile later; do not mask it by compromising timing correctness.

### Discoverability

**Planned:** a contextual TipKit pass to reveal useful features naturally after entry, not an intrusive onboarding maze. Exact tips and rollout remain open.

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

1. **Phase 2B, next on explicit request (2A.1 validation/checkpoint complete):** compare Recovery correction cost plus remaining original scramble workload with replacement scramble workload from current state; use hysteresis to avoid oscillation. No full solver/Replan in 2A.1.
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
- Square-1 training categories: OBL, PBL, 有特 EP and 有特 PBL. These are explicitly Square-1, not Smart 2x2/2x2 terminology; confirm unfamiliar taxonomy before expanding it.
- FTO: preserve already accepted competition event/name/icon/filter support. The supplied planning assumption is formal WCA-event status from January 2027; verify the official transition when implementing remaining event workflows. Treat it as a canonical WCA-event member at transition, not a permanent unofficial extension. This is not a request to redo existing FTO support or implement more now.

### Advanced Statistics

- Configurable trimmed statistics and custom average lists.
- Metronome and focused training tools.
- Personal reconstruction/replay, move count, TPS, pauses, phase analysis/times, trends and method recognition belong in Data, including solve details where useful; engineering order follows the Smart Cube phases above.
- Later analysis must separate raw moves/timestamps from inferred human method labels. For ambiguous ZB/ZBLL, skipped steps or alternative methods, ask for user confirmation when useful and retain appropriate confirmed interpretations/preferences so similar cases do not repeatedly prompt. Do not present uncertain classification as fact or alter raw reconstruction truth.

### Backup Automation

- Optional automatic export and backup intervals.
- Clear success, failure, and last-backup states.

## Planned Explore And Participation

### Explore Home And Public Data

Explore is a content-first discovery layer, not merely a destination List, uniform Grid or identical-card dashboard. Reference the browsing rhythm of Apple Music Home/New/Radio, Apple News and the App Store: one vertical surface mixing a full-width hero, large typography/numbers, editorial carousels/compact rows, record highlights, charts, Weekly and structured Community content. Exact order and layout remain open.

Use a stable skeleton with one contextual hero and very limited promotion of exceptional current content. Candidate hero priorities include a registered competition happening soon, Weekly ending soon, a significant WR, an upcoming competition or active Weekly. Do not randomly reorder the page or build AI/recommendation-feed infrastructure.

- **Competitions:** retain the focused existing destination described above.
- **Rankings & Records:** likely one destination with Rankings/Records peers. Keep frequent ranking controls visible: Event, Single/Average, World/Continent/Country or Region. Reuse existing WCA Profile navigation. Records include current WR/CR/NR, progression/history, charts and recent records, not just rank #1.
- **Public Stats:** discovery-oriented large-number facts can lead to full leaderboards/details. Candidates: most competitions, official solves, podiums, wins, countries, competitions by year, competition streaks, consecutive home-country competitions and longest competitive career. These are public WCA-derived stats, distinct from personal Data.

### Weekly And Community

**Weekly (planned)** is CubeFlow-native participation/leaderboards under Explore, never mixed into the official WCA Competition list. It can launch the existing Timer with Weekly session/attempt/progress context, not become a permanent Timer layout mode. Use Apple-native capabilities where useful; backend-owned Weekly state remains separate from client execution.

**Community (long-term umbrella)** may include reconstructions, PB/solve posts, Weekly results, algorithm discussion, reactions/comments, following cubers and challenges/battles. Do not prematurely define it as Forums or make unrestricted media-heavy social networking a dependency.

Product progression, not an immediate delivery plan:
1. Public WCA-derived competitions, rankings, records and stats.
2. Weekly participation and leaderboards.
3. CubeFlow identity/profile, optionally linked to WCA identity.
4. Online battles/matchmaking and richer shared activities.
5. Decide whether/how much discussion/forum functionality is actually useful.

### Official Results And Reconstruction

**Invariant:** an official WCA result reconstruction is not Smart Cube telemetry recorded during that official solve. Do not imply an electronic cube captured official competition moves.

One Reconstruction concept supports manual entry, video/memory analysis, recreating the official scramble later with Smart Cube input, and import. Optional provenance (Manual, Smart Cube Assisted, Imported) describes input method, not authenticity. Do not invent trust categories that imply assisted recreation proves the original moves.

- **WCA-linked/verified official result:** competition/event/round/attempt/time and official identity.
- **Complete/valid reconstruction:** supplied moves mathematically solve the official scramble state. This does not prove those were the actual competition moves.
- Desired linkage: Competition <-> Official Result/Round/Attempt <-> optional Reconstruction <-> WCA/CubeFlow profile <-> optional Community share.
- Later recreation attaches to this workflow; it must not create a fake normal solve in personal Data.

## Planned Sessions, Rulesets And Multiplayer

### Current Local Behavior Must Remain Available

**Implemented:** Head-to-Head and Side-by-Side are local two-person Timer experiences with continuous cumulative wins. Ten consecutive wins can mean 10-0; there are no fixed attempt counts, rounds, sets or automatic match ending. Users keep solving until they stop. Player 1/2 can be placeholders, not persistent accounts. Side-by-Side specifically means same-device landscape split-screen, not networking. Head-to-Head is not already an advanced match engine.

"Free Play" is a useful future name for these semantics, not an instruction to rename current UI. Preserve this simple default when optionally adding richer rules.

### Orthogonal Dimensions

| Dimension | Examples; none implicitly determines another dimension |
| --- | --- |
| Activity/session context | Solo practice, local two-person play, group practice/competition, Weekly, online battle |
| Ruleset | Free Play, fixed solves (including 5/12), Ao5/Ao12 aggregation, solve wins, sets, first-to-N solves/sets, turn order, same/independent scramble, inspection, penalties and tiebreaks |
| Timing/input | Touch, keyboard where appropriate, Bluetooth Timer, Smart Cube, future devices |
| Transport/discovery | Same device, LAN, internet/server/WebSocket, proximity-assisted pairing, QR, session code, account invite |

Advanced rules are not inherently online. Reuse logical rulesets across local and online contexts; transport changes, competition semantics should not. Future formats may include Free Play, Fixed Solves, Sets and Custom. Data-driven head-to-head rules can specify points/solves per set, sets per match, starting competitor/alternation, event, inspection, +2/DNF and tiebreaks. External leagues can inspire formats, but must not define a hard-coded engine.

Keep the Timer's upper-left native Menu focused on experience/layout (conceptually Solo, Head-to-Head, Side-by-Side). Do not cram a rules engine/toggles into it. Richer rules belong in a separate contextual Format surface after entry; exact sheet/popover/navigation design is open. Nearby is pairing/session discovery, not a peer layout concept. A contextual "Play Together..." shortcut may complement Explore's full discovery entry.

### Groups, Authority And Ownership

- Groups support casual Practice Together and Competition, not only 5/12-solve formats. Twenty participants need only their twenty phones; two-person battles need only the participants' devices.
- A dedicated spare Host is never mandatory. The creator/organizer may compete. Separate logical authority from hardware; optional authority transfer remains a design question.
- Optional Organizer Console/Host, Public Display or later Judge roles can exist. Mac/Windows consoles could manage participants, readiness, scrambles, attempts, penalties, results, leaderboard and session state without becoming a participation requirement.
- In same-device play, do not silently save the other person's solves into the owner's Data. Planned closeout lets the owner select a save destination and share/export the other participant's solves.
- Real user-owned local/group/Weekly/online solves may enter Data with activity context; official reconstruction replays are not real new solves.
- Define stable platform-neutral solve/session interchange; Share Sheet/AirDrop are Apple transports, not the data format. Recipients should open shared data in CubeFlow and choose an existing/new session or appropriate destination. Exact schema/file extension is open.

### Pairing And Session Protocol

**Exploratory Apple UX:** both users enter a join/battle flow, bring supported iPhones close, disambiguate the intended participant, confirm and join. Do not assume private NameDrop APIs. Nearby Interaction/UWB helps ranging/pairing, not session data transport. Use runtime capability checks; do not raise the whole deployment target for an optional enhancement. Unsupported devices retain local discovery, QR/code, invite or internet fallback.

**Architectural direction:** serializable platform-neutral SolveResult, Session, Participant, Round, Attempt, Scramble, Penalty, Ruleset and MatchState concepts. The schema and serialization technology remain open. Do not expose Swift-only wire types or depend on deprecated Apple-only peer APIs. Native discovery/networking adapters can differ by platform while sharing logical session semantics; LAN and internet/WebSocket are transports, proximity only assists discovery.

## Platform, Sync And Infrastructure Direction

### Apple First, Not Apple Complete

Develop iPhone/iPad/Mac together where practical. Stabilize/mature/release the core product and session/data semantics before the first major expansion, likely Android; do not wait for every long-term Apple idea. Windows follows with strong organizer/large-screen potential, then HarmonyOS as demand warrants, Linux much later. This is strategy, not an immutable release promise or instruction to start another client now.

Use platform strengths rather than force parity: iPhone portability/touch/camera/proximity, iPad Side-by-Side, Mac/Windows organizer/data/keyboard, and native Android/HarmonyOS integrations.

### Responsibility Boundaries

CubeFlow remains local-first: ordinary timing/scrambles, private solve/session operations, local analytics/training and device integration must not become server-dependent.

| Owner | Responsibility |
| --- | --- |
| CloudKit (planned) | Private Apple-device sync for appropriate personal solves/settings/data; plan conflict resolution, offline changes, retry/reliability and multi-device lifecycle, not just a sync checkbox |
| CubeFlow backend/ECS (planned public services) | Accounts/public identity, Weekly, Community/reconstruction metadata, coordination/matchmaking, leaderboards, APIs, lightweight real-time messages and selected public-data cache |
| WCA/public sources | Authoritative official competitions/results/rankings/records/public data |
| Object storage/CDN | Avatars, images and later video; not ECS system disk |
| App Store/GitHub/platform releases | Application/source distribution; not large IPA/APK downloads from the small ECS |

Deployment remains gated on explicit confirmation of ICP completion and authorization. Private CloudKit sync is not the public Community/battle backend. A small ECS can initially support a lightweight/static website, API, small database, Weekly/metadata and low-traffic session coordination; ready/start/time/penalty/result messages are small. Scale from measured CPU/RAM, DB latency/connections, API latency, concurrent sockets and bandwidth, not the word "Community".

Keep the product website lightweight/static where practical, optionally linking public services/share pages later; do not turn the whole product into a web app or lock this roadmap to an unconfirmed framework. This is a distribution boundary, not website implementation work.

### Media And Rolling Capture

Early Community should favor reconstructions, text, stats, WCA links, reactions/comments and small avatars. Images later; video later still with deliberate duration, compression/resolution, retention, cleanup, storage and egress limits. No unlimited video assumption; use object storage/CDN.

**Exploratory, long-term:** optional PS5-like rolling camera buffer, allowing the user to save preceding seconds/minutes after a PB or manually, with configurable duration and eventual Solve/Community linkage. Future design must cover permission, visible capture state/privacy, memory/storage, compression, energy/thermals, lifecycle/background limits and cleanup. Never compromise Timer latency or timing correctness. Do not implement now.

## Non-goals

- Do not copy web-only csTimer settings such as ads, floating browser windows, or desktop keyboard layout controls.
- Do not depend on private CubeStation protocols or undocumented account/server behavior.
- Do not scrape Competition Groups when the authoritative WCIF assignment data is available directly from WCA.
