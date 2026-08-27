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

Smart-cube development is paused at the current usable baseline. Reliability and competition-day value take priority over protocol experiments.

### Current Baseline

- GAN 16 UI, GAN 12 UI Maglev, GAN i4 Maglev, MoYu V10 AI, V11 AI, and Super WeiLong V2 AI have working protocol paths from prior hardware tests.
- Timer input, scramble target matching, start/stop flow, battery/hardware diagnostics, reset policies, and a fixed-view 3D cube are implemented.
- Facelets are the only 3D rendering truth; the move animation queue is intentionally removed so fast SwiftUI publications cannot make the model diverge.
- The 3D palette follows csTimer's reference colors and does not duplicate sticker color into SceneKit emission.
- Gyro-driven presentation and perfect M/E/S notation are deferred.

### Next Smart-Cube Milestones

1. Hardware-validate rapid-move facelet synchronization and the corrected orange/yellow palette.
2. Persist raw and readable reconstruction, per-move timestamps, move count, and TPS with each solve.
3. Add automatic CFOP and Roux phase timing using the persisted move stream.
4. Add training and continuous-training modes.
5. Add stronger hardware error detection and explicit re-sync recovery.
6. Add device-time to local-time fitting for accurate solve and phase timestamps.
7. Add physical cube orientation mapping and optional advanced virtual-cube views.
8. Revisit slice notation only if it does not reduce live responsiveness.

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
