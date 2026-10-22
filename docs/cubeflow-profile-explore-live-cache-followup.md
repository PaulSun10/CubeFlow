# WCA Profile, Explore and Live Cache Follow-up

Status: implementation and source audit completed; final verification recorded below.
Scope: the current dirty worktree, 2026-10-19. No commit/push, physical-device access,
new dependency, project/deployment-target change or manual cache/build-output cleanup.
This is not a claim of app-wide cache completion or physical acceptance.

## Baseline and Ownership

Read `docs/cubeflow-cache-audit.md` before editing. Baseline status, tracked diff,
SHA-256 manifest and pre-edit copies are under `build/profile-explore-cache-oct19/`.
The worktree already contained substantial tracked and untracked Competition,
Explore, Timer and Smart Cube work. Only six pre-existing source files changed in
this follow-up; the final manifest comparison records them. Prior Competition
snapshot/cache policies, official Results/Scrambles, Browser/detail bounds, idle-only
Top Cubers publication and modern Cubing REST/SSE sessions were not replaced.

| Area | Existing behavior | Newly implemented / decision |
| --- | --- | --- |
| WCA public results/PR/history | Typed page persisted in one unbounded v1 map, ID + raw language; saved timestamp/banner; mounted view returned indefinitely | Bounded typed snapshots; canonical ID; 15-minute freshness; shared leased requests; generation guards; bounded migration; force refresh preserves page/banner on failure |
| Public identity/avatar/teams/roles | Three public JSON endpoints, optional roles fetch; no persistent identity | Typed public-field allowlist, one-hour freshness, shared request and disk reuse; failed roles request cannot retract cached roles |
| Supplemental profile countries/names | Unbounded/permanent memory dictionaries; concurrent repeated loads | Existing owner retained, bounded dictionaries and shared in-flight work; per-country 24h and names 6h freshness; no new disk owner |
| Explore Home | Region/language snapshots; Browser/page API reused; Home six-hour TTL, five-minute retry suppression | Same owners and policy; bounded exact-key snapshots; validated legacy migration; shared Home refresh through final commit; clear-generation protection |
| Rankings/official records | Query-key JSON files, view-local 15-minute TTL; duplicate requests across views | Endpoint-scoped shared owner, bounded storage, fresh disk shortcut, typed validation before commit, full-key identity, no view-owned writes |
| Recent Records | Official history + global WCA Live feed, provenance-aware merge; partial results not persisted | Same discovery/merge/provenance; shared aggregate request, clear-generation guard, explicit official refresh; no competition scanning |
| Explore search | Local filtering of loaded Home competitions and navigation to Browser search | Audited unchanged; no fictitious network search cache |
| WCA Live | Round-local realtime owner + snapshot/reconnect/polling logic | Audited unchanged; visited-round cache deferred for ownership migration below |
| Legacy Cubing WebSocket | Competition session, selected raw rows, result.all/new/update | Audited unchanged; cache deferred until contracts below are established |

## Public WCA Profiles

The production paths from Top Cubers, competition Result Card/Profile, Rankings,
Teams/Delegates and Settings converge on `WCAProfileView` / its existing result
model. Full-screen Profile presentation, Back, scroll ownership, typography and
layout are unchanged. Explore's public-region lookup also uses the same cached
identity facade. Signed-in account state and authenticated My Competitions are
separate, unchanged owners.

`WCAPublicProfileCache` replaces the unbounded page store, not the public page
parser or auth storage. WCA IDs are trimmed, uppercased and validated against the
canonical 4-digit/4-letter/2-digit shape. Page keys include provider/schema/resource,
canonical WCA ID and exact requested language; identity is language-independent.
A fetched page must report the requested canonical WCA ID and content-language
scope before persistence. Complete, successfully decoded replacements overwrite
old collections, including empty collections; an HTTP/parser failure cannot erase
an old page. The existing HTML parser remains conservative: a missing expected
section is rejected, not guessed to mean an authoritative empty profile.

