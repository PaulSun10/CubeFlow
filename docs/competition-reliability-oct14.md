# Competition Reliability Closeout

October 14, 2026. Source corrections and simulator verification, not physical-device certification.
Existing unrelated dirty work and external project settings are preserved. No commit or push.
Final focused regression and the single unsigned generic iOS Debug build passed.

## Root Causes and Corrections

| Issue | Evidence and correction | Production state path |
| --- | --- | --- |
| Filter permanent lockout | Native dismissal completion could precede binding false. Ignoring that ordering retained the native-content latch forever. Completion clears the current generation independently; queued intent resumes only after dismissal. Cancellation restores the active generation and rejects old acknowledgement. No cooldown/retry or redesigned popover. | CompetitionFilterPresentation; native dismissal probe; CompetitionBrowserView Filter |
| Filter/list mismatch | Cache, localization, detached lookup/preparation and errors could outlive their query. Every suspended publication validates query, active screen and cancellation. Same-query preparation also validates a source revision. Query reset/restore has one task owner; request UUIDs prevent cancelled A cleanup from clearing a new A load. A returning Browser does not wait for the old response. Warm reuse requires matching displayed identity. | CompetitionTabView: loadCompetitions, refreshCompetitionsForPullToRefresh, loadAllCompetitionPages, publishCompetitionPaginationBatch, publishVisibleCompetitionsSnapshot, CompetitionListLookupStore |
| Intermittent card presentation | A request made while a foreign controller was dismissing returned without a completion wake-up. Native transition completion now reconciles retained intent; withdrawn selections remain closed. | CompetitionNativePresentation: coordinator and presentation controller |
| Card motion and Detail Back | Restore reachable c551de97's opacity/0.97 scale, 0.18s ease-out in and 0.16s ease-in out. Only the card scales; full-scene dimming remains stationary. A transparent proxy intercepts only the measured native Detail Back region, dismisses/clears state, then invokes its existing action once. Other background toolbar/content/tab touches remain blocked. Profile owns its native Back. | CompetitionNativePresentation; competitionResultsPresentation |
| Top Cubers title rebound | Rendered title ink and public geometry writes prove a half-height shift: SwiftUI lays out growing content within old hosting bounds before native resizing. A max-height-only frame retains a content-derived minimum. The retained outer `frame(minHeight: 0, maxHeight: .infinity, alignment: .top)` accepts the temporary height and keeps a top origin. Native height interpolation and existing row insertion/opacity remain. No scroll/glyph offsets, fixed row height, grid/column/count changes or animation removal. | CompetitionHostingCollectionViewCell.setRootView; existing persistent disclosure and wrapping layout unchanged |
| Records/Podium advancement | Evidence previously depended on selected Results loading. Each grouped destination now requests complete field/adjacent opened-roster evidence for its displayed rounds, sharing session-local in-flight work. Install only validated current identity/revision/generation results. No selected-round mutation or qualification from truncated record/podium lists. | CubingChinaModernLiveSession; CubingChinaUnifiedLiveContent |
| Result-table corners | Mask and border formerly followed intrinsic overflow content. They now wrap the visible horizontal-scroll viewport. Preserve scores, widths, two 22pt insets and overflow. | competitorEventResultsTable / CompetitionResultTable |
| Missing round rules | An uninstrumented native screen capture reproduced a missing First/Second rule despite a valid one-pixel frame. Preserve the original gap and 36pt row, but draw the single adaptive separator on a full-row Canvas rather than a one-pixel leaf surface. Matrix and native screenshot pass; undocumented renderer internals are not asserted. | CompetitionResultRoundRow in CompetitionResultsStyle; All Results rows |

The source defects are proven paths; this does not assert which exact request/callback caused every original hardware session. Full investigation, rejected contrasts and failed-job records remain in `build/competition-reliability-oct14/investigation-notes.md`. Failed batches are not counted as passes.

