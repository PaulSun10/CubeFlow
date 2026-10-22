# CubeFlow Cache Audit

Status: scoped implementation and cache audit complete; final unsigned Debug build
passed. Deferred provider-ownership migrations and the unrelated baseline test
conflict are explicitly documented below, not represented as completed features.
Audit baseline: existing dirty worktree on 2026-10-19. Initial status, tracked diff,
source hashes and pre-edit copies are in `build/cache-audit-oct19/`.
No physical device access, commit, push, cache cleanup or new dependency.

## Inventory: Existing Before This Task

Classification concerns the actual production path, not whether loading is visible.
Persistent caches under Library/Caches survive ordinary restart but can be reclaimed
by iOS; they are not backups. Unless noted, network failures leave the existing
visible data intact, but do not make that data newly authoritative.

| Area / classification | Storage and identity | Freshness / invalidation | Concurrency, offline and restart | Bounds / error recovery |
| --- | --- | --- | --- | --- |
| Browser list: partially implemented | Actor dictionary + `competition-query-cache-v2.json`; inner key v3, language, region, sorted event IDs, year, status | Stored `lastUpdated`; visible view suppresses repeats for 60s; disk has no expiration | Page requests coalesce by query + page; cache shown before refresh; cached list survives restart/offline | Atomic whole-file JSON; no entry/byte eviction; malformed JSON ignored |
| Browser runtime presentation: potentially incorrect growth | MainActor snapshots by filter signature, including prepared items and Top Cubers states | No lifetime or eviction; view-local loaded timestamp governs reload | Preserves navigation/filter presentation in process, not restart | Unbounded dictionary; no disk |
| Browser preferences/sorting: adequate | AppStorage `competition_filter_region/events/year/status`, card style, Top Cubers preference | User changes and query-bound task generation; sort is derived from query | Local and restart-safe; no network cache needed | Finite preference keys; enum fallbacks; no new persistence required |
| Detail sections/metadata: partially implemented | `CompetitionSectionStore` (80 entries) + `competition-detail-cache-v2.json` (24 entries); schema/resource/provider/competition/language | Live 15s, competitors/tickets 60s, other sections 6h; disk all 6h then discarded | Shared consumer-leased tasks; Info loads independently; disk excludes new Live/competitor/ticket sections; expired disk unavailable offline | Atomic JSON; count limits but no byte limit; corrupt format ignored; parse caches separate |
| Detail parsing: adequate for reuse, partial bounds | Rich documents by HTML/base URL (32), WCA semantic Info and schedule parse actors | Exact source identity; explicit clear/force refresh | In-flight parse work shared; semantic products rebuilt off MainActor, UI formatting separate | Rich document count bounded; some schedule/metadata maps lack byte/count policy |
| Country/localized-name/Live lookup support: partially implemented | Recognized-country and localized-name JSON, process-local WCA Live lookup by official competition ID | Names/countries have no automatic expiry; explicit support clear. Live lookup available 6h / unavailable 15min / failed 30s; loading not cached | Names loading task coalesces; countries/names survive restart, lookup does not | Atomic JSON; lookup/name maps lack overall resource limits; these support caches are not replaced |
| Top Cubers: potentially incorrect freshness | `competition-top-cubers-cache-v1.json`, inner `top-cubers|v2|competitionID`; row loader also retains state | No fetch timestamp/TTL; non-nil cache prevents refresh indefinitely | Per-competition fetch coalesces; cached rows available offline/restart; publication is deferred during active browser interaction | Atomic JSON; map unbounded; failure must not be confused with authoritative empty list |
| Calendar: partially implemented via detail | Calendar import consumes detail schedule and summary; EventKit writes are user-owned records, not cache | Detail schedule rules, explicit refresh | Existing parsed schedule can be reused; no separate persistent calendar-data cache | Do not delete EventKit events as cache; no additional calendar cache warranted |
| Official Results, event/round/competitor/All Results: partially implemented | `PublishedCompetitionService` memory models; key competition + event order; all views derive from canonical rows | Positive 1h, empty 60s; store previously short-circuited forever once same ID loaded | Per-key consumer-leased requests; no persistent result snapshot before this task | 12 models; no aggregate byte bound; failed refresh retains already-mounted data but recreation/restart loses it |
| Official Scrambles: partially implemented | Same service, eight in-memory grouped competition snapshots | 1h; view store also had permanent `loaded` early return | Shared requests; no persistent snapshot or restart/offline cold load | Count bounded, not byte bounded; failed refresh retains mounted sets |
| Official record indicators: adequate semantics | Derived from authoritative regional single/average fields in canonical results | New successful result response replaces the dataset, including empty/deleted/retracted records | Never infer records from ranks or numbers | No separate badge cache; do not create one |
| WCA Live: partially implemented cache, adequate existing realtime ownership | Detail/bootstrap memory and one round manager; opaque WCA Live IDs, distinct from official IDs | Snapshot on start/resume/reconnect; subscription updates supersede older HTTP via revision/request IDs; 45s polling fallback after failures | One owned connection; heartbeat, exponential bounded delay, network monitor; in-process last rows retained; no persistent provisional rows | Round-local state; no independent shared round/competitor cache; no disk-current guarantee |
| Cubing REST/SSE: partially implemented cache | Competition-scoped session; selected canonical snapshot, leased result requests; round metadata and record/podium/sum aggregates | Server identity + revision, equal-revision events, reconnect resync, aggregate refresh sequence | One stream/session; selected requests coalesce; unvisited selector records already use competition aggregate; no all-round scanning | Limits: 500 rounds, 20k snapshot results, 200 chat entries, 128 buffered frames; selecting a round clears visible snapshot; no restart cache |
| Legacy Cubing WebSocket: partially implemented, contract-limited | Selected raw results and users in session memory; legacy compressed keys/IDs | `result.all/new/update`, selected-round fetch on selection | Single receive loop; existing rows in process only; no confirmed record-flag contract | No persistent result cache; do not project REST identity/revision semantics onto it |
| Public WCA profile/PR/history: partially implemented | `wca-person-results-cache-v1.json`, WCA ID + language; supplemental country/name dictionaries | Timestamp retained, profile model shows cache then fetches `useCache:false`; same mounted model can return early indefinitely | Cache survives restart and failed fetch with saved-data timestamp banner; no shared person fetch pool | Atomic JSON but no expiration/count/bytes; malformed JSON ignored |
| Signed-in WCA profile/auth/history: adequate secret separation, partial public-data freshness | Tokens/refresh session in Keychain; display profile in UserDefaults; authenticated My Competitions in view memory | Token expiry with 60s margin, shared refresh task, sign-out removes stored session/profile; My Competitions explicit refresh | No duplication of credentials into content cache; profile survives restart, authenticated history does not | Profile includes personal fields; no new retention. Embedded OAuth client-secret configuration is a separate security follow-up; never copy its value into this audit/cache |
| WCA delegates/teams: partially implemented | Actor memory by group/region | `forceRefresh`, otherwise process lifetime; no TTL | No disk/offline cold load; no shared pending-request map | Finite source but no explicit eviction; errors thrown to existing view model |
| Timer scramble generation: adequate, not HTTP caching | TNoodle native prewarm/registry discovery; context-bound single-slot next scramble; FTO producer/reserve memory | Context/session/event/MBLD/language invalidates slot; stale completion rejected; consume-once, never replay a used scramble | Dedicated producer queues; prewarm avoids UI startup cost; no need to persist random next scrambles | Single prefetched payload, bounded FTO reserve; reset on process exit |
| Timer session/solves/reconstruction: adequate local persistence | Core Data SQLite with Session/Solve IDs; external binary reconstruction storage; comments in UserDefaults | Explicit model writes; automatic lightweight migration; merged contexts | Native local-first, available offline/restart; not an expiring cache | User data must not be evicted as cache; store-open failure currently fatal, separate resilience follow-up |
| Statistics/graphs: adequate local derivation, possible performance follow-up | Local solve samples, Timer `SessionStatisticsSnapshot`, DataTab computation and view state | Recomputed after selected session/solve mutations; source is Core Data, not network | No background network or stale HTTP involved; derived data rebuilt after restart | Work scales with user solve history; profile before adding another persistent statistics cache |
| Smart Cube/Timer: adequate separation | BLE canonical observation/session state in memory; saved device identity/alias/Auto-Connect preferences in versioned UserDefaults | Connection/observation readiness and existing protocol rules, not HTTP TTL | Device preferences survive restart; saved UUID is not an authoritative connected cube state | User-owned device list, no content-cache eviction; no changes to BLE/Combined |
| Algorithms: adequate datasets, partial user-state scalability | Bundled licensed datasets; per-set payload/normalized/source maps; learned/favorites/view preferences in AppStorage | Bundle version and set IDs; sorting/filter input rebuilds search index | Offline by construction, bounded set universe; learned/favorites survive restart | Diagram NSCache 128 images / 32MiB keyed by palette and rotation; large trainer history in UserDefaults deserves separate sizing audit |
| Explore competitions/recent records: partially implemented | Separate persisted Home snapshots, shared Browser query/page source, `WCAExplorePublicDataCache` | Home 6h stale classification; recent records 15min; partial source failure does not overwrite prior persisted aggregate | Shows cache then refreshes; cached data remains on error with existing saved-data notices | Atomic JSON; fixed Home prefix but locale/region files have no global disk budget |
| Explore rankings/records: partially implemented | Disk JSON by complete query, view-local timestamp and request generation | 15min in-view shortcut, persisted snapshot shown before refresh; official-record source kept separate from Live | Cached data available offline; no central in-flight dedup across views | No overall entry/byte eviction; key sanitization replaces punctuation and merits collision audit |
| Shared remote images: partially implemented | NSCache + URLCache, URL identity | `returnCacheDataElseLoad`; server/versioned URL required for refresh | Disk behavior depends on URLCache/server; no explicit in-flight coalescing | Image NSCache has no explicit cost budget here; algorithm diagram NSCache is separate and bounded |
| Settings/local preferences: adequate for small settings | AppStorage/UserDefaults, Codable versioned device stores; model migration in Core Data | Explicit preferences, enum fallback and feature-specific migrations | Persisted local state; no network refresh needed | Large image/trainer/comment blobs are user data, not content cache; do not clear globally |