The mounted view no longer has an unexpiring same-ID return. It reads the dated
snapshot, uses a 15-minute freshness check, and force refresh bypasses that check.
A failed refresh retains both content and the original saved timestamp. Cached
identity has a one-hour freshness window; explicit profile refresh revalidates it
as well. Optional country/localized-name enrichment still runs on fresh warm pages,
with a request-generation guard so it cannot overwrite a newer page or language.

Network page and identity work use the existing consumer-leased request pool.
Cancelling one consumer does not cancel another; cancellation of the last consumer
cancels shared work. Completed tasks leave the pool. Cache-clear generations reject
late commits; view request IDs independently reject superseded presentation and
late enrichment. Force refresh joins an already-running identical public GET rather
than racing another download of the same resource.

Only typed public summary/PR/result/avatar/team/role models are encoded. Raw user
JSON (including extra/private fields), OAuth tokens, credentials, authorization
headers, cookies, email and sessions are not persisted. The production public
session is ephemeral with credential/cookie storage and URLCache disabled. Keychain,
sign-out and authenticated profile/history behavior were not edited. If the roles
endpoint fails, an existing complete identity is retained without advancing its
validation timestamp; a cold partial identity is persisted with an explicit incomplete flag for offline
use, never treated as verified empty roles or eligible for the complete-identity
freshness shortcut. A successful empty roles response does remove old roles.

### Profile Migration

The old `CubeFlow/wca-person-results-cache-v1.json` map is size-checked (32 MiB),
decoded with its original ISO-8601 dates, sorted deterministically and restricted
to the newest 64 candidate entries. Identity/language/date validation precedes
imports. The full-key v2 store rejects an older import over a newer response.
After successful bounded imports the exact old file is retired, preventing
resurrection after future v2 eviction; failed writes retain it for a later process
retry. Corrupt or over-budget legacy data is invalidated rather than decoded
without limits. Expired/invalid candidates do not become fresh. No migration touches
account data, documents, app files or another cache owner.

## Explore Identity and Cache Behavior

The previous lossy filename sanitizer was audited rather than assumed broken.
A deterministic test enumerates supported selectable events, result types,
continents, ISO country regions, genders and ranking/record display modes: **no
collision occurs in that actual supported domain**. Arbitrary strings such as
`a/b` and `a?b` do collide under the old sanitizer. The new representation is a
JSON array of identity components, SHA-256 filename, versioned envelope and exact
original-key validation. It also avoids case-insensitive filesystem aliases.

Rankings/records keys contain provider, resource/schema and the complete API URL
(path and query). Thus event, single/average, gender, region and API display scope
are isolated. No pagination or language dimension is invented for endpoints that
do not take it. UI localization is derived after loading language-neutral JSON.
The supported endpoints are not paginated: their actual fixed 100-person/result
scope is in the URL. General identity framing tests also distinguish page 1/2.
Home keys explicitly contain page 1, language, region, provider, schema and the
present/all-years/all-events query; Browser's multi-page owner is unchanged.

Compatible consumers really share resources: mixed/slim/separate Records displays
use the same `show=mixed` API payload; by-region Rankings' selected display region
is a local derivation over the same `region=world` response. Distinct API scopes
are never merged. Wire coalescing additionally keys HTTP method, URL and POST body,
so global WCA Live GraphQL discovery is not confused with an official Records GET.
No per-competition result scan or new backend was introduced.

Discovery/history highlights and Stats use the bundled ExploreHistory export, not
a separate network feed. MapKit manages its own tiles; this pass does not create
a second tile cache. Competition lookup destinations reuse CompetitionService and
the existing detail caches.

Old Explore public-data files have no self-identifying key/version envelope.
They are explicitly invalidated (not loaded under either guessed original key),
counted in ordinary owned-directory eviction and replaced by the next valid fetch.
This deliberately requires one online reload for pre-upgrade Rankings/Records/
Recent Records; it is not represented as seamless legacy offline availability.
New-format snapshots survive restart. Home's finite known language + ISO-region
legacy paths are unambiguous and migrate with their original timestamp, retiring
the exact old file after a successful write. Unknown legacy scopes are not guessed.

