# Competition Record Integrity, Personal Discovery, Warm Live State, and Filter Evidence

## A. Outcome and Scope

This pass continues the existing dirty worktree. It does not replace the previously accepted Competition Browser, Top Cubers, native presentation, or cache work.

Implemented:

- Official/historical PR enrichment from WCA's **server-authored historical PB markers**, shared by international and CubingChina published Results.
- One existing badge component: verified own PR blue/white, other PR gray, regional colors unchanged.
- User-scoped pre-navigation PR discovery through **one verified competitor**, not full-round scans.
- Detail-lifetime modern Cubing Live owners, synchronous known selector hydration, stable selection, last-known rows, and equivalent-publication suppression.
- Detail-lifetime WCA Live round caching, one active round subscription, revalidation, stale-response rejection, authoritative correction/retraction handling, and bounded compact record evidence.
- Additional passive DEBUG Filter dismissal-surface measurements.

**Not claimed fixed:** the physical native Filter rapid-reopen latency. The actual ZIP establishes a delayed UIKit lifecycle acknowledgement, but does not show when its animated surface actually disappears. There is not enough evidence to safely release the production gate earlier. Native presentation and animation remain unchanged.

**Not claimed passed:** physical-device acceptance. No physical Apple device was accessed.

## B. Missing Official Results PR: Exact Source Break

The saved actual response `build/record-integrity-oct19/official-beijing.json` contains official competition rows with `regional_single_record` / `regional_average_record`, but no personal PR fields. The competition HTML also lacks personal markers. Accepting `PR` as another regional code would not recover information that this endpoint never supplied, and would pollute global/regional discovery.

The native published adapter previously relied only on that competition dataset. It therefore had no historical PB evidence to render, even though its shared result components could already render explicit PR tags supplied by Live.

The reliable additional contract is WCA's public **person results page**:

- The [person-results template](https://github.com/thewca/worldcubeassociation.org/blob/main/app/views/persons/_results_by_event.html.erb) invokes the provider's historical PB marker calculation and emits `pb`, `wr`, `cr`, or `nr` on the corresponding single/average cell.
- The [official helper](https://github.com/thewca/worldcubeassociation.org/blob/main/app/helpers/results_helper.rb) establishes that regional emphasis substitutes for `pb` only when the historical PB marker is true.
- CubeFlow reuses its existing typed public-person HTML parser and `WCAPublicProfileCache`. It does **not** port that calculation or compare performances to infer records.

The join requires canonical WCA ID, official competition path/ID, event, exact known English round label, matching displayed single/average values, and exactly one matching result. Numeric equality is only a join validation, not a record test. Ambiguous/dual/unknown round mappings fail closed. Single and average remain separate. Regional flags retain precedence.

Profile loading is limited to visible competitors and user-opened competitor cards, with four concurrent loads. It does not scan every competition, every participant, or every round. The existing profile cache is the sole network/persistent owner: 15-minute page freshness, bounded typed public storage, no authentication/cookies copied into results storage. A valid expired snapshot is usable as dated evidence; a failed fetch is not an authoritative empty response.

The presentation flags are separate from raw official JSON decoding. They do not rewrite the cached official response or change regional/global record discovery.

## C. CubingChina Live Versus Official/Historical

| Path | Authoritative record source | Treatment |
| --- | --- | --- |
| Official international published Results | Official regional fields plus public-person historical PB cells | Shared published enrichment |
| CubingChina official/historical published Results | The same canonical official WCA dataset/person page | Same enrichment, not the modern Live parser |
| Modern Cubing Live round Results | Explicit `regionalSingleRecord`, `regionalAverageRecord`, `personalSingleRecord`, `personalAverageRecord` | Existing canonical flags retained for all people |
| Modern competition selectors | Existing competition `/live/records` regional summary; current full-round evidence; verified own competitor response | Regional precedence plus own PR only |
| WCA Live Results | Explicit `singleRecordTag` / `averageRecordTag` | Preserved in HTTP, subscriptions, cache, cards, and All Results |
| Legacy Cubing Live | Existing compressed WebSocket fields | No new undocumented flag interpretation |

Modern source samples already collected in this pass are retained in `cubing-competitor-112.json` and `cubing-sums.json` under the artifact directory. The competitor response supplies explicit PRs across that competitor's rounds. The competition regional-record summary must not be assumed to enumerate personal PRs.

## D. WCA Live Findings

Previously the production view created a fresh round-scoped manager from its navigation metadata. Returning to another round had no retained competition-level full snapshot owner. Home bootstrap also requested every round's full results. These are now separated:

- Home metadata requests competition rounds, schedule, regional `competitionRecords`, and the lightweight `competitors { id wcaId }` identity roster.
- Only an explicit deep-link target is eagerly hydrated. Other full rounds load on demand.
- One verified person's existing competitor endpoint supplies their across-round explicit PR flags before opening round Results.
- A parent-detail `CompetitionWCALiveSession` owns visited snapshots and compact record evidence. Round views own the transport only while active.

The public `competitors` association is documented by the [official WCA Live schema](https://github.com/thewca/wca-live/blob/main/lib/wca_live_web/schema/competitions_types.ex) and was verified with an actual GraphQL response saved as `wca-live-competitor-lookup.json` for competition `11089`. The schema copy is `wca-live-schema.ex`. No numeric Live person ID is treated as a WCA ID.

An additional identity-loss bug was found: the subscription selection requested `person.id/name/country` but omitted `wcaId`, whereas HTTP already provided it. Full subscription replacement therefore lost the canonical ownership identity. The subscription now requests `wcaId`; Phoenix/Absinthe framing, heartbeat, retry intervals, and polling intervals are unchanged.

## E. Badge and Selector Semantics

- Results, Result Card, expanded All Results: all competitors' legitimate WR/CR/NR/PR remain visible.
- Canonically verified signed-in person's PR: `RGB(25,118,210)`, white text.
- Other/unverified/signed-out PR: existing gray, `RGB(238,238,238)` light or `RGB(66,66,66)` dark.
- WR stays `RGB(244,67,54)`; CR stays `RGB(255,235,59)`; Results NR stays `RGB(0,230,118)`.
- Top Cubers NR remains its existing yellow; that component was not edited.
- Ordinary results get no badge. Ownership alone is not a record.
- Selector precedence: `WR > CR > NR > verified own PR`.
- Regional records can come from anybody; somebody else's PR cannot affect selectors.
- Modern event scope aggregates its rounds; round scope includes only that round. WCA Live's actual home navigation uses Active Rounds and Schedule, so its **existing round links** get the same scoped badge. No new WCA navigation design was introduced. The owner also supports event aggregation.

Own PR color is applied through the existing `CompetitionWCARecordTagView` and result-value component, not a second design. Padding, font, radius, record placement, and accepted regional colors are preserved.

The official enrichment also updates an already-open card's selection and All Results content without presenting again, resetting its measured expansion heights, or changing the card transition.

## F. Own PR Before Round Navigation

### Modern Cubing Live

Use existing Sum of Ranks competitors and other already available authoritative competitor associations. Require one unambiguous canonical WCA ID -> provider user ID + competition number association. Request that competitor's existing full competition result endpoint once per evidence/refresh scope. Validate every returned result against competition/round membership, user ID, number, and WCA ID.

No round is selected/loaded by personal discovery. Regional summaries continue loading independently. Account switch/sign-out clears private evidence immediately; current identity is checked again at presentation. Event sequences and request tokens reject superseded responses. Fresh empty lists and removed explicit flags retract prior personal records.

### WCA Live

Use the verified competition roster to find exactly one Live person ID for the canonical WCA ID. Request that one person's competition results through the existing endpoint. Validate person identity and all returned round/event/number memberships. Track per-round observation versions: a later full-round replacement, including an empty result or an identical authoritative update, wins over an earlier person request.

Regional records learned from a personal response are public evidence, separate from own-PR state; they are not discarded on account changes. Equivalent metadata refresh preserves known PR while revalidating the same verified person/round scope, avoiding a temporary badge disappearance.

## G. Provider Limits and Evidence Boundaries

1. A direct public-person HTML request in this environment returned **HTTP 403** (`wca-person-geng.html`, 118 bytes). The implementation is supported by the official template/helper contract and the repository's typed parser/fixtures, but successful fresh person-page access on the user's network is **not proven here**. If no valid cached page is available and the provider blocks the request, official PR remains unavailable rather than fabricated. This affects both international and CubingChina published Results.
2. Unknown/ambiguous official round labels or changed HTML cannot be safely joined and deliberately receive no inferred PR.
3. Modern own-PR discovery needs a verified association in the already loaded competitor sources. Missing/ambiguous ID/number mapping fails closed; no broad participant/round download is introduced as a fallback.
4. Old WCA Live cached metadata can lack the new optional roster. It remains Codable-compatible, but pre-navigation personal discovery requires fresh roster metadata. Missing fields never authorize guessed identity.
5. Neither provider offers a validated server revision for the WCA Live full snapshots used here. Client observation/request ordering protects known local races; it is not represented as a server sequence or proof of total global ordering.
6. Live records are provisional and can be corrected. Cache display is last-known evidence, not a claim that a disconnected stream is current.
7. Legacy compressed WebSocket payloads do not establish explicit PR semantics in the available evidence. Existing working decoding is preserved; no guessed compressed field or time-derived PR was added.

## H-J. Warm State, Cache Ownership, and Selector Jumps

### Modern Cubing Live

The old conditional child owned `StateObject` session/extras instances and configured them in `.task`. Removing/recreating that child lost known selector/options/record ownership and required an asynchronous rebuild/refetch. Its re-mounted initial deep link could also overwrite the user's later selection.

The competition-detail parent now retains one `CompetitionCubingLiveStores` entry, keyed by competition/provider transport. A new entry is configured synchronously before the child's first body. Returning to Live reuses the same session and extras, including known metadata and badges. A consumed initial-round request is not reapplied on every mount.

Visited-round snapshots restore synchronously. Prior-stream rows are presentation only until revalidation; they are never installed as the authoritative state into which new deltas can be merged. Cold metadata still loads normally and unknown records are not invented.

Existing cache bounds remain 12 full rounds / 20,000 canonical rows. Wrong competition or changed transport does not reuse owners. Identical canonical results, rounds, records, podiums, Sum of Ranks, bridge rows, and messages no longer republish equivalent arrays. Badge/advancement publications also skip equal values; advancement calculation and semantics are unchanged. Real corrections, deletions, authoritative empty snapshots, revision gaps, and account changes still update.

No badge-sized permanent empty placeholders were introduced. A genuinely cold server response can still add new information; the guarantee concerns already-known warm state, not unknowable cold records.

### WCA Live

- Parent lifetime, competition + language isolation; no process-wide live-session registry.
- Up to 12 full rounds / 20,000 rows, evicting whole snapshots, not truncating tables. Empty successful snapshots are retained as loaded.
- Only one active round manager; activating a new one stops the old. A stale disappearing view cannot stop the new manager.
- Synchronous seed before the round body's initial loading state. Known rows remain during revalidation/failure.
- Existing `explore.cached` caption distinguishes last-known Results from a current snapshot. Stop/suspend/offline/reconnect remove current authority, not known rows.
- Full authoritative replacement retracts obsolete flags, including nil flags and empty results. Unchanged real-time events still invalidate older pending HTTP, without republishing identical rows.
- Request IDs, run IDs, local observation revisions, round/event validation, and active-owner identity reject late HTTP/old-socket responses, including stop/start ABA and reused subscription IDs.
- Compact record evidence outlives full-row cache eviction, including **empty retractions**, so an old metadata record cannot reappear just because its full round was evicted.
- Compact evidence is bounded to 500 rounds, 2,048 person overrides, and 20,000 record entries. Resource overflow drops evidence rather than resurrecting older base records.
- A process-scoped monotonic client request-start context orders metadata against later local observations. It is not a guessed provider field, server revision, or freshness TTL. Old-process cached contexts are not used for current-process ordering.

## K-L. Actual Filter ZIP Findings

Source: `/Users/paulsun/Downloads/7B6FE08E-9A52-4C55-B344-9EFF96E38231.zip`.

SHA-256: `c49fc15a3da0a699ac3baf9afffd6cce205f49a1048d8986aaa6596aba16f999`.

The actual export has 112 events, zero dropped, iOS 27.2 build 24B5084k. Extracted JSON and full event TSV are saved in `build/record-integrity-oct19/filter-metadata.json` and `filter-timeline.tsv`.

| Native will-disappear (monotonic seconds) | Transition completion | Elapsed ms |
| ---: | ---: | ---: |
| 101963.597912 | 101965.094445 | 1496.533 |
| 101965.636774 | 101967.728090 | 2091.316 |
| 101968.437804 | 101969.694632 | 1256.827 |
| 101970.594699 | 101972.471438 | 1876.739 |
| 101972.995042 | 101974.238071 | 1243.029 |

Confirmed:

- Taps and application open/close intent are prompt (about 12-22 ms from recorded touch-end to action in this capture).
- A delivered reopen waits behind the current native dismissal.
- Observer and native container report the **same transition-coordinator identity**. This capture does not support blaming an unrelated observer coordinator.
- Completion registration succeeds; initial coordinator duration is zero, final completion reports 0.34 s.
- `didDisappear` and completion align closely. The native presenting/window relationship exists during the waiting interval and is removed by completion.
- Reopen publishes immediately after accepted completion; no additional application cooldown follows.
- Representable dismantling occurs after the acknowledgement, not before a lost completion observer.

Not proven: whether the visible native surface already vanished substantially earlier than those lifecycle events. A nominal 0.34-second coordinator duration is not enough to infer that every presentation relationship is safely detached after that time. The previous visibility sampler stopped at `willDisappear`, leaving precisely this evidence gap.

Production gating, flags, presenter, native surface, and animation are unchanged. DEBUG now samples the actual native presented surface's presentation-layer bounds, position, opacity, transform, window attachment, and projected window origin **during dismissal**, alongside the existing coordinator/lifecycle data. It uses a passive CADisplayLink at 12 Hz, stops on completion/disappearance/cancellation/recording-off, and is bounded to eight seconds. It never schedules a production action or changes touches, content offsets, durations, or UIKit dismissal.

Thus the physical Filter delay is explicitly unresolved, rather than hidden with a forced `isDismissing=false`, timer, custom animation, duplicate presentation, or replacement UI.

## M. Focused Regression Verification

Artifacts: `build/record-integrity-oct19/`.

| Run | Result |
| --- | --- |
| `personal-records-v1` | 16 passed |
| `official-and-warm-v1` | 45 executed; four assertion failures from old warm-cache/duplicate-publication expectations; updated to distinguish visible last-known state from current authority. No accepted podium/advancement assertion was changed. |
| `integration-v2`, `integration-v3` | Simulator compile attempts exposed optional metadata handling and one test actor-await expression; corrected before verification. Not generic iOS builds. |
| `integration-v4` | 36 executed; two assertions in one new identical-data test failed because the fixture used country code `BR` while the production decoder returns `Brazil`. Corrected the fixture, not the decoder. |
| `integration-v5` | 41 passed |
| `focused-final` | 99 passed, zero failures |
| `modern-publication-final` | 24 passed, zero failures; includes the additional identical-revalidation test |
| `wca-warm-final` | 9 passed, zero failures; verifies known personal badges survive equivalent metadata refresh |

The final focused coverage comprises 100 distinct tests after the additional publication test (overlapping reruns are not summed as unique tests):

| Suite | Tests |
| --- | ---: |
| CompetitionRecordIntegrityTests | 9 |
| PublishedCompetitionPRTests | 6 |
| CompetitionRecordBadgeRenderingTests | 2 |
| CompetitionWCALiveIntegrityTests | 9 |
| CubingLiveRecordDiscoveryTests | 6 |
| CubingLiveSessionCacheTests | 9 |
| CubingLiveRecordIndicatorTests | 4 |
| CompetitionRecordRoutingTests | 5 |
| PublishedCompetitionTests | 14 |
| CompetitionAllResultsTableTests | 7 |
| CompetitionSeparatorEvidenceTests | 3 |
| CompetitionPresentationBoundaryTests | 20 |
| CompetitionFilterEvidenceTests | 2 |
| Four relevant PublicProfileExploreCacheTests | 4 |

Coverage exercises production owners/transport seams and mounted production SwiftUI/UIKit components: own discovery without round selection, exact identity and ambiguity, single/average separation, ordinary no badge, rendered blue-vs-gray in both themes, unchanged regional colors, mounted official card update, cached/fresh/offline evidence, correction/retraction, late HTTP/old sockets, active lease replacement, cache eviction, full-row versus compact evidence, Codable compatibility, known selection restoration, duplicate-publication suppression, Filter repeated reopen/cancel/stale callbacks/reconstruction, original native Back, independent no-bounce solve scrolling, and one-physical-pixel separators at fractional parent origins.

These are simulator/component regressions, not physical acceptance or proof that third-party production networks will return all optional metadata.

## N. Build and Diff Check

- `git diff --check`: passed, including the final check.
- One final unsigned generic iOS Debug build: **BUILD SUCCEEDED**, exit 0. Command: `xcodebuild -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/competition-navigation-loading/DerivedData -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build`.
- Build log: `build/record-integrity-oct19/final-unsigned-debug.log`. Exactly one generic iOS build was run in this goal; simulator test compilation attempts above are listed separately.
- Non-fatal warnings remain: a `ViewBuilder` annotation on `configureWCALiveSession` is disabled by its explicit early return (normal Void behavior); App Intents metadata extraction is skipped because the app has no AppIntents dependency. No source was changed after the final build.
- No broad unrelated UI suite, signed build, installation, or device diagnostics.

## O. Manual iPhone Acceptance

The user performs these checks in Xcode/on the iPhone. None was performed by the agent.

1. Open an official competition with a known historical single PR, average PR, and both. Verify ordinary nonrecords have no badge. Repeat through CubingChina's official/historical Results.
2. Test Results -> competitor card -> expanded All Results, and By Competitor -> same card. Keep a card open while public-person evidence arrives; its summary and expanded tables should update without reopening or resetting expansion.
3. Sign in as the PR owner: blue/white PR. Another competitor's PR is gray. Sign out/switch account: no stale blue ownership. WR/CR/NR remain their original colors; Results NR green and Top Cubers NR yellow.
4. On modern Cubing Live, before opening the user's relevant round, wait for ordinary competition summaries/verified one-person discovery. Confirm own PR at the correct round and event scope, never another person's PR. A different-round WR must dominate the event but not the user's PR-only round. Repeat on WCA Live's existing round links.
5. Navigate between events/rounds; return from Info to modern Live. Already-known options, badges, chosen round, and visited rows should restore without the old blank/rebuild interval. Cold optional metadata remains allowed to arrive later.
6. On WCA Live, visit A -> B -> A, including an empty round. Confirm immediate known rows/empty state, no wrong-round rows, one active subscription, and successful refresh. Test offline/foreground return: known data stays visible with the saved-data caption until revalidated.
7. Observe real Live corrections and record retractions where available. No previous WR/CR/NR/PR should return after switching round, returning to the page, or signing out. Network interruption/reconnect must not let an older full response overwrite a newer update.
8. Confirm accepted Browser List/Glass scrolling, three-row Top Cubers, progressive disclosure, native interactive glass, and profile navigation remain unchanged.
9. Confirm existing card open/dismiss, Round <-> All Results, original toolbar Back, independent horizontal solve scrolling with no edge bounce, six-point solve padding, and one-physical-pixel stationary round separators in Light/Dark Mode.
10. Filter: in Settings > Development > Competition Diagnostics enable a Filter capture, return to Competitions, perform two or three close/rapid-reopen cycles, stop and export. Keep each capture short to stay within the existing 512-event limit. Compare `dismissal-native-surface` trajectory/window detachment with `native-did-disappear` and `transition-completion`. This is evidence collection for the unresolved native delay, not a claim that the delay was fixed.

## P. Files Changed in This Pass

Paths below are relative to `/Users/paulsun/Desktop/Projects/CubeFlow`. Changes from earlier dirty-worktree passes are not attributed to this pass.

New source:

- `CubeFlow/Views/Shared/CompetitionCubingLiveStores.swift`
- `CubeFlow/Views/Shared/CubingChinaPersonalRecords.swift`
- `CubeFlow/Views/Shared/PublishedCompetitionPR.swift`
- `CubeFlow/Views/Shared/PublishedCompetitionRecordEnrichment.swift`
- `CubeFlow/Views/Shared/CompetitionWCALiveSession.swift`
- `CubeFlow/Views/Shared/CompetitionWCALiveRecordLedger.swift`
- `CubeFlow/Views/Shared/CompetitionWCALiveSocket.swift`

Updated source:

- `CubeFlow/Views/Shared/CompetitionService.swift`
- `CubeFlow/Views/Shared/CompetitionWCALiveRealtimeManager.swift`
- `CubeFlow/Views/Shared/CubingChinaLiveModels.swift`
- `CubeFlow/Views/Shared/CubingChinaModernLiveSession.swift`
- `CubeFlow/Views/Shared/CubingChinaLiveExtras.swift`
- `CubeFlow/Views/Shared/CubingLiveRecordIndicators.swift`
- `CubeFlow/Views/Shared/PublishedCompetition.swift`
- `CubeFlow/Views/iPhone/CompetitionTabView.swift`
- `CubeFlow/Views/iPhone/CompetitionResultTable.swift`
- `CubeFlow/Views/iPhone/PublishedCompetitionView.swift`
- `CubeFlow/Views/iPhone/CubingChinaUnifiedLiveContent.swift`
- `CubeFlow/Views/iPhone/CompetitionFilterPresentation.swift` (DEBUG observation only)

New/updated tests:

- `CubeFlowTests/CompetitionRecordIntegrityTests.swift`
- `CubeFlowTests/PublishedCompetitionPRTests.swift`
- `CubeFlowTests/CompetitionWCALiveIntegrityTests.swift`
- `CubeFlowTests/CompetitionRecordBadgeRenderingTests.swift`
- `CubeFlowTests/CubingLiveRecordDiscoveryTests.swift`
- `CubeFlowTests/CubingLiveSessionCacheTests.swift`
- `CubeFlowTests/CompetitionFilterEvidenceTests.swift`

This report and local diagnostic/test/build artifacts are also new. Initial status, diff, and source hashes are preserved in `build/record-integrity-oct19/`. Baseline hash comparison found no removed files or changes to unrelated source files. The project file, Timer, Smart Cube, Algorithms, Top Cubers sizing/layout/animation files, Browser scrolling owners, native presentation/Back implementation, and separator rendering implementation were not edited in this pass.

## Q-R. Safety Confirmation

No physical Apple device was accessed. No devicectl, physical installation, launch, logs, signed build, or physical UI automation was used. No development artifacts, runtimes, caches, simulator state, or user data were cleaned up. No commit, push, reset, or revert was performed. All prior dirty-worktree changes remain preserved.