## Architecture and Proven Competition Gaps

Existing mechanisms are reused rather than replacing the app's persistence model:
actor-isolated file caches, atomic JSON writes, canonical result models,
`CompetitionRequestPool` consumer leases, resource-scoped detail loads and
provider-specific realtime sessions. There is no new database or third-party package.

Proven gaps:
- Official results/scrambles disappeared across view recreation/restart after memory
  eviction, even when the app had already downloaded them.
- Same-ID store early returns bypassed expiration forever, including unpublished
  responses, preventing later publication discovery without forced refresh.
- Query/runtime and Top Cubers maps lacked resource limits; Top Cubers had no age.
- Detail disk snapshots were discarded at six hours instead of retaining a bounded
  stale copy for revalidation/offline use.
- Live selected-round clearing and repeated competitor loads require separate
  revision-aware investigation, not a universal historical TTL.

## Newly Implemented In This Task

### Official public Results / Scrambles

`CompetitionSnapshotCache` is wired into `PublishedCompetitionService.shared`.
Injected test services do not touch shared disk unless explicitly given a cache.
The key includes provider `wca-official`, canonical competition ID, resource and
schema; event ordering is a derived model dimension, not a second HTTP resource.

Raw validated bodies, validation timestamp, ETag and Last-Modified are stored in
versioned, SHA-256-keyed per-entry JSON envelopes. Credentials, authenticated
endpoints and provisional Live data never enter this store. The service coalesces
the underlying resource request even when callers want different event orders.
Successful responses are decoded and identity-validated before replacing disk.
Invalid JSON, wrong competition, duplicate rows, HTTP failure or cancellation do
not overwrite a valid snapshot. An authoritative empty response does replace it.