Views retain last-known content and saved timestamp while revalidating. Fresh disk
snapshots now avoid redundant downloads; force refresh bypasses freshness. Failed
loads do not write empty responses or advance dates. Successful typed empty results
replace old data. Ranking/Records and Home query generations reject superseded
responses. Recent Records retains its provenance and partial-failure warning;
a partial merge is never persisted as a fresh confirmation of both feeds.
Existing saved-data sections are reused for stale Rankings/Records during refresh;
Home keeps its established quiet saved-data policy. Layout/navigation are unchanged.

## Storage and Resource Budgets

`PublicDataSnapshotStore` is storage machinery, not a second authoritative business
cache. Profile, Explore API and Home owners decide identity/freshness/request
ownership. All snapshot file I/O and serialization run outside MainActor. Atomic
JSON writes carry envelope version, exact key, original validation date and body.
Invalid schema/key/date/corrupt JSON is a miss. Newer entries reject older writes.
Memory uses bounded LRU; disk eviction is newest validation date first with hashed
filename tie-break, count/byte/retention enforcement. Whole oversized entries are
not persisted; displayed results are never truncated to satisfy a cache budget.

| Owner | Freshness | Retention | Count | Disk | Raw-body memory | Per-entry encoded maximum |
| --- | --- | --- | --- | --- | --- | --- |
| Public profile pages + identities | Page 15min; identity 1h | 30 days | 64 total | 32 MiB | 8 MiB | 8 MiB |
| Explore public API + merged recent records | 15min | 7 days | 96 total | 32 MiB | 8 MiB | 8 MiB |
| Home competition page | Existing 6h | 30 days | 24 | 8 MiB | 4 MiB | 2 MiB |
| Supplemental profile countries / localized names | Per-country 24h / names 6h | Process memory only | 4096 each | None | 1 MiB UTF-8 key/value budget each, plus dictionary overhead | Not persisted |

Legacy files in the same Explore-owned directories count toward disk budgets.
A failed profile migration can temporarily retain the capped 32 MiB v1 input as
well as v2 output; it does not become another fallback authority after successful
migration. Library/Caches may be reclaimed by iOS; these are not user-data backups.
Writes denied by disk pressure do not turn a successful network load into failure.
Previously retained, non-expired entries work offline/restart; cold uncached data
still needs network. Retention expiry intentionally ends offline availability.
Settings cache-size reporting and explicit clear include the new stores. Clearing
public caches does not sign out or modify solves, accounts, timing or Keychain.

## WCA Live: Audited, Cache Reuse Deferred

Evidence: `CompetitionWCALiveRealtimeManager.swift` and the actual round renderer
in `CompetitionTabView.swift`; GraphQL decode/mapping in `CompetitionService.swift`.
The renderer owns a round-scoped `@StateObject`, starts on appearance, stops on
disappearance, and suspends/resumes with scene state. `configure` replaces the
selected round, stops transport and resets the **local** update counter. There is
no competition-level leased session shared among all round/competitor consumers.

One manager owns one Phoenix/Absinthe socket/subscription for the selected opaque
WCA Live round ID. `start` is guarded; run IDs reject old connection callbacks.
Initial/resume/network-recovery/subscription establishment trigger HTTP snapshots.
Snapshot request ID + selected round + pre-request local updateRevision reject a
late HTTP response after a subscription update. Heartbeat is 30s, handshake timeout
20s, backoff 1..60s; after three failures a 45s polling fallback runs. Polling checks
run/connection state rather than a server revision. These are existing behaviors,
not new validity promises or freshness TTLs.

Accepted `roundUpdated` payloads require a matching round and complete `results`
array. The mapper replaces that array (not incremental union); missing results and
nil record tags in a valid full replacement therefore retract old rows/tags.
Single/average record metadata is forwarded unchanged, not inferred from values.
There is no server revision in this model. An unvisited or detached round is not
subscribed, so a retained snapshot cannot be represented as current authority.

