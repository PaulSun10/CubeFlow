# Competition Data, Regional Live And Competition Day

Research/gap analysis only, 2026-10-05. Existing Competition/Explore UI, live advancement logic and transports are unchanged. This is not authorization to deploy a backend or restore the old regional Live UI.

## Existing CubeFlow: Preserve, Do Not Rebuild

| Area | Actual local implementation | Useful depth / remaining gate |
| --- | --- | --- |
| Explore | Content-first home composition, competition/record snapshots, loaded-empty/error/cache states and links into focused destinations | Editorial/Weekly/Community content requires separate product/backend work, not more placeholder cards. |
| Competition discovery | Native list/search, contextual filters, map and competition detail routing | China province semantics and registration-stage filtering can be deepened with a reliable regional source. |
| Detail | Overview, rules, travel, event/qualification/time-limit/cutoff data, venues/rooms and schedule in `CompetitionService` | Preserve native presentation; distinguish authoritative structured data from existing HTML fallback blocks. |
| Competitors/results | Public WCIF competitors, event/psych previews, WCA Live rounds/results/records/podiums and individual results | Personal assignments and source-specific freshness should be first-class later. |
| WCA identity / My Results | WCA OAuth PKCE/profile identity; personal records, medal/record collections and competition history | `WCAResultsService` uses WCA JSON for identity but still parses the official person page for rich results. A future structured replacement needs parity validation, not assumptions that all paths are JSON already. |
| Rankings/Records/Recent Records | Focused public-data views; WCA rankings/record endpoints; live recent records and explicit cache/stale state | Keep official records distinct from provisional WCA Live reports; no Recent Records navigation redesign. |
| Live | Existing GraphQL snapshots and Phoenix/Absinthe subscriptions with run/revision guards | Retain current manager's foreground/network lifecycle, heartbeat, reconnect/backoff and polling fallback. |
| Cache/offline | Actor/disk caches, retained snapshots, negative lookup caches and native retry/error presentation | Unify source age and provenance at adapter boundaries; do not discard successful cached data on provider failure. |
| Calendar | Native calendar import/review and ICS support | Not AlarmKit, Live Activities or a personalized WCIF dashboard. Those remain planned. |

The main China detail tab list currently does **not** expose Live. `CompetitionTabView` still contains a dormant legacy `CompetitionCubingLiveSession` using `wss://cubing.com/ws`, result/staff-chat messages. It is inaccurate to say no regional Live code exists, and unsafe to re-enable it merely because the class compiles.

## Current Cubing China Product Evidence