Results and Scrambles stores hydrate cached canonical data before waiting for
network revalidation. Existing loaded data is retained on failed refresh. Same-ID
loads consult service freshness instead of an indefinite view-store loaded bit.
UI navigation/selection/scroll owners and badge rendering remain unchanged.
Cached publication also hydrates **already cached** scramble sets before slow
Results revalidation completes. This performs no early scramble HTTP request;
new scramble requests still use the existing publication-owned loading gate.

A new canonical response invalidates **all** derived event-order models for the
same official resource. Bounded response tokens reject older async work and disk
reads that raced a newer response or cache clear. Thus correcting/removing a WR
through one event order cannot leave a fresh-looking WR in another model variant.
Network/decode byte/timing metrics describe the actual request and decode, not the
subsequent cache write; 304 responses do not report the cached body as wire bytes.

Policy reuses the existing one-hour positive official-data lifetime and one-minute
negative lifetime: official results can be corrected and are not immutable. The
new 30-day stale retention is an offline recovery budget, **not** a freshness claim.
Conditional requests use provider validators where supplied; lack of validators
falls back to an ordinary validated GET. A 304 refreshes the validation timestamp
without discarding the original body. Old empty snapshots are not used for offline
publication classification once their 60-second freshness ends.

Limits: 16MiB raw-body in-memory budget, 64 entries, 96MiB encoded disk budget,
16MiB maximum encoded entry, 30-day retention. Memory evicts LRU; disk evicts older
validated writes. Oversized entries are not persisted or truncated, and a valid
oversized network response **still loads in full**. Canonical-model caches are
limited to 12 result / eight scramble models and 16MiB source-payload cost each.
This is a payload budget, not a claim about exact Swift object heap size; current
view-owned data and transient network/decode buffers are separate. The requested
model is protected while older models are evicted. Response-token history is
bounded at 64 resources.
Atomic writes and per-entry corruption/schema/key validation isolate failures.
Old/incomplete unknown files are ignored rather than interpreted as current data.
Cache-manager detail size/clear includes the new public cache; clearing cancels
owned result/scramble requests before removing stored data.

