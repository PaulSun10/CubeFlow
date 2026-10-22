# Competition And Recent Records Closeout - October 11, 2026

Continues the existing dirty worktree. No commit/push, project-file rewrite, native Live transport replacement, Records History integration, bulk competition scanning, or new backend.

This report supersedes the earlier reports' three-row Home preview, published three-tab navigation, and explicit-WCA-Live precedence for Chinese competitions. It does not replace their other Explore, ticket, loading, or Timer findings.

## Implemented

- Published navigation is Info / Results / Scrambles, plus a visible Live row when the competition's actual provider is verified available. Publication still defaults ordinary entry to official Results. Publication is established by official data, not an end date. Selecting an available Live archive afterward remains possible.
- China uses CubingChina Live; ordinary international competitions use WCA Live. No hidden China WCA Live destination is used. China selected Live remains pink (`#E60076`); international selected Live retains native accent blue. China's unselected primary labels/icons remain adaptive `.primary`, selected semantic labels/icons white, and Info adaptive neutral. Secondary Info styling is unchanged. Existing color sources and conversions are documented in [the color report](/Users/paulsun/Desktop/Projects/CubeFlow/docs/competition-navigation-polish-oct08.md).
- The approved **existing website fallback** now verifies current `/competition/<slug>/live` archive metadata and record-bearing rounds from the page's public SSR state. It requires matching slug/canonical WCA identity, `live: true`, and nonempty usable archive data. A fabricated URL alone cannot expose Live. Modern native results/transport are deliberately not implemented.
- Live Recent Records retain canonical event ID and verified round number/count from the existing global WCA Live GraphQL query. China website links use the site's actual `eventId` + `roundNumber` parameters only when that round exists in the archive. Legacy native China round targeting requires a unique semantic match; opaque provider IDs are never interchanged. Missing/ambiguous targets remain unavailable rather than opening an unrelated default round. Website fallback can select event/round, but does not promise native competitor/result-card selection.
- Official Recent Records keep their existing exact official result/event/round routing. The shared normalizer preserves verified WR/CR/NR flags, including WCA `AsR`, and highest selector level WR > CR > NR. The global Live candidate now uses that normalizer too; its old raw enum conversion dropped actual `AsR` metadata. No rank/time-derived record is invented; PR remains separate.
- Home Recent Records retains all ordered, deduplicated, Hero-excluded items. A hidden accessibility-excluded copy of the first four actual rows/dividers defines the viewport's intrinsic size; the visible inner vertical ScrollView contains all rows. Fewer than four records use their natural height. Existing rows, typography, wrapping, spacing, badges, See All, and other modules' caps are unchanged.
- iOS 26+ uses native bottom `.soft` scroll-edge styling and hides the other three edges. Earlier systems retain clipped native scrolling without unsupported modifiers. No custom gradient is substituted. UIKit edge-effect properties were verified; native visual attenuation depends on actual edge overlap/compositing, so a standalone viewport snapshot is not proof of a visible fade.
- Selected event/round shapes now wrap existing trailing badge space, with a 3-point drawing-only expansion for rounded-corner clearance. Badge positions, size, font, colors, cell layout, and spacing remain unchanged. Pixel tests compare old/new **selected** layouts, not different font weights between selected/unselected states.
- Scrambles uses the iOS-15-compatible `shuffle` symbol. The existing sky accent is retained; it is a CubeFlow choice, not a newly claimed CubingChina Scrambles token.
- Filter presentation is owned by the stable browser root instead of its transient toolbar Button. The first opening worked; the repeated status-switch/open sequence reproduced a popover disappearing before the next selection. Moving the presentation owner fixes that reproduced lifecycle problem without changing filtering, persistence, labels, or popover contents. No evidence supports blaming the word Present itself. Repeated opens and persisted Present after relaunch passed.

Browse, Peru Coming Up event glyphs/accessibility, Spectator Tickets, Timer/Smart Cube, and unrelated dirty changes remain preserved.

## Global Records Discovery: Evidence And Limits

