# Modern CubingChina Live - October 11, 2026

Continues the existing dirty worktree under the **Modern CubingChina Live Native Compatibility & Personal Results** goal. This authorized follow-on implements the compatibility plan from [the earlier investigation-only report](/Users/paulsun/Desktop/Projects/CubeFlow/docs/competition-records-refinements-oct11.md); that report's native-transport deferral applied to the preceding goal. No commit, push, project-file rewrite, backend, competition scanning, or global Recent Records discovery change.

## Implemented

- Current CubingChina Live loads native round metadata and the selected round's REST snapshot, then consumes SSE. Both active rounds (including empty snapshots) and finished archives use the existing CubeFlow CubingChina Live UI, not a web embed or another Results design.
- Canonical `eventID + roundNumber` selects the round. Numeric competition, Live round, competition round, result, registration, user and message IDs have separate typed domains. Competitor number is used only for the competitor-results endpoint; neither it nor a CubingChina user ID is passed to WCA Live.
- Per-round server revisions prevent stale rollback. Equal-revision upserts/removals are idempotent; next revisions reconcile; gaps raise a snapshot revision floor and trigger REST recovery. Every stream open/reconnect resynchronizes metadata, the selected round and public chat; no undocumented SSE replay guarantee is assumed.
- Round selection, leaving Live, backgrounding, retry and stop cancel owned work. Generation guards discard late snapshots and prevent an old connection's cancellation from closing a replacement stream. Reconnect attempts are bounded to five with 1/2/4/8-second waits; selected-snapshot recovery is bounded to three attempts. Permanent HTTP/format errors are not retried indefinitely.
- Incremental SSE framing handles UTF-8, BOM, CR/LF/CRLF, split frames, multiline data, named/default events and heartbeats. Line/frame limits are 512 KiB; the 128-frame stream buffer fails on overflow and resynchronizes rather than silently dropping deltas. REST JSON is checked for HTTP status, MIME and a 4 MiB decoded-response limit; this is not a streaming-download size cap.
- Server position, attempts, best/average and explicit regional record flags drive presentation. The existing normalizer produces WR/CR/NR, including `AsR -> CR`; rank markers, female markers, personal records and score comparisons are not promoted to regional records. A selected round's known highest badge also appears beside its selector. Unopened rounds are not downloaded to calculate badges. Advancement is not recomputed.
- Signed-in own-row recognition in both CubingChina Live and WCA Live requires an exact valid WCA ID match. No name, case-folding, trimming, missing-ID or account-number inference. The drawing-only system-blue treatment uses background alpha 0.035 light / 0.065 dark and a 1.5-point leading line at 0.22 / 0.30. Row metrics, fonts, rankings and existing record badges are unchanged; there is no You badge or provider-pink highlighting.
- My Results appears only when the displayed round contains that exact identity. Native CubingChina result taps/deep links reuse the existing viewport-owned result card and on-demand All Results loader. Missing/unavailable competitor results do not create an empty destination. Official rows do not acquire the Live-only emphasis.
- Public native chat uses the existing Chat card, a read-only label, initial messages, created/deleted events, empty/error states and website handoff on failure. No sending, login form, credential collection, cookie/credential storage or WCA-token reuse was introduced.
- Published official Results remain the default unless Live was explicitly opened. Verified Live remains a separate first-level destination: CubingChina only for Chinese competitions, WCA Live for ordinary international competitions. China Live remains `#E60076`, selected text/icons white and unselected primary rows adaptive `.primary`. Secondary Info styling and international styling are unchanged. Live record markers are explicitly provisional.
- Verified `/competition/<slug>/live` website fallback remains available if native bootstrap fails. Legacy native content continues down its original transport path. Switching between modern and legacy content clears incompatible rows/state. Live section cache version is now v3; old optional-model decoding remains compatible.

## Verified Production Contract

These are observations of public production endpoints/client behavior on October 11, not a promised third-party API stability contract.