A small dictionary in the current round view would not satisfy the required
multiple-consumer/competition scope, reconnect authority and stale-HTTP invariants.
A robust visited-round reuse needs a competition-scoped owner, consumer leases,
one transport ownership boundary, round + local epoch identities, explicit
last-known/revalidating presentation, and replacement/retraction tests spanning
round switches/reconnect/polling. It must revalidate on return and never project
local updateRevision into a fictional server revision. This is a meaningful owner
migration, so this pass stops at that proposal. No provisional results are written
to disk, no new connection/subscription and no WCA Live production changes.

## Legacy Cubing WebSocket: Independent Audit, Deferred

Evidence: legacy bootstrap in `CompetitionService.parseCubingLiveContent` and
`CompetitionCubingLiveSession` in `CompetitionTabView.swift`.
Bootstrap parses legacy `data-c`, `data-events`, `data-params`, `data-filters` and
optional static messages. Numeric competition ID, event `i`, round `i`, filter and
result `i` belong to this legacy namespace, not modern REST IDs. Selected option
identity is event + round; outbound `result/fetch` includes event/round/filter.
There is one `wss://cubing.com/ws` session/receive loop; `start` refuses a duplicate
receive task, subscribes to competition and fetches the selected round. `stop`
cancels socket/loop. A receive failure exits with an error; there is no proven
reconnect epoch/acknowledged revision contract in this path.

`result.all` replaces `latestRawResults` from `data`; the handler has no verified
response request/round envelope guard. `result.new/update` tests `e`/`r` against the
selected option then replaces/appends by `i`. Existing consumers use `n` for user
number, `b`/`a` for best/average and `v` for attempts. These are existing source
semantics only: no guessed extra compressed field was assigned a record meaning.
There is no handled deletion/retraction message, verified record flag contract,
server revision or authoritative stale-response invalidation contract. Selected
raw rows/users are session-local, not a safe cross-round cache.

Required next implementation evidence: actual provider response identity for fetch
(event/round/filter + request association), full-snapshot/correction/deletion and
record-field contracts, reconnect subscription acknowledgement and resnapshot
ordering. Then put a bounded visited-round map under the existing single
competition session, invalidate authority on reconnect, reject late responses and
test complete replacement plus record retraction. Do not add another socket, bulk
round requests or reuse modern ID/revision rules. No legacy production change was
made; modern REST/SSE cache/record-summary work remains intact.

## Verification

Evidence directory: `build/profile-explore-cache-oct19/`.

- `compile-smoke`: initial simulator compilation identified default-MainActor
  Codable conformances crossing a cache actor. DTOs now have nonisolated data
  conformances; presentation-only label methods remain MainActor.
- `focused-v1`: 11/12 new tests passed; the failing ViewModel expiry fixture mixed
  an injected cache clock with system view time. The view now accepts the same
  test clock, defaulting to real time in production.
- `focused-v2`: 71 XCTest checks plus the selected Swift Testing Explore composition
  checks passed, including 15 new cache checks; Top Cubers sizing/animation,
  independent All Results tables, existing cache and modern record discovery
  regressions passed. Explore light/dark/Dynamic Type rendering snapshots passed.
- `final-focused`: 58 XCTest checks plus 19 Swift Testing composition checks passed,
  including the HTTP/page parser, typed public-identity privacy, aggregate partial
  failure and clear-generation boundaries.
- `final-gate`: 29 XCTest checks plus 19 Explore composition checks passed on the
  final country-metadata lifecycle, including per-scope view generations.
- `final-profile-eviction`: the actual 64-entry Profile owner evicted old snapshots
  and recovered a corrupt typed page through the network loader.
- `final-identity-gate`: all **26 new cache lifecycle tests** passed; the original
  `wcaProfileParserPreservesCollectionsPodiumsAndResultSemantics()` also passed.
  Cold incomplete roles now persist an explicit incomplete flag, with a dedicated
  restart/retry regression.