### Browser Lists and Runtime Context

The existing query JSON format/path and pagination pipeline are retained. The
query actor now limits itself to 16 query snapshots, a 32MiB encoded file and
30-day saved-data retention. Bad/oversized files fail safely; stores are atomic.
The runtime presentation map is LRU-bounded to the same 16 filter signatures.
The active view still owns its current UI/expansion state. Evicted older filter
contexts reconstruct from persisted rows, rather than growing memory forever.

A **complete** fresh snapshot now avoids an unnecessary page download after view
recreation/restart. Incomplete/unknown-total snapshots never skip pagination.
Present/Recent use the existing 60-second current-discovery window; Past/all or
current-year catalogues use the existing one-hour public-data window; closed
historical years use the existing six-hour metadata window. Past catalogues are
less volatile than current discovery, but not immutable. Manual pull-to-refresh
still bypasses this shortcut.

Fresh disk data replaces an older runtime dataset before the shortcut, including
authoritative empty lists. Empty must not accidentally leave the old runtime rows
visible. No UICollectionView layout, native scroll physics, glass, Filter, or
disclosure/scroll-offset compensation code changed.

### Detail / Metadata / Calendar Inputs

The existing 24-entry detail actor/file is retained, now with a 32MiB byte limit.
Six-hour freshness remains distinct from 30-day stale retention. Reads preserve
the original validation time; returning a fresh disk entry no longer rejuvenates
it inside another six-hour memory layer.

The actual detail loader reads cached non-provisional sections before starting
background revalidation, guarded by its existing identity/generation. Live,
competitor and ticket sections are explicitly excluded from disk hydration.
Metadata/Info, regulations, travel, public registration and schedules can retain
useful offline content. Existing selections and view identities are unchanged.
Cached Cubing Info can provide its **previously verified embedded canonical WCA
ID**, scoped to provider/competition/language, so an offline revisit need not
download the HTML solely to discover which official result cache to read. A slug
is never guessed to be a WCA ID.

An existing localized "Showing saved information" caption is used for expired or
failed-revalidation Info/Results/Scrambles. It is appended below the content, not
inserted between accepted headers/summary/solve columns. This is a correctness
notice, not a new UI design. Successful revalidation removes its stale state.