The hosting correction uses the existing public [flexible-frame API](https://developer.apple.com/documentation/swiftui/view/frame(minwidth:idealwidth:maxwidth:minheight:idealheight:maxheight:alignment:)); it introduces no newer-OS dependency. The app's iOS 15 deployment settings remain unchanged. Tests run on iOS 27, so older-runtime acceptance remains pending.

## Focused Verification

Evidence is in `build/competition-reliability-oct14/`.

| Evidence | Verified scope |
| --- | --- |
| filter-native-ordering-after.log | 13 native tests plus actual production toolbar route: 20-cycle stress, queued/outside dismissal, callback ordering, cancellation, reconstruction, Region sheet return and original controls/capsule |
| filter-scene-restoration-corrected.log | Four Home/background/foreground cycles without relaunch; dismiss/reopen twice each; one close action |
| native-back-and-title-trace.log; back-wrapper-final.log | Native historical durations, full-window interception, retained lifecycle, exact-once Detail Back; actual SwiftUI Back twice |
| card-motion-and-back.log | Individual named Marietta/Minnesota repeated competitor-card cases and Beijing By Competitor/Profile/Sum/direct/round-origin cases passed. Initial Back failure in this batch was subsequently corrected; the original whole batch is not a pass. |
| cold-evidence-and-corners.log | 18 advancement cases individually passed, including complete field/roster, invalidation/cancellation and cold grouped entry. Its earlier erroneous corner fixture prevented an overall pass; corrected corners were rerun separately. |
| full-row-drawing-surface.log | Uninstrumented native separator screenshot; overflow corners; 18-render 2/3/4-round light/dark requested-subpixel matrix |
| browser-owner-and-top-origin-production.log | Top-origin title/height/glyph case passed (15.195s); actual Glass long-scroll/recycling passed (95.872s); actual cold List with loading during drag passed (84.747s). Earlier preference-observed page case failed; this batch is not an overall pass. |
| native-publication-and-final-focused-regression-corrected.log | Final focused batch status recorded below. Actual diffable display, not merely a coalesced preference, verifies 12 cache ABA cycles, 4 late successful-page cycles, 4 late-error cycles and 4 inactive/active cycles. Also cold grouped evidence, both scrolled-collapse boundary cases, overflow corners, separator matrix and Dynamic Type/recycling. |

Actual Browser expansion/collapse traces retain 0pt viewport and cell-origin drift; Glass title drift is 0.206/0.270pt, List 0pt, below the unchanged 1pt assertion. Native height interpolation is explicitly asserted, not replaced by a fade-only jump. Both appearances complete 24 user-style swipes and preserve expansion through recycling. The separate boundary tests permit only unavoidable nearest-legal-offset clamping.

Inspected rendered title baseline/midpoint/settled screenshots show 0pt ink drift in List and Glass. Actual Browser screenshots and trace attachments are exported to `build/competition-reliability-oct14/top-origin-production-attachments/`. Red chip outlines/measurements in those captures are existing DEBUG diagnostics, not restored production entry boxes. Native result screenshot confirms all three round rules at their unchanged positions. Light/dark overflow captures show rounded visible corners and symmetric insets.

The page-case test observer initially relied on SwiftUI preferences, which can coalesce independently of native collection application. The corrected observer records the actual diffable snapshot after apply completion, scoped to the test Browser only; delayed stale rows are still forbidden. Final source/prepared checks remain. Compile-only diagnostic errors and one source/module timing mismatch are retained in logs, not represented as application failures or consumed generic final builds.

## Flow and Preservation Audit

- Official round / By Competitor / All Results / Records / Podium, WCA Live round/competitor, and China Results / Records / Podium / Sum / My Results converge on the shared card-state/presenter. Source identities, target-round semantics and cancellation remain distinct. Simulator coverage is listed above; it is not exhaustive real-server/provider physical acceptance.
- WCA Live server-authored advancement is unchanged. Historical Official next-round participation, Final podium semantics and China revision/roster evidence remain distinct. No rank-only inference, incomplete-field qualification, or new WCA Live My Results.
- Original shared Map/Filter capsule/popover and filters, Sum of Ranks, current-user Me, record provenance, symmetric padding, Top Cubers badge order/three measured rows/wrapping, and existing transports are preserved.
- Project, advancement calculation and CubingChina HTTP transport hashes match baseline. No Timer/BLE/Gyroscope/Explore production edits were made in this goal. All unrelated pre-existing dirty changes remain.
- DEBUG-only capture instrumentation is bounded and opt-in where caller stacks are collected. No private selector/class matching or runtime swizzling is introduced; geometry probes never move content. Collector overhead is not claimed as physical frame-time performance.

## Cache Audit Matrix

This is a source audit, not measured network traffic for every destination. Application-level caches are listed; URLSession's incidental HTTP cache is not treated as a guaranteed offline dataset. The implementation paths are `CompetitionService`, `PublishedCompetition`, `CompetitionTabView`, `CubingChinaModernLiveSession`, `CubingChinaLiveExtras`, and `CompetitionWCALiveRealtimeManager`.

| Category | Fetch/cache owner and key | Memory / disk / freshness | Reuse and remaining risk |
| --- | --- | --- | --- |
| 1. Discovery summaries | CompetitionService; query-v3 + language/region/sorted events/year/status, page in request key | Query snapshots in actor and `competition-query-cache-v2.json`; lastUpdated retained, no store-enforced TTL | Browser paints cached summaries and refreshes pages. Runtime prepared-list cache avoids repeated preparation. |
| 2. Filtered lists | Browser; runtime signature includes language/region/events/status and effective year | Runtime memory only, no bound/expiry; Browser skips recently loaded nonempty query for 60s | Old cache/error publication lacked query/cancellation guards; corrected locally. Runtime cache policy should be bounded in a later goal. |
| 3. Detail metadata | CompetitionService detail-v10 + provider/language/competition/competitors/live; section store resource keys | Full detail memory + detail-cache-v2 JSON, 6h/max24; sections memory max80, resource TTL 15s-6h | Full-detail variants can duplicate shared resources; section pool already narrows tab fetches. Expired disk detail is not an offline fallback. |
| 4. WCIF | Separate registration-summary, Top Cubers and public-competitor loaders | Derived outputs cached; no shared raw/decoded WCIF owner in these three paths | Each issues reloadIgnoringLocalCacheData to the same public WCIF endpoint on its cold path. Per-feature dedup is not cross-feature dedup. Confirmed consolidation opportunity, deferred. |
| 5. Top Cubers | CompetitionTopCuberStore; top-cubers/v2/competitionID | Memory + top-cubers-cache-v1 JSON; no timestamp/TTL/bound | Warm entries do not refetch. Single-flight cold requests; event-filter/PB eligibility derived once. Indefinite participant/PB freshness needs an explicit policy. Loader publishes directly to hosted row. |
| 6. Official Results | PublishedCompetitionService; competitionID + ordered event IDs | Memory max12; published1h/unpublished60s; no application disk cache | Shared canonical dataset; request pool deduplicates. Published store retains a loaded ID without rechecking TTL until explicit refresh/recreation. |
| 7. Official By Competitor | PublishedCompetitionPresentation derived from item6 | Same canonical dataset; no separate network cache | Navigation reuses data. No competitor endpoint required. |
| 8. Individual rounds | Official derives item6; WCA Live round GraphQL/realtime manager; China session round endpoint | Official shares item6; Live selected snapshots memory only, no disk | China selected/adjacent/grouped evidence requests now share session-local in-flight work; completed full snapshots are not separately cached. Live view recreation/round changes can refetch. |
| 9. Competitor/All Results cards | CompetitionResultCardState; selection result/round or competition/competitor identity | Content retained for active selection, cleared on close; no shared Live competitor cache | Official loader derives item6. China competitors/<number>/results and WCA Live person query refetch on another card entry. Card task cancellation and selection checks protect publication. |
| 10. Records | Official derives item6; China ExtrasStore records endpoint, slug | Official shared; China view/session memory, no disk/TTL cache | Extras fetches server aggregates independently; displayed rounds now trigger their own complete advancement evidence. Global recent-record discovery remains separate. |
| 11. Podium | Official derives item6; China ExtrasStore podiums endpoint, slug | Same as item10 | Server category validation preserved. Subset lists must not calculate qualification against a truncated field. Final podium is not next-round advancement. |
| 12. Sum of Ranks | Official dataset derivation; China ExtrasStore statistics/sum-of-ranks, slug | Same as item10 | China server aggregate is not a full-round scan. Extras pendingRefresh coalesces overlapping refreshes; no durable aggregate cache. |
| 13. My Results | Official identity-filtered item6; China competitor endpoint using verified personal identity | Official shared; China active card memory only | Same repeated Live competitor fetch as item9. WCA Live has no My Results feature, intentionally unchanged. |
| 14. CubingChina Live | Modern session + HTTP client + ExtrasStore; slug/competition and round key/id/revision | Selected snapshot, rosters and aggregates session memory only; HTTP reload policy, no disk | SSE reconnect buffers during round/result/chat resync; generation/selection/revision guards. Returning to same surviving session retains usable data; a new session does not. |
| 15. WCA Live | Detail bootstrap + lookup store + per-round realtime manager | Lookup memory: available6h/unavailable15min/failure30s; manager's current round memory; no disk snapshot cache | Round starts/reconnect/resume resync. Request UUID, run identity and update revision protect resync from overwriting newer socket data. Server-authored advancement preserved. |
| 16. Advancement/adjacent rosters | China session nextRosters keyed round key, tagged revision; Official derives item6 | China session memory only; invalidated by round metadata/revision | Destination-owned grouped evidence loading now removes Results-order dependency. Existing selected-round task is retained, with same-key in-flight leases shared. Full field/roster installation is atomic and revision/generation guarded. |
| 17. Shared tab/card resources | Official canonical dataset; CompetitionSectionStore, rich-document/parse stores; detail identity | Official as item6; sections and parsed resources memory; full detail persistent as item3 | Section cancellation is consumer-leased. HTML uses 60s/max24 reuse. Browser and card state are UI owners, not authoritative durable caches. Avoid adding one cache per tab. |

### Cancellation, Publication and Offline Behavior

- Page/detail/Top Cuber/registration pools in CompetitionInFlightRequestStore share an unstructured task per key. A departing waiter does not necessarily cancel network work. This preserves other consumers but is not the same last-consumer cancellation policy used by HTML, sections and PublishedCompetition's CompetitionRequestPool.
- Published service validates competition identity/unique row IDs before caching; request pool cancellation releases consumers and cancels the last lease. Stores publish on MainActor with generation checks. Their memory dataset can remain visible during a failed refresh, but a process restart has no application-level Official Results fallback.
- China aggregates publish after all three concurrent endpoint operations and validate current generation/slug. Failed endpoints currently replace that aggregate with an empty array; useful previous data is not independently retained per endpoint. This is a confirmed cache/publication policy limitation, not a fix made in this pass.
- China rounds/rosters validate competition, round identity and revision. SSE invalidation drops obsolete advancement evidence and changes grouped evidence request identity. Grouped observation is through session @Published data; Records/Podium no longer rely on visiting the selected Results round.
- WCA Live retains its current round while transport stops. A recreated manager is seeded from detail content and requests a fresh snapshot. No application-owned persisted/revision-aware Live snapshot store is present.
- Query and Top Cuber disk stores offer restart reuse; unbounded/indefinite retention requires size/freshness policy. Expired full-detail cache entries are removed rather than returned marked stale. Do not promise offline coverage beyond an actually retained valid entry.

### Focused Next Cache Goal

1. Consolidate the already-proven duplicate public WCIF cold fetches into one competition/schema-keyed validated dataset, with consumer-leased in-flight work. Preserve existing derived models and measure before/after request counts.
2. Bound query/runtime/Top Cuber caches and define freshness separately from display usability. Do not make stale participants look live/current; do not discard useful offline snapshots merely because their refresh TTL elapsed.
3. Introduce provider/competition/round-identity/schema-keyed Live snapshot reuse, initially memory and then bounded persistence if justified. Render a validated retained snapshot immediately with explicit freshness, then connect and resync in the background.
4. China: retain server revision and metadata identity, buffer SSE during resync, install only non-regressing snapshots, invalidate dependent rosters/aggregate evidence coherently. WCA Live: retain existing request/run/update-revision protection; a cached snapshot must never overwrite newer subscription data. Keep each provider's native advancement semantics.
5. Share on-demand competitor data with a short explicit freshness policy and last-consumer cancellation. Never discover global records by scanning every competition/round; no new backend is proposed.

These are recommendations, not an implemented cache rewrite. Reconnect/poll timers already present in provider transports are not new Filter-recovery delays.


## Physical Acceptance and Limitations

- Repeat rapid Filter cycles, outside/interactive dismissal, Region return, background/foreground and rapid Present/Recent/Present changes on device, with slow/offline/error network conditions.
- Expand/collapse Top Cubers in List and Glass without scrolling, then collapse after scrolling through long entries; expect stationary viewport except unavoidable boundary clamping. Repeat with cold data, Dynamic Type, localization, VoiceOver and Reduce Motion.
- Revisit Marietta Monday Mini IV, Minnesota Quiet, Beijing and another competition; repeat all supported card entries, All Results/Profile/back, dimmer dismissal and native Detail Back. Verify all other underlying toolbar/tab actions remain blocked.
- Direct cold Records/Podium before Results; compare advancement afterward. Physically validate WCA Live server flags, Official historical next-round evidence, China/My Results, yellow-to-green updates, unknown states, reconnect/revision protection and long/unusual scores.
- Test small screens, iOS 15 runtime, prolonged sessions and memory/frame pacing. Simulator source tests do not certify physical responsiveness, live network behavior or accessibility presentation.
- Cache policy gaps in the matrix remain deliberately deferred. No broad cache rewrite, bulk global record scan or backend was introduced.

## Final Validation

- Final focused batch: **9 tests passed, 0 failures**, comprising 2 UI cases and 7 native/unit cases. The Browser cases exercise 24 controlled transitions; the separator case includes 18 rendered variations. No broad suite was run.
- **One unsigned generic iOS Debug build passed**: `final-generic-ios-debug.log`, `generic/platform=iOS`, signing disabled, deployment target 15.0. No second generic build was run. The only reported warning is skipped AppIntents metadata extraction without an AppIntents dependency.
- `git diff --check` passed. Project settings, frozen advancement calculation and CubingChina HTTP transport hashes still match baseline. The independent read-only reviewer is closed; no agent-started test/build remains running.
- Recorded active-goal execution time at final validation: **6h 02m 14s** (21,734 seconds, including previous continuations). This continuation took approximately 27 minutes. This is execution accounting, not a claim that all earlier time was productive verification.
- No commit or push. Hardware acceptance remains the next step; broader cache implementation remains a separate goal.