| Operation | Public API path under `https://api.cubing.com` | Shape / identity |
| --- | --- | --- |
| Round list | `/competitions/<slug>/live/rounds` | Array of Live rounds, revisions, canonical event/number, nested rules |
| Selected results | `/competitions/<slug>/live/results/<event>/<number>` | `{ round, results }`; nested competitor WCA ID and server position |
| Competitor results | `/competitions/<slug>/live/competitors/<number>/results` | Array; competition-local competitor number, not user ID |
| Public messages | `/competitions/<slug>/live/messages?limit=50` | Message IDs, plain content, ISO timestamp, competition ID, optional nested user |
| SSE | `/competitions/<slug>/live/stream?viewerId=<anonymous-id>` | `text/event-stream`; JSON envelope `type/payload/viewers/occurredAt` |
| Chat permissions (research only) | `/competitions/<slug>/live/chat` | Anonymous read access; sending/moderation disabled |

[Beijing's public archive](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/beijing-native-light.png) fixture has 17 7x7 Final rows, revision 45, competition 1602, Live round 9518 and competition round 12026. Its first competitor has verified single/mean WR flags. [Guangzhou's public archive](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/guangzhou-native-light.png) fixture has 40 3x3 Final rows, revision 109, competition 1600, Live round 9540 and competition round 11974. Its `WR3` world-rank marker does **not** become a WR badge. Sanitized full-result fixtures retain public identity/result fields, not operator/admin metadata.