The count limit is **24 resources**, not 24 complete competitions; this can evict
some sections sooner for users browsing many competitions. It remains a deliberate
bound, not a guarantee of unlimited offline history. Calendar import consumes
the same schedule data; EventKit/user events are never treated as cache.

### Top Cubers

The v1 cache had no validation timestamp, so it could prevent a WCIF refresh
forever. The v2 envelope adds a date, six-hour freshness, 30-day dated retention,
64 entries and a 32MiB file limit. The key now names `wca-wcif`, competition ID,
schema and sorted event IDs: a changed event set cannot reuse a fresh old subset.
Old v1 entries have **unknown age**, remain stale offline fallback, and are never
assigned a fabricated fresh date. Fallback badges are restricted to current events.
The legacy file is retired only after an atomic successful v2 write. Cache clear
increments a generation so old in-flight work cannot repopulate the cleared store.

Production loader revalidation retains loaded/known-empty content while fetching;
an error does not turn it into a placeholder or erase it. Unchanged data does not
republish any row. Changed data uses the **existing** interaction/idle publication
queue; it never publishes mid-scroll. Injected static acceptance fixtures keep
their explicit no-fetch behavior. No row packing, first-fit measurement, three-row
collapse geometry, glass or disclosure animation code was changed.

### Modern Cubing Live

New caching is **session-memory-only**, not persisted provisional data:

- At most 12 previously visited complete rounds / 20,000 cached canonical rows.
  No snapshot is truncated and no unvisited round is fetched to fill this cache.
- Reuse requires the same active SSE stream epoch, exact current round metadata,
  and a reconciled per-round state. A valid warm switch publishes synchronously
  without clearing rows, another result request, or another subscription.
- Existing delta validation now also updates already-cached unselected rounds,
  including equal-revision corrections and explicit result deletion. Gaps discard
  their authority and require REST resynchronization.
- Reconnect, stop/resume and unknown/malformed update paths invalidate prior
  stream authority. No stale warm snapshot is silently promoted across that gap.
- REST requests capture both stream epoch and per-round event sequence. An older
  same-revision REST response cannot overwrite a newer correction/retraction that
  arrived while it was in flight.
- Full-snapshot selector badge authority is also stream-epoch-scoped. Old full
  snapshots cannot override newer aggregate evidence after authority invalidation.
  Existing competition `/records` summaries, WR > CR > NR > PR precedence,
  single/average separation, equal-revision refresh and summary supersession remain.
- Competitor All Results requests share consumer-leased in-flight work, keyed by
  provider/competition/person/session/evidence generation. They are not retained
  under an arbitrary completed-result TTL. Superseded replies are rejected.

The existing selected last-known data/error presentation survives transient
failure while resynchronization runs; it is provisional, not a promise of offline
Live correctness. There is **no Live restart/offline disk guarantee**. Official
published data and Live state remain different sources even after a competition
ends. No global recent-record scanning or backend service was introduced.

## Freshness / Invalidation Summary

| Data | Freshness / authority | Persistent retention and invalidation |
| --- | --- | --- |
| Current discovery | 60s, complete snapshots only | 30d saved read; query/schema/filter key; successful empty replaces rows |
| Past catalogue / closed year | 1h / 6h, complete only | Same limits; explicit refresh fetches regardless of shortcut |
| Official results / scrambles | 1h positive, 60s negative; conditional validators when supplied | 30d positive stale budget; empty/retractions invalidate all model variants; failure does not write |
| Non-provisional detail | Existing 6h | 30d stale budget; per-resource/provider/language key; explicit refresh and schema changes |
| Top Cubers | 6h public WCIF metadata/PB window | 30d dated / bounded stale legacy; event-set identity; clear generation |
| Live bootstrap / private-changing sections | Existing 15s Live, 60s competitor/ticket memory | Not persisted or stale-hydrated by this pass |
| Modern visited Live rounds | Same synchronized SSE epoch + exact metadata + no revision gap | Memory only; reconnect/unknown events/metadata changes revoke reuse |