The existing provider still combines **one global WCA Live `recentRecords` query** with **official WCA world WR history**. It has no global CubingChina Live record source. The refreshed Live query returned 55 records and omitted Guangzhou/Beijing; optional event-round metadata was accepted by the real schema. The previous goal's official history HTTP 403, partial-source cache retention/retry, 15-minute app TTL, order, and deduplication findings remain applicable. That network failure is not an empty successful response. The official world query does not supply all global CR/NR histories.

On-demand competition results are separate from discovery. The previously verified official fixtures contain seven flagged Guangzhou rows and nine Beijing rows, including Beijing `AsR`. Existing row and selector badges consume these flags correctly. Modern CubingChina Live exposes regional flags too, but its native compatibility update is deferred; those archives currently use the website's provisional record presentation.

### Public Legacy Repository Versus Current Production

The [public CubingChina PHP repository](https://github.com/CubingChina/cubingchina) is GPL-2.0. Its behavior was researched, not copied into production. The legacy Records controller/model/view implement current/history and world/continent/country scopes, default China/current, historical one-event results, WCA regional flags, and competition-start-date ordering. That implementation caches record responses for seven days and flushes cache after the WCA export import command. The inspected sync shell does not prove the deployment schedule or a freshness SLA. Its API Results controller does not provide a records-history JSON route.

**The current site is a different Nuxt/Express deployment. Do not apply the legacy seven-day cache or old parameters to it.** The served frontend uses:

| Observed current contract | Evidence |
| --- | --- |
| HTML history | `/results/records?type=history&region=world&eventId=333`; lowercase `world`, `_Asia` continent, `China` country; `event` accepted as an alias |
| JSON history | `https://wca-api.cubing.com/results/records/history?regionType=world&eventId=333&gender=all`; continent adds `regionId=_Asia`, country adds `regionId=China` |
| Current records, all 17 events | `/results/records?regionType=world&gender=all&expandRecordSources=true` on the same API; **current WR**, not global recent WR/CR/NR history |
| Response | Explicit single/average arrays, result/raw+formatted value, person/country, `recordCode`, canonical source competition ID/name/start/end dates, average attempts |
| Missing for exact navigation/order | No observed official result ID, round ID, global incremental cursor, or record publication timestamp. Competition dates are not submission/publication time |
| Observed cache | HTTP 200 JSON, ETag, `public, max-age=60, s-maxage=300, stale-while-revalidate=600`; not evidence of upstream export freshness |
| Coverage boundary | History requires one event; `eventId=all` returned HTTP 400. World history contains WR, not a union of all countries'/continents' records |

Real history responses include Guangzhou 3x3 WR 2.51, Guangzhou 5x5 WR average 33.19, Beijing 6x6 WR average 1:01.76, Beijing 7x7 WR single 1:27.47/average 1:35.93, Beijing Asia 7x7 `AsR` average 1:38.77, and Guangzhou China Clock NR single 2.26/average 2.71. Thus the mirror covers relevant official records; CubeFlow's current global feed does not consume it. [World history](https://cubing.com/results/records?type=history&region=world&eventId=777), [China Clock history](https://cubing.com/results/records?type=history&region=China&eventId=clock).

Read-only access succeeded without authentication, but no stable third-party API/support contract or redistribution permission was established. A valid history page initially exposed `boardError: list`; HTTP 200 alone does not establish useful data. Robots access is not an API license. Global WR history would require event fan-out; all CR/NR coverage would require additional regional fan-out unless the operator supplies a verified aggregate. No such feed was established. Do not introduce that fan-out, silently substitute a default China/current page, scan competitions, or invent chronological coverage.

## Deferred Native CubingChina Live Compatibility Plan

**Investigation only. The following adapter/transport changes are not implemented in this Goal.** Both [Guangzhou](https://cubing.com/competition/Guangzhou-Grand-Open-2026/live) and [Beijing](https://cubing.com/competition/Beijing-Autumn-Rivalry-2026/live) current archives returned HTTP 200 with matching competition metadata and nonempty `live-records:<slug>` SSR data after official publication. Legacy `/live/<slug>` did not supply the required legacy bootstrap.

### Exact Transport And Model Differences

| CubeFlow legacy integration | Observed current website contract | Required compatibility work |
| --- | --- | --- |
| `/live/<slug>`; `live-container` HTML `data-c/events/params/filters` | `/competition/<slug>/live`; Nuxt competition metadata; REST round/result snapshots | Add a versioned current-provider adapter, preserve legacy fallback; do not parse a modern page as legacy HTML |
| `wss://cubing.com/ws`; sends competition subscription and `result/action:fetch` | `https://api.cubing.com`; REST + **SSE**, not WebSocket | Separate cancellable URLSession HTTP stream decoder; do not merely change the WebSocket URL |
| Event + WCA-style round type (`1`, `f`, etc.) | Canonical `eventId`, integer `roundNumber`; distinct live-round ID, competition-round ID, competition ID | Explicit typed identity mapping; never equate IDs or infer a final round from an end date |
| `result.all`, `users`, `result.new/update` envelopes | Snapshot `{round, results}`; stream `{type,payload,occurredAt,viewers}` | Versioned decoders, snapshot/delta reconciliation and safe refresh on unsupported payload |
| Abbreviated `i/n/e/r/v/b/a`, separate users dictionary | `id`, `registrationId`, `userId`, `eventId`, `roundNumber`, `attempts`, `best`, `average`, `position`, nested `competitor` | Adapt authoritative values, stable result identity, WCA ID, number, name/localName, ISO2; share existing WCA result formatting |
| No proven regional marker contract in the legacy model | Explicit `regionalSingleRecord`/`regionalAverageRecord`; separate personal/female/rank markers | Reuse shared WR/CR/NR normalizer and highest verified selector aggregation. Do not convert `WR7` rank markers, PR, or female markers into regional record flags |
| Unversioned replacement/addition | Round `revision`, delta `upsertedResults`, `removedResultIds` | Revision-aware state, out-of-order protection, deletions, gap recovery and reconnect snapshot refresh |

Public read-only endpoints verified for Beijing:

- `GET https://api.cubing.com/competitions/Beijing-Autumn-Rivalry-2026/live/rounds`: HTTP 200 JSON **array**, 36 rounds. Each has live-round `id`, `competitionRoundId`, `revision`, `eventId`, `roundNumber`, status/timestamps, and nested `round` rules (`format`, timeLimit, cutoff, advancementCondition).
- `GET .../live/results/777/2`: HTTP 200 `{round,results}`, 17 results; live round 9518, competition round 12026, revision 45, status finished. Timofei's best 8747/mean 9593 carries explicit WR in both regional fields. These are archived **provisional Live** fields, not new official certification.
- `GET .../live/stream?viewerId=<bounded-client-id>`: HTTP 200 `text/event-stream`, private/no-cache/no-store. A bounded six-second read received a `heartbeat` event with SSE `id: 1`, `{type:"heartbeat",payload:{},occurredAt,viewers:3}`. Timeout intentionally ended the stream; no mutation or recovery replay was observed.

The served [SDK](https://cubing.com/_nuxt/Cc_Pr_FR.js) and [Live subscription adapter](https://cubing.com/_nuxt/8KXCmRws.js) establish endpoint construction and named events: `round.updated`, `round.rules.updated`, `round.competitor.joined/quit`, `result.updated`, `result.attempt.updated`, `result.checked`, `results.reranked`, `advancement.refreshed`, `message.created/deleted`, `chat.updated`, `heartbeat`. The [route client](https://cubing.com/_nuxt/Ce6DqqER.js) consumes delta rounds/upserts/removals. These served-client contracts are evidence, not a guarantee of a stable public API.

Its observed reconciliation rule accepts equal-revision idempotent upserts/deletions, applies a sequential revision, refreshes the selected snapshot for missing state or a forward gap, and does not roll back newer state with an older snapshot. On SSE open it resynchronizes rounds/selected results/chat. Do not assume SSE `id` is a durable resume token or implement Last-Event-ID replay without validation. A mutation stream, disconnect/reconnect, and split/multiline SSE frames still need deterministic tests and read-only live-session acceptance in the future pass.

### Focused Implementation Order, When Separately Authorized

1. Add typed current Live round/result/snapshot/event DTOs and small sanitized fixtures from the verified responses. Keep canonical IDs, source/provisional provenance, format/time limits/cutoff, record flags and revisions separate. Do not change advancement calculations in this compatibility pass.
2. Add on-demand public round-list and selected-round GETs, cancellation/identity generation guards, and failure/cache handling to the existing provider boundary. Select via canonical event+round number; load only the opened competition and selected round. Preserve the website fallback for malformed/unavailable/unsupported responses.
3. Add a bounded-memory SSE parser that tolerates network chunk splits, CRLF, multiline `data`, named events and heartbeat; cancel on destination/session change. Apply same/next revisions idempotently, delete removed IDs, refresh on gaps/unknown deltas and after reconnect. Use retry/backoff; no mutation/admin/chat-write requests.
4. Adapt the existing native result presentation, source label and event/round selectors; keep China pink, existing tables/cards, and WR > CR > NR. Use nested competitor WCA ID for matching; never reinterpret a WCA Live result ID as a CubingChina result ID. Existing read-only chat/podium/statistics features can keep the website fallback until their separate DTOs are validated.
5. Run targeted model/stream/revision/cancellation/deep-link tests and mounted light/dark snapshots. Physically check archived Guangzhou/Beijing and an available live competition, reconnect/gap recovery, selected event/round, records and source provenance. Keep global Recent Records discovery independent. No competition scanning or new backend is required for this on-demand transport update.

### Additional Investigation: Current Deployment And Integration Boundaries

This supplement is investigation/documentation only. The existing website fallback remains in use; no native transport integration was made in this pass. Existing dirty-worktree files, including the unintegrated `CubingChinaLiveModels.swift` scaffold, were preserved.

The current HTML entry bundle resolves `/competition/:alias/live` to [Bjba_olE.js](https://cubing.com/_nuxt/Bjba_olE.js), which imports [CFoDJUKa.js](https://cubing.com/_nuxt/CFoDJUKa.js). These freshly inspected assets corroborate the earlier subscription/delta contracts; hashed asset names are evidence, not stable API identifiers. A fresh six-second, unauthenticated Beijing SSE probe returned HTTP 200, `text/event-stream`, and a named heartbeat containing `viewers: 4`. Its intentional curl timeout is not a transport failure. It did not exercise mutations, disconnect recovery, or server replay.

Additional public snapshot evidence:

| Archive | Rounds / selected snapshot | Distinct provider identities |
| --- | --- | --- |
| Guangzhou | 31 rounds; `GET .../live/results/333/3`: 40 results, revision 109, finished | competition 1600; live round 9540; competition round 11974 |
| Beijing | Previously verified 36 rounds; `GET .../live/results/777/2`: 17 results, revision 45, finished | competition 1602; live round 9518; competition round 12026 |

The result's nested competitor ID is a user ID, **not** its competition number or WCA ID. The public Beijing `GET .../live/competitors/112/results` returned an array of 19 results for competitor number 112. It is an optional on-demand competitor-card source, not a reason to download every competitor's history. Round rules include format, time limit, cutoff and advancement condition. Results carry server `position` and `advancementStatus`; for example, a finished Guangzhou final still contains `advanced` values. Preserve received semantics rather than inventing new advancement logic from round completion. Empty regional-record strings and rank markers such as `WR3` must not produce WR badges.

Public read-only chat is also observable: `GET .../live/chat` returned anonymous state with `canSend: false`, `canModerate: false`, and `readOnlyReason: anonymous`; `GET .../live/messages?limit=50` returned message arrays for both archives. Messages use integer IDs, ISO `createdAt`, plain `content`, optional round context and nested user metadata, unlike the legacy `time`/HTML-content convention. The deployed client handles direct message payloads for `message.created`, an ID payload for `message.deleted`, and mute-state updates for `chat.updated`. These reads do not establish permission to send, a supported third-party OAuth flow, or an API stability commitment. Chat adaptation, if separately authorized, needs snapshot/update/deletion reconciliation and cancellation; no credential collection or borrowed WCA tokens.

The future compatibility patch should be localized to these boundaries:

| Existing boundary | Required change, not implemented here |
| --- | --- |
| `CompetitionService.loadCompetitionResource(.live)` / `CompetitionLiveContent` | Add a versioned modern bootstrap using validated competition identity plus round-list REST data; retain legacy extraction and verified website fallback. An initialized active round with zero results is not inherently unavailable. The current archive fallback's nonempty SSR record gate must not be reused as the modern native readiness rule. |
| Typed provider DTOs / new HTTP-stream client | Finish and validate separate competition, live-round, competition-round, result, user and registration IDs against fixtures. Add bounded public GET/SSE decoding; no URL substitution in the WebSocket client, no POST/admin requests, and no dependency on hashed frontend bundle names at runtime. |
| `CompetitionCubingLiveSession` | Preserve the existing legacy branch; add an isolated modern session selected by bootstrap version. Track selected-round identity, revisions and task generations, cancel old requests/streams, resnapshot after gaps/reconnect, and cap retries/buffer sizes. Do not silently drop deltas or let a late REST response overwrite newer data. |
| `CompetitionCubingLiveSection` / Live deep-link resolver | Adapt modern results into the existing presentation, use canonical event + integer round number rather than legacy round type `f`, and update selector metadata from SSE. Use server positions, attempts, nested competitor data and verified regional badges. Do not forward legacy filter parameters to an unverified modern endpoint or redesign the native table. |
| `CompetitionSectionLoading` cache | Version the modern bootstrap/cache representation and preserve provider/competition identity; never reinterpret cached legacy payloads as modern DTOs. Round snapshots remain on demand for the selected round, independent of global Recent Records discovery. |

Before activation, focused fixtures must cover both archives, an empty active round, nullable/unknown fields, wrong-provider IDs, exact event/round targeting, WR/CR/NR versus PR/rank markers, stale/equal/next/gapped revisions, removals, reconnect resync, round-switch cancellation, bounded failure/fallback and light/dark mounted UI. SSE framing must follow the [event-stream standard](https://html.spec.whatwg.org/multipage/server-sent-events.html#parsing-an-event-stream), including split UTF-8/chunks, CR/LF, comments, blank-frame termination and joined multiline `data`. The observed SSE `id: 1` alone does not prove persistent replay; reconnect should resnapshot unless that server capability is independently established. Real active-session updates and physical/network acceptance remain unverified.

## Verification

| Focused run | Result / scope |
| --- | --- |
| ArchiveVerified | 14 passed, zero failures/skips: archive identity/availability/round links, metadata/cache decode, source routing, explicit official badges, mounted navigation/target, measured viewport and unchanged badge coordinates |
| CompositionFinal | 20 passed, zero failures/skips: 19 composition cases including all retained records/Hero exclusion, plus section merge ordering |
| ArchiveAppearance / CompositorAppearance | The same mounted archive test passed in each focused rerun; these are overlapping checks, not extra distinct tests |
| FilterFinal | 1 passed, zero failures/skips: four opens/status selections, close each time, relaunch without status override, persisted Present selected |

Earlier iterations exposed the repeat-filter failure, the real `AsR` conversion bug, and fixture mistakes (safe-area sizing, comparing different selection font weights, and missing UIKit appearance override). They are not counted as successful final verification. One earlier mixed run completed its UI test but stalled result finalization and was interrupted; the final dedicated filter bundle replaces that incomplete evidence. No broad unrelated suite ran.

The final ArchiveVerified + CompositionFinal + FilterFinal bundles contain **35 distinct passing focused tests**. The repeated appearance checks overlap those tests. [Persisted Present filter after relaunch](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/competition-records-refinements-oct11/filter-present-restored.png).

Tracked and touched untracked files passed `git diff --check`/equivalent whitespace checks. The external project file remains SHA-1 `0aadcf8c7dd61852886cb8babdfd4ca5ff2ad70f`.

### Screenshots And Residual Appearance Risk

Actual SwiftUI snapshots were inspected, not design mockups. Four complete record rows appear in both modes; the eight-item fixture has additional native-scroll content. Mounted official entry selects 7x7 First round with CR, retaining WR final/event badges and row flags. Mounted published China shows the visible pink Live row, unselected adaptive primary text, shuffle symbol and existing website action.

| Screen | Light | Dark |
| --- | --- | --- |
| Four-row Records viewport | [Light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/competition-records-refinements-oct11/records-four-rows-light.png) | [Dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/competition-records-refinements-oct11/records-four-rows-dark.png) |
| Published China website fallback | [Light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/competition-records-refinements-oct11/live-fallback-light.png) | [Dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/competition-records-refinements-oct11/live-fallback-dark.png) |
| Exact official target / badges | [Light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/competition-records-refinements-oct11/official-target-badges-light.png) | [Dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/competition-records-refinements-oct11/official-target-badges-dark.png) |

**Unresolved visual acceptance caveat:** the beta simulator intermittently omitted the selected Live label/icon while retaining its pink fill, across UIKit and compositor captures. Other runs display the correct white content in both appearances. [The failing compositor capture is retained](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/competition-records-refinements-oct11/live-label-intermittent-dark.png), rather than discarded. Source styling remains explicit white, but these observations cannot prove a screenshot-only cause or physical-device correctness. No guessed production styling workaround was added. Check selected Live appearance repeatedly on device, including appearance switching; investigate separately if reproducible there.

The isolated selector fixture also triggers the existing top edge blur because of its tiny test window; mounted official snapshots show crisp glyphs/badges. No generic blur behavior was changed. iOS 15 guards compile in the app target, but the existing test bundle requires iOS 26.2+, so older-device runtime scrolling is not claimed validated.

### Final Build

**BUILD SUCCEEDED**, exit 0. Exactly one final unsigned generic iOS Debug build ran after the production corrections and focused tests. No production code changed afterward. The app target remains iOS 15.0; the nonblocking AppIntents metadata warning says extraction was skipped because there is no AppIntents.framework dependency.

```sh
xcodebuild build -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/cubeflow-explore-final-refinements/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''
```

Log: `/tmp/cubeflow-competition-records-goal/final-generic-ios-debug.log`. Final tracked/touched-untracked whitespace checks passed. Project-file SHA-1 remains unchanged. No commit or push.

### Production Paths

[CompetitionService.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/CompetitionService.swift), [CompetitionSectionLoading.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/CompetitionSectionLoading.swift), and new [CubingChinaLiveWebsite.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/CubingChinaLiveWebsite.swift) own verified archive availability/metadata and state propagation. [CompetitionTabView.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/CompetitionTabView.swift) owns provider-visible navigation, targeting, website fallback, and stable filter presentation. [WCAExplorePublicDataService.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/WCAExplorePublicDataService.swift) and [WCAResultPresentation.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/WCAResultPresentation.swift) carry verified event/round metadata and normalize record levels. [ExploreComposition.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Models/ExploreComposition.swift) / [ExploreModuleView.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/Explore/ExploreModuleView.swift) retain all Home records and measure the viewport. [PublishedCompetitionView.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/PublishedCompetitionView.swift) changes selected shape bounds only; [CompetitionFiltersView.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/CompetitionFiltersView.swift) adds acceptance-test accessibility semantics. Tests are in CompetitionRecordsRefinementTests, CompetitionRecordRoutingTests, PublishedCompetitionIntegrationTests, ExploreCompositionTests and CompetitionRefinementAcceptanceTests.

## Next Step

Perform physical acceptance of the four-row nested scroll/taps, native bottom edge behavior, repeated filter switching/relaunch, selected badges, and published Live archive website links on the user's network in both appearances. Native modern Live transport and any global Records History integration require separate authorization; neither is hidden inside this closeout.