- Across runs, **87 distinct XCTest checks + 20 distinct Swift Testing checks**
  passed (107 total). `test-summary.json` deduplicates XCTest names, including a
  renamed page-generation test; the source suite contains 26 new lifecycle tests.
- `final-generic-debug.log`: the **one** final unsigned generic iOS Debug build
  passed using `CODE_SIGNING_ALLOWED=NO`, `-configuration Debug` and
  `-destination generic/platform=iOS`. No second generic build was run. The only
  warning was the existing App Intents metadata-extraction skip.
- `git diff --check` and explicit whitespace checks for all newly added source,
  test and report files passed. Final production SHA-256 checks match the exact
  files used by that build. Only the six listed existing source files differ
  from the task-start manifest; prior cache, rendering, Timer, Smart Cube and
  project/dependency changes are preserved.
  No physical acceptance is claimed.

The known baseline podium expectation conflict from the previous audit is not a
new failure and was not edited: `CompetitionSectionLoadingTests.testPublishedPresentationUsesCanonicalRowsWithoutLiveIDsOrAdvancement`
expects nil advancement, while the accepted final-podium renderer supplies its
existing green state. This unrelated assertion is excluded from the focused run;
source hashes verify its test/renderer were preserved.

## Files Changed in This Follow-up

- `CubeFlow/Views/Shared/PublicDataSnapshotStore.swift` (new storage component)
- `CubeFlow/Views/Shared/WCAPublicProfileCache.swift` (new public profile owner)
- `CubeFlow/Views/Shared/WCAResultsService.swift` (facade, DTO isolation, bounded supplemental owner)
- `CubeFlow/Views/iPhone/WCAMyResultsView.swift` (load/generation/banner behavior only)
- `CubeFlow/Views/Shared/WCAExplorePublicDataService.swift` (shared typed cache/request owner)
- `CubeFlow/Views/Shared/ExploreCompetitionProvider.swift` (bounded Home owner, aggregate lifecycle)
- `CubeFlow/Views/iPhone/Explore/ExplorePublicDataViews.swift` (cache integration/stale notice, no layout redesign)
- `CubeFlow/Views/Shared/AppCacheManager.swift` (owned size/clear integration)
- `CubeFlowTests/PublicProfileExploreCacheTests.swift` (focused production lifecycle tests)
- This report.

## Remaining Risks and Physical Acceptance

This is simulator/build/source evidence, not physical acceptance. WCA/legacy Live
visited-round ownership migrations remain deferred. The existing conservative HTML
parser cannot establish deletions from missing markup; such responses retain last
known data rather than invent an empty authoritative result. Old Explore public-data
snapshots require one online reload after safe invalidation. Failed/oversized writes
cannot promise cold offline persistence, and iOS may reclaim caches. Supplemental
country/name maps are optional process-local metadata, not an offline identity
source. No Filter rapid-reopen or BLE/gyro work was attempted.

User-operated checklist:
1. Open a Top Cuber Profile, inspect identity/PR/history, Back and reopen; ensure
   cached content appears without navigation/scroll changes. Repeat from Rankings.
2. Restart offline with a previously loaded profile; confirm saved timestamp/banner
   and data. Force refresh offline; the page and saved time must stay intact.
3. Refresh online after official corrections; check corrected PR/history/roles,
   single/average badges and absence of retracted data. Switch language/person
   rapidly; a previous response must not replace the current profile.
4. Load Home, Rankings, Records and Recent Records online, restart offline and
   revisit. Change event, gender, region and language; no incompatible cache reuse.
   Expect the first post-upgrade online reload for old public-data snapshots.
5. Pull refresh, including valid empty results and one-source failure; confirm
   saved/provisional notices and no false newly verified timestamp.
6. Recheck List/Glass scrolling, Top Cubers packing/disclosure, Profile return,
   Filter, Result Card/Back and independent no-bounce All Results tables.
7. Check WCA Live and modern Cubing Live correction/retraction/reconnect behavior
   manually; unchanged source and regression tests do not establish live hardware
   or provider acceptance. Legacy cache reuse is not claimed.