The 30-day figure is a bounded last-known/offline recovery budget, not a freshness
TTL or immutable-history claim. It balances common revisit/offline use against
retention/disk growth. Atomic writes can temporarily require space for both old
and replacement files. Steady-state new public storage is capped at 96MiB;
query/detail/Top Cubers files at 32MiB each. Existing support/Explore/person caches
are not incorrectly included in a claim that the **whole app** is now bounded.
Clearing downloadable caches does not delete already-mounted view data or the
Browser's bounded presentation/navigation context. A new list cache miss still
revalidates even when that context can display last-known rows. This distinction
preserves user context and is not presented as persistence after cache removal.

## Deferred / Follow-Up Priorities

1. No new shared completed-result cache was added to **WCA Live**: its accepted
   local `updateRevision`/request-ID authority is owned by the round manager, not
   a server revision available to a cross-screen generic cache. A safe future plan
   is a provider/competition/opaque-round keyed memory owner fed by the existing
   subscription and HTTP generation checks; mark disconnected values last-known,
   let actual subscription removals replace records, lease one transport, then
   verify reconnect/equal-data corrections/card consumers before enabling reuse.
   This ownership migration is intentionally deferred rather than introducing a
   stale TTL cache that can resurrect records.
2. **Legacy Cubing WebSocket** remains memory-only/current-round. Its compressed
   IDs/record semantics are not projected from REST. A future implementation must
   first verify round/filter identities and correction/deletion contracts, then
   attach a bounded cache to its single existing receive owner with session/event
   generations and an authoritative fetch after reconnect. No guessed record
   fields, disk snapshots or extra subscriptions were added here.
3. Bound public WCA person/Explore query caches and introduce shared fetch leases in
   a separate, targeted pass; preserve their existing saved-data notices.
4. Address OAuth client-secret configuration/rotation separately from this cache
   task. No credentials or secret literals are reproduced or newly persisted here.
5. Profile large user solve/trainer histories before choosing derived-cache or
   persistence migrations. Do not evict user-owned data as if it were HTTP cache.
6. Some HTML detail loaders still use `.empty` for unavailable/parse-failed content
   and cannot prove that an empty section is an authoritative deletion. This pass
   conservatively keeps prior useful content rather than inventing a deletion.
   A future typed loader outcome (`loaded`, `authoritativeEmpty`, `failed`) needs
   parser-contract fixtures and coordinated changes across those HTML resources;
   that broader migration is deferred. JSON result empty/deleted cases are verified
   independently and do replace cached data.

## Verification and Completion Gates

**91 distinct focused tests passed across this goal's runs**, including 31 newly
added production-cache/lifecycle checks. This is not one 91-test run and does not
hide the one pre-existing failing assertion described below. The final combined
cache/frozen-UI group passed 69 tests; later focused gates reverified the changed
publication/saved-data/policy paths, with 26 and then 17 checks passing. The last
gate used the final source and includes the actual URLSession offline error path.

| Evidence | Outcome |
| --- | --- |
| `published-cache.xcresult` | Initial 23 cache/official/record-discovery checks passed |
| `browser-detail-cache.xcresult` | 22/24 passed; initial empty-UI observation was corrected, unrelated baseline podium assertion preserved |
| `live-and-browser-cache.xcresult` | 46 focused checks passed |
| `final-focused-cache.xcresult` | 69 cache, modern Live, records, Top Cubers sizing/animation and All Results checks passed |
| `final-cache-policy.xcresult` | 26 policy, body-budget, canonical-cache and publication checks passed |
| `offline-final.xcresult` | Actual `URLError.notConnectedToInternet` (-1009) retained cached data and stale state |
| `final-regression-gate.xcresult` | Final-source 17 checks passed, including the offline path, cross-order retractions, oversized bodies and no-early-scramble-request gate |
| `final-generic-debug.log` | **One** unsigned generic iOS Debug build passed, `CODE_SIGNING_ALLOWED=NO`, `generic/platform=iOS`; no second generic build |

All evidence is under `build/cache-audit-oct19/`; `test-summary.json` contains
the deduplicated names, initial failures and unresolved baseline failure. No
physical acceptance is claimed. The test runtime is simulator-only; the generic
build uses Xcode beta's iOS SDK while preserving the existing iOS 15 target.