The current [competition browser](https://cubing.com/competition) offers year/type/province/event/search/status discovery. The [Guangzhou detail page](https://cubing.com/competition/Guangzhou-Grand-Open-2026) exposes useful regional depth: staged registration, pause/reopen and cancellation dates, phase-specific event/base fees, guest policy and local travel/organizer information. These are genuinely regional facts rather than a different presentation of official rankings.

The [schedule](https://cubing.com/competition/Guangzhou-Grand-Open-2026/schedule), [competitors](https://cubing.com/competition/Guangzhou-Grand-Open-2026/competitors), [travel](https://cubing.com/competition/Guangzhou-Grand-Open-2026/travel), [registration](https://cubing.com/competition/Guangzhou-Grand-Open-2026/registration) and [Live](https://cubing.com/competition/Guangzhou-Grand-Open-2026/live) pages were inspected separately, not inferred from the homepage. Registration requires sign-in; no account/private-registration flow was accessed. Live exposes round/rank/attempt/record/advancement context with provisional-result wording; the inspected round had no entered results, so this is not validation of an active v2 socket contract.

[Rankings](https://cubing.com/results/rankings), [records](https://cubing.com/results/records) and a [person page](https://cubing.com/results/person/2019WANY36) expose region/event/result filtering and personal/historical statistics. Official result records derive from WCA, while registration/local announcements belong to the regional service. News/competition reports are useful links, not permission to redistribute a full article feed.

The current site links explicitly to **v1**. Public repository source must not be treated as proof of the deployed **v2** API, realtime protocol, rate limits or permissions.

## Public Repository Findings: Separate Evidence Layer

Inspected [CubingChina/cubingchina](https://github.com/CubingChina/cubingchina) at commit `33ceab1efd8b7e1d0596cebe7e7af047142ded74`. GPL source was read for architecture only; no implementation copied. It uses PHP/Yii with MySQL, Redis and Ratchet/React networking.

The [API Competition controller](https://github.com/CubingChina/cubingchina/blob/33ceab1efd8b7e1d0596cebe7e7af047142ded74/protected/modules/api/controllers/CompetitionController.php) has list filters and detail/schedule/competitor/WCIF actions with visibility guards. Ticket/registration/sign-in operations are gated, not a public client API to reproduce. [Results handling](https://github.com/CubingChina/cubingchina/blob/33ceab1efd8b7e1d0596cebe7e7af047142ded74/protected/websocket/handler/ResultHandler.php) separates public fetch operations from privileged writes and broadcasts updated results/round state. [LiveServer](https://github.com/CubingChina/cubingchina/blob/33ceab1efd8b7e1d0596cebe7e7af047142ded74/protected/websocket/LiveServer.php) includes Redis record-computation notifications; this is not a stable v2 subscription specification.

The [WCA synchronization script](https://github.com/CubingChina/cubingchina/blob/33ceab1efd8b7e1d0596cebe7e7af047142ded74/protected/commands/shell/wca_data_sync.sh) currently consumes WCA export v2 into alternating `wca_v2_0/1` databases before switching the read pointer and rebuilding derived data. This supports treating official results as WCA-derived, not independently authoritative regional records. Deployment details were not executed.

## Source And Product Matrix

| Capability | Preferred source | Native direction |
| --- | --- | --- |
| Official event/round/limit/cutoff/advancement and published results | WCA / public WCIF / official result endpoints | Preserve focused lists/detail and canonical WCA IDs. |
| Rooms, schedule, groups and person assignments | Public WCIF | Next-assignment summary with role/station/room/time zone; no Competition Groups HTML scrape. |
| Provisional attempts/ranks/records/current rounds | Available, verified live provider | Competition-context Live; source label, age and provisional status. |
| China province/type, staged registration/fees/local policy | Regional structured API after contract/permission verification | Native filter/schedule/detail sections, with official/source link fallback. |
| Official rankings, records and personal result history | WCA where structured parity is available | Keep current native destinations; do not scrape regional mirrors of the same official data. |
| China announcements/travel/organizer specifics | Regional/organizer content | Short attributed contextual content/links; not a copied desktop news portal. |
| Registration/payment/tickets/admin/staff chat | Provider-owned authenticated systems | Open official flow; out of scope for a read-only mobile companion. |

Public WCA identity is not Cubing China account identity. A newcomer may have no `wcaId`; match an authenticated user carefully and keep `registrantId` scoped to its competition. Names alone must not auto-link people. Never ingest private WCIF birthdates/email/guest/comments as public dashboard data. [WCIF specification](https://github.com/thewca/wcif/blob/stable/specification.md) defines assignments, activities, rooms and result/round semantics; keep adapters version-aware rather than assuming a fixed attempt format forever.

## Coherent Live Architecture

Keep the existing WCA Live manager. [WCA Live's architecture](https://github.com/thewca/wca-live/blob/main/README.md) uses GraphQL subscriptions and WCIF synchronization; live scores are not equivalent to finally published official results. Add a separate versioned **read-only** regional adapter only after confirming v2 structured endpoints, schema, access/limits and actual realtime messages with permitted fixtures.

Proposed common snapshot envelope: canonical competition ID plus provider-scoped IDs; source/schema version; fetched/provider-updated timestamps; cache age; provisional flag; events/rounds/attempts/person IDs; current/upcoming activity when the provider supplies it; server-confirmed advancement versus projected standings. Do not infer actual venue progress solely from a scheduled time or reimplement advancement from displayed ranks.

Transport contract: full snapshot first, then validated revision/update events; duplicate/out-of-order rejection; reconnect resnapshot; bounded retry; suspend/network handling; provider-specific polling fallback. Reuse the established WCA lifecycle discipline, not its undocumented wire details for another provider. Namespace IDs and cache keys to prevent cross-provider/person/round collisions. A stale regional update cannot overwrite a fresh official snapshot.

Select a provider by verified competition availability, not geography alone. WCA Live is the existing supported path; a later regional path can serve competitions absent there. Offer source-specific freshness and explicit fallback links when unavailable. If both exist, select one live authority explicitly; do not mix attempts from unsynchronized systems. On official publication, reconcile into a distinct official-results view instead of silently changing provisional records in place.

## Live Versus Competition Day Versus Detail

**Competition Detail** remains the stable destination for general information, schedule, competitors and results. Live is a contextual detail tab/entry when a provider is available, promoted during an active competition but still reachable for historical results. No new permanent global Live tab or duplicate dashboard is needed.

**My Competition Day** is a personalized view inside My Competitions: next assignment first, then today's roles/groups and personal live result. It links to the same competition/round detail, not a second standings implementation. Schedule/WCIF is planned assignment truth; provider Live is provisional venue/result truth. Offline snapshots retain source age and time zone; cancelled/reassigned groups must invalidate reminders.

**Reminders** are a separate native delivery layer: registration milestones/calendar first, then availability-gated AlarmKit/Live Activities for justified assignment reminders. Live Activities should show compact next-assignment context, not mirror a web scoreboard. This pass adds neither reminders nor dashboard production UI.

Recommended sequence: deepen authoritative detail and regional facts; stabilize reminder semantics; build the WCIF-first personalized dashboard; then add a verified regional read-only Live adapter. Release gates include newcomer identity, room/time-zone/DST boundaries, incomplete WCIF, reassignment, offline/reconnect/reordered updates, provider unavailability and reconciliation with official results. Existing advancement rules remain untouched.