Production SSE returned a named heartbeat with viewer count. Result/round mutation payloads and same/next/gap revision handling were verified in the [production client adapter](https://cubing.com/_nuxt/CFoDJUKa.js) and [Live route client](https://cubing.com/_nuxt/Bjba_olE.js); deterministic fixtures exercise those mutations. This pass did not mutate production results or claim to witness an ongoing competition mutation. SSE `id: 1` on an archive heartbeat is not evidence of durable replay support. Framing follows the [HTML SSE parsing rules](https://html.spec.whatwg.org/multipage/server-sent-events.html#parsing-an-event-stream).

Public chat messages were accessible without authentication (45 Beijing / 50 Guangzhou messages in the inspected snapshots). The [anonymous Beijing permission response](https://api.cubing.com/competitions/Beijing-Autumn-Rivalry-2026/live/chat), rechecked during closeout, reports `canSend: false`, `canModerate: false`, `readOnlyReason: anonymous`. The website's own authentication/API methods are not evidence of a supported external OAuth contract. No suitable documented third-party authorization contract was established, so chat sending/auth integration remains deferred.

## Code Paths

- [CubingChinaLiveModels.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/CubingChinaLiveModels.swift): typed identities, validated bootstrap/snapshots, revision reconciliation and exact WCA ID matching.
- [CubingChinaLiveTransport.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/CubingChinaLiveTransport.swift): public REST, incremental SSE and underlying URLSession cancellation.
- [CubingChinaModernLiveSession.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/CubingChinaModernLiveSession.swift): selection lifecycle, snapshots/deltas, bounded recovery, read-only chat and competitor lookup.
- [CubingChinaLivePresentation.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/CubingChinaLivePresentation.swift): adapter to existing selectors/result/card DTOs, canonical targeting and server-authored records/rankings.
- [CompetitionService.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/CompetitionService.swift): identity-gated modern bootstrap, verified website fallback, legacy continuation and cache version.
- [CompetitionTabView.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/CompetitionTabView.swift) and [CompetitionPersonalRowTreatment.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/CompetitionPersonalRowTreatment.swift): existing native Live integration, own rows, existing result-card ownership and on-demand My Results.
- English, Simplified Chinese and Traditional Chinese `CompetitionPublished.strings`: read-only/provisional/error/My Results copy. No unrelated localization edits.

## Verification

**25 focused tests passed, zero failures**, in the final run: 13 protocol/session/identity/fallback tests, eight bridge/mounted-presentation tests and four actual URLSession HTTP/SSE tests. They cover both archive fixtures, genuinely empty active state, canonical vs opaque IDs, WR/CR/NR provenance, chunk boundaries/UTF-8, equal/stale/next revisions, removals/gap recovery, reconnect resync, rapid stop/resume, late selected-round replies, bounded retries, chat create/delete/error, exact ID/no-ID cases, legacy mode switch, verified website fallback, shared My Results/card/All Results, publication transitions and light/dark row metrics/pixels. Earlier focused runs exposed test-fixture compiler errors, unavailable unit-host SwiftUI accessibility enumeration and incomplete UIKit teardown; the fixture/inspection/lifecycle helpers were corrected rather than changing production UI to satisfy them. A transition color assertion was separated from its deliberately dimming result-card overlay.

Tests: `CubingChinaModernLiveTests`, `CubingChinaModernLivePresentationTests`, `CubingChinaLiveHTTPTests`. Final log: `/tmp/cubeflow-modern-live-goal/final-focused.log`; result bundle: `/tmp/cubeflow-explore-final-refinements/DerivedData/Logs/Test/Test-CubeFlow-2026.10.11_19-51-25-+0800.xcresult`. No broad suite ran.

**BUILD SUCCEEDED, exit 0**. Exactly one unsigned generic iOS Debug build ran after the production changes and final focused tests; no production code changed afterward. The app target remains iOS 15.0. The only warning was skipped AppIntents metadata extraction because there is no AppIntents.framework dependency. Tracked/touched-untracked whitespace checks pass; frozen Explore module, Competition Filter, global Recent Records merge and external project file match their starting hashes. The project SHA-1 remains `0aadcf8c7dd61852886cb8babdfd4ca5ff2ad70f`.

```sh
xcodebuild build -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/cubeflow-explore-final-refinements/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''
```

Build log: `/tmp/cubeflow-modern-live-goal/final-generic-ios-debug.log`. No commit or push.

Mounted native screenshots use full public archive fixtures and the real SwiftUI tree, not design mockups. Inspected light/dark results retain existing typography/cards, correct event glyphs and record flags, and subtle own-row emphasis. The existing WCA shared renderer is exercised without replacing its transport. Full competition mounts cover official and separate pink Live navigation plus the viewport result card. A mounted publication transition verifies [ordinary entry becomes official Results](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/publication-transition-official-default.png) and [explicit Live stays Live](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/publication-transition-explicit-live.png). Pixel assertions verify the row's drawing-only accent and unchanged 34-point shared-row height; they are not a substitute for physical taps or VoiceOver testing.

| Screen | Light | Dark |
| --- | --- | --- |
| Beijing native archive / WR / own row | [Light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/beijing-native-light.png) | [Dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/beijing-native-dark.png) |
| Guangzhou native archive / no invented WR | [Light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/guangzhou-native-light.png) | [Dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/guangzhou-native-dark.png) |
| Existing WCA renderer / own row | [Light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/wca-shared-own-row-light.png) | [Dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/wca-shared-own-row-dark.png) |
| Full published page / separate pink Live | [Light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/full-published-live-light.png) | [Dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/full-published-live-dark.png) |
| Existing viewport result card | [Light](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/full-published-live-card-light.png) | [Dark](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/cubingchina-modern-live-oct11/full-published-live-card-dark.png) |

## Limits And Next Step

1. On device, open Beijing/Guangzhou through ordinary competition entry and verify official Results remain default; then open the distinct pink Live destination and switch event/round repeatedly. Verify native rows and exact recent-record event/round/card targeting.
2. With a real signed-in WCA identity present in the displayed round, verify the restrained treatment and My Results/result-card/All Results taps in both providers. Sign out or use an unmatched identity and confirm no emphasis/shortcut. No rows should move or change height.
3. During an active competition, verify real result edits/removals and chat creation/deletion; disconnect/reconnect the network, background/foreground, switch round and leave/reopen Live. Confirm resynchronization without stale rollback, duplicates or lingering streams.
4. Check anonymous chat, failed-chat website handoff, and selected Live text/icon visibility during repeated appearance changes. The prior beta-simulator selected-label intermittency is not considered physical-device acceptance. iOS 15 runtime and VoiceOver remain physical checks; the app's deployment target stays iOS 15, while the existing focused test bundle requires iOS 26.2+.

Chat posting/authentication and modern provider extras such as podiums/sum-of-ranks are not implemented in this transport pass. Legacy extras retain their original behavior; unsupported modern extras are not exposed as empty native destinations. No WCA Live transport, global record discovery, Explore scrolling/edge effect/filter, Smart Cube, Combined, timing or unrelated UI work was changed.