Verified paths include cold request/miss, warm cache hit, new service/cache instance
restart, provider/resource/schema isolation, corrupt/partial files, retention and
eviction, consumer cancellation/clear, positive versus authoritative empty, record
removal in every event-order model, stale-before-network UI stores, same-revision
SSE correction/deletion, gap/reconnect/unknown events, bounded visited-round reuse,
no additional stream, idle-only Top Cubers refresh and no warm republishing.

The Browser empty-state fixture was fixed to inspect the production empty SwiftUI
publication rather than await a callback from a UICollectionView that no longer
exists in that state. It now verifies both actual nonempty native display and empty
source/prepared rows. No production scrolling or rendering workaround was added.

`git diff --check` and explicit whitespace checks on all touched added files pass.
Source hashes confirm only the seven intended existing files changed. Settings
cache-size enumeration is already called from `Task.detached`; all new cache
reads/serialization/writes are off MainActor. No project/dependency/deployment
setting change, physical-device access, manual DerivedData/simulator/cache cleanup,
commit or push occurred.

Known baseline failure: `CompetitionSectionLoadingTests.testPublishedPresentationUsesCanonicalRowsWithoutLiveIDsOrAdvancement`
expects nil advancement for a final podium, whereas the accepted renderer supplies
its existing green podium state. The test and renderer hashes exactly match the
task-start manifest. Neither was changed to make the cache suite green; the failing
result is retained in `browser-detail-cache.xcresult`. The other 16 section checks
and the two actual Browser ABA/reactivation checks passed. This is not concealed
as a cache regression fix.

Physical checklist (user-operated only):
1. Open a historical competition's Info/Results/Scrambles, exit and restart the app,
   revisit it, and confirm cached content appears without an empty full-page reload.
2. With those resources previously loaded, test offline; confirm last-known data
   and saved-data notice, no account/solve loss, and honest missing-resource states.
3. Force refresh online after a correction; confirm badges/deletions and a changed
   event/round apply without resetting still-valid selections or opening another card.
4. Switch among fresh Browser filters, including empty lists, in List/Glass; verify
   native scroll, Filter, Top Cubers packing/disclosure and profile return context.
5. Check Top Cubers after an expired/legacy cache: same data must not twitch or
   republish; changed data may update only after scrolling is idle.
6. In modern Cubing Live visit two rounds and return; then reconnect/rotate rounds,
   confirm current values, record corrections and no double stream/subscription.
   Verify Beijing 666 mean WR, 777 final WR/WR and first-round NR single/CR mean.
7. Recheck WCA Live, Result Card/Back, All Results first-solve alignment, 6pt spacing,
   independent no-bounce horizontal scroll, shadows and separators. This pass does
   not claim the older unresolved physical Filter latency issue has been fixed.

## Files Changed

- `CubeFlow/Views/Shared/CompetitionSnapshotCache.swift` (new)
- `CubeFlow/Views/Shared/CompetitionCachePolicy.swift` (new)
- `CubeFlow/Views/Shared/PublishedCompetition.swift`
- `CubeFlow/Views/Shared/CompetitionRequestPool.swift`
- `CubeFlow/Views/Shared/CompetitionService.swift`
- `CubeFlow/Views/Shared/AppCacheManager.swift`
- `CubeFlow/Views/Shared/CubingChinaModernLiveSession.swift`
- `CubeFlow/Views/iPhone/CompetitionTabView.swift` (cache read/retention paths, saved-data footer only)
- `CubeFlow/Views/iPhone/CompetitionTopCubersLoader.swift` (data lifecycle only)
- `CubeFlowTests/CompetitionSnapshotCacheTests.swift` (new)
- `CubeFlowTests/CompetitionBrowserCacheTests.swift` (new)
- `CubeFlowTests/CubingLiveSessionCacheTests.swift` (new)
- This report.

Only seven pre-existing source files changed from this task's initial hashes.
Previously uncommitted Explore, Timer, Smart Cube, Filter/separator and rendering
changes are preserved. The project/deployment target and dependencies are unchanged.
