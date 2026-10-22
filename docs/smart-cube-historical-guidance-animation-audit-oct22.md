# Smart Cube Historical Guidance and Animation Audit

Date: 2026-10-22, Asia/Shanghai. Continued the existing dirty worktree; no commit, push, signed build, physical-device access, archive, upload, or authentication change.

## 1. Executive Summary

- **Proven animation defect corrected:** a new SwiftUI canonical snapshot could reach the renderer before its matching synchronous canonical move event. The snapshot consumed the sequence and snapped the scene; the subsequent executable turn was rejected as already consumed. This also affected isolated slow moves, not just backlog.
- A deterministic negative control failed before the correction. Actual mounted Settings, Timer and management-card renderers now retain their owners and show intermediate rotation during slow moves and parent publication. Physical acceptance remains outstanding.
- **Guidance P0 remains unresolved:** the exact penultimate-scramble fixture can reproduce long recovery accumulation. Valid routes and stationary model-to-view publication are verified, but the examined historical comparisons do not establish a lost better route or a culpable historical commit. No speculative solver change, forced equal replacement or budget increase was made.
- Discovery now has a genuine native large-to-inline title in the same card, passive offline rows, no empty-state prose and section-header refresh. The existing X is unchanged.
- Management title gains 16 pt previously lost to an extra spacer, without changing approved name/battery typography or close-button clearance.
- **Distribution is not cleared:** TNoodle runtime privacy purposes remain unknown, and its bare device dylib packaging conflicts with Apple's iOS bundle rules. OAuth remains an independently unresolved security/provider dependency.

Evidence root: `build/smart-cube-historical-audit-oct22/`. The starting tree's file hashes and relevant source copies remain in `baseline/`. This report distinguishes source defects, observed test behavior, hypotheses and physical unknowns.

## 2. Guidance History

Examined the full reachable relevant file history, including earlier Timer-owned implementations and later dirty controller code. The latter is not attributable to a committed last-known-good physical build.

| Revision / Implementation | Established Behavior | Classification |
| --- | --- | --- |
| `1844425d` | Timer-owned recovery task; exact bounded search up to three moves to known checkpoints, with epoch/source guards. A checkpoint route includes the remaining scramble suffix. | Historical algorithm difference; not proof of physical last-known-good. |
| `b0cf62dc` | Checkpoint recovery followed by native target search: first two-phase answer, depth 21, probe limit 1,000,000, no wall-clock deadline. Minimum correction three; strictly shorter adoption and an immediate-inverse penalty could suppress a one-move saving. | More permissive search time, but stricter adoption in some cases; not globally optimal search. |
| `8eb5369a` | Context-bound scramble prefetch. | Unrelated to a demonstrated better Guidance solver. |
| `4d83d3ed` | Retains the dual renderer authorities: canonical events and independently applied snapshots. Also contained the old six-turn animation drop. | Latent animation ordering hazard; the drop was already removed and stays removed. |
| `da9ad58d` | Timer/persistence/presentation work; no evidence of a different optimal Guidance solver. | Not an established Guidance regression commit. |
| Current controller | Latest-state requests; exact direct-target short lane; 120 ms trailing settle for bounded native work; cooperative cancellation; replay validation and ownership guards; primary 350 ms and improvement 100 ms budgets. | Intentional bounded scheduling difference; exact physical regression attribution unproven. |

The current native upper bound is based on a replay-valid normalized known continuation, capped at 21, not the total number of visible tokens. Completed gray history is excluded. No fixed 19/20-deviation adoption gate was found.

The old checkpoint-directed short lane is a meaningful source-level difference from the newer direct-target short lane. Tested reducible-history comparisons produced historical/current lengths 4/4, 7/7 and 11/11; they did not demonstrate that restoring it would fix the reported workflow. The final retained comparison uses an 11-move checkpoint route against a 35-move guaranteed inverse continuation. The current target search also finds 11.

Older unbounded native work is not safely restored merely because it might search longer. Earlier code checked cancellation around the synchronous call; current native work can stop cooperatively inside it. Main-thread responsiveness and obsolete-request ownership must remain protected.

## 3. Exact Penultimate-Scramble Fixture

The actual mounted `TimerTabView`, real routed peripheral session, canonical event feed, production Guidance controller and actual rendered Text probe are exercised. Only the settle clock is virtual; the native solver still executes. In-memory solve persistence and synthetic radio state prevent writes to user solves or physical BLE interaction.

Original 20-move scramble:

```text
R U2 F B R B2 R U2 L B2 R2 D F2 L2 U' B2 U2 L2 D F2
```

Execute the first 19 moves through `debugEmitPhysicalMove`; assert exact canonical prefix state, 19 completed tokens, final `F2` pending, unchanged original text and immutable target digest `ade169e11a6cc4f4`.

Two deviation sequences are retained:

```text
Mixed: U R F L B D R2 U' F2 L2 D' B2 R' U2 F' L' D2 B U L
Repeated: (R U R' U') repeated five times
```

At deviations 1, 2, 3, 5, 7, 10, 12, 15, 17, 19 and 20, advance the virtual settle clock by five seconds, wait for actual work completion, replay the displayed actionable route to the same immutable target, and compare actual rendered Text to that selected route plus appropriate completed history. Screenshots and full bounded diagnostic TSV are attached to the test results.

The fixture checks the current state and original scramble on every checkpoint, not a solved-state substitute. The trace includes request/revision, source/target digests, raw/calculated/selected paths, shown cost, decisions and native timing. The existing bounded ring remains unchanged; it is not an unlimited audit log.

## 4. Observed Guidance Results

The following reproducible observations agree in `ui-guidance-final.log` and the passing `focused-complete.log`, after correcting virtual-clock cancellation bookkeeping. Costs are actionable HTM only; the 19 dimmed originals do not enter the comparison.

| Deviations | Mixed: Before -> Selected | Repeated: Before -> Selected |
| --- | --- | --- |
| 1 | 2 -> 2 | 2 -> 2 |
| 2 | 3 -> 3 | 3 -> 3 |
| 3 | 4 -> 4 | 4 -> 4 |
| 5 | 6 -> 6 | 6 -> 6 |
| 7 | 8 -> 8 | 8 -> 8 |
| 10 | 11 -> 11 | 11 -> 11 |
| 12 | 13 -> 13 | 13 -> 13 |
| 15 | 16 -> 16 | 16 -> 10 |
| 17 | 18 -> 18 | 8 -> 8 |
| 19 | 20 -> 20 | 6 -> 6 |
| 20 | 21 -> 20 | 5 -> 5 |

For the mixed case, gray=19 and orange=19 still occur at deviation 19. At 20, a verified 20-move replacement reaches the actual Text view without another turn. For the repeated case, replacement at 15 resets recovery history; subsequent moves advance within that replacement. Thus later selected costs 8/6/5 are not all new solver adoptions.

This establishes the reported long-path behavior in a realistic workflow, **not its historical cause or satisfactory proactive performance**. Tests intentionally verify invariants and actual publication rather than demand a mathematically unjustified improvement at every checkpoint.

## 5. Same-State Native Comparison

Existing native modes were compared on identical repeated-sequence source/target states with a 100 ms bound per call. This is an investigation control, not a change to production's 350/100 ms policy.

| Deviations | Known Bound | Current-Bound First Answer | Historical Depth-21 First Answer | Optimal Mode Limited to Depth 8 |
| --- | --- | --- | --- | --- |
| 5 | 6 | 6 | 16 | 6 |
| 7 | 8 | 8 | 16 | 8 |
| 10 | 11 | 11 | 15 | No answer |
| 12 | 13 | No answer | 19 | No answer |
| 15 | 16 | 14 | 17 | No answer |
| 17 | 18 | 16 | 16 | 8 |
| 19 | 20 | 6 | 6 | 6 |
| 20 | 21 | 5 | 5 | 5 |

These observations are retained in `guidance-baseline.log`. Each nonempty answer is replay-checked. Warmed first-answer search is not globally optimal; finite optimal-mode failures do not prove a distance lower bound. At seven repeated deviations, exact depth-eight search returns eight: forcing an equal replacement would not shorten that route. The separate production improvement pass can beat the isolated first answer (for example, 14 down to 10 at deviation 15).

The mathematical global HTM diameter of the legal 3x3 state space does not guarantee an interactive bounded implementation will return an optimal route on demand. No broad optimal-search mode was enabled.

## 6. Adoption, Recovery and Unresolved Cause

Current simplification handles adjacent cancellation, same-face composition and commuting opposite-face reductions. Composed correction plus remaining work is replayed and compared against the candidate; inverse recovery is not counted separately from the actionable continuation. Replay-valid equal routes stay stable; verified strictly shorter routes are eligible without a legacy savings penalty.

The exact fixtures demonstrate that work starts, returns and publishes while stationary. The repeated case adopts at 15; the mixed case adopts at 20; actual Timer Text agrees with the selected route. No selected-but-unpublished or published-but-stale stationary UI failure was reproduced for these controlled targets.

Cancellation/supersession is distinguishable through controller request ownership and obsolete-result guards. Invalid candidates are rejected by exact replay. However, the bridge's empty result does not expose every native termination reason: an empty bounded call cannot honestly be labeled specifically deadline, probe exhaustion or no solution merely from elapsed milliseconds. Existing native timing is supporting evidence, not proof of a particular exit condition.

The old physical export remains the same 2,014-entry capture already audited in the October 21 report (SHA-256 `2aea3af5e841da18b063b6ea8b3c10b2076b1afe3ce3ea0fd5929b0f90726169`). It is not a newly supplied capture of this penultimate scenario. No physical last-known-good version, newly rejected better historical route or exact solver regression was established.

**No production Guidance change was justified in this pass.** The missing checkpoint-directed lane remains a hypothesis, not an approved fix. Do not interpret passing replay/publication tests as P0 closure.

## 7. Proven SceneKit Ordering Defect

The canonical feed delivers subscribers synchronously. An earlier model subscriber can update SwiftUI before a later renderer subscriber receives that same event. The old path was:

```text
turn N -> model publishes facelets N -> updateUIView(snapshot N)
       -> resync / lastSequence=N -> renderer receives event N
       -> event rejected as already consumed -> no intermediate turn
```

This is the opposite ordering of the previously fixed stale-snapshot race. Fencing old snapshots after newer events did not protect a new snapshot arriving before its event.

The deterministic negative test installs the model subscriber first and invokes the real coordinator update from that subscriber. One slow `U` previously left no active turn. Actual mounted controls independently found Settings animating while Timer intermittently lost its slow turn, despite a live window, enabled renderer, active clock, trusted state, contiguous sequence and 4 TPS.

Subscription ordering is a supported mechanism; different mounted subscriber lifetimes can explain intermittent surface differences. Its complete contribution to the user's physical symptom remains unquantified.

## 8. Renderer Correction and Boundaries

`SmartCube3DView.Coordinator` now stages a sequenced live snapshot that could preempt pending event delivery. It neither consumes the sequence nor clears the animation queue immediately. One bounded, generation-guarded next-main-queue work item reconciles only after synchronous delivery has completed.

If the matching/newer canonical event arrives, it consumes the executable move normally and supersedes the pending snapshot. If no event arrives, the snapshot still becomes an authoritative resync; no synthetic move is invented. Rebinding and stop cancel pending work, preventing cross-attempt application. Weak ownership avoids extending coordinator lifetime.

This is an event-delivery ordering fence, not a wall-clock animation delay or new render timer. Existing clock frequency, turn duration, TPS policy, ordered queue and exceptional overflow handling are unchanged. `CubeTurnPresentation.swift` matches the starting baseline exactly. Window/visibility ownership remains intact; hidden owners still synchronize without replaying invisible backlog.

Tests inspect actual intermediate SceneKit pivot angles, retained view/coordinator identity and final canonical state. The mounted Settings -> Timer -> management sequence sends `U U U2 R F' L2` at 4 TPS and triggers parent publication during animation. Other focused tests cover rapid mixed input, high-frequency backlog, stale snapshots, eventless authority, rebinding, two independently mounted renderers, visibility and authoritative boundaries.

## 9. Discovery Presentation and Interaction

The embedded picker uses the existing compatible navigation container and native `.large` title, localized through `Text("smart_cube.title")`. The List drives native collapse to inline. The standalone picker retains its prior inline Devices title and scan toolbar. No new sheet, custom title interpolation, decorative scroll-edge imitation or minimum-OS increase was introduced.

The existing outer card and top-right X are unchanged. Actual mounted navigation tests measure the real navigation-bar height changing on scroll, one navigation stack and no nested presentation. Captured large/inline and empty-section screenshots are retained.

Screenshot follow-up: the original review missed that the large title touched the card edge. A mounted pixel/OCR regression measured native navigation-bar, navigation-view and system minimum margins all at zero, with title ink only 0.066 pt inside the card. `SmartCubeDiscoveryNavigationInsets` now sets only the embedded card's native navigation-bar directional margins to at least the existing 22 pt card content inset, restoring previous values on teardown. Actual title ink measures 22.31 pt after correction. The native title/font/collapse logic, List width/insets and outer X are not replaced or repositioned. The standalone picker receives no configurator. No global appearance change or private UIKit title access is used.

Offline saved rows previously contained a real `NavigationLink` in an externally presented card. That link could target the surrounding navigation owner behind the card. It is now removed, not merely made visually chevron-free: the row is plain content. A genuinely discovered/eligible saved device keeps its existing explicit Connect button. Connected rows retain the same-card management callback and do not change Active implicitly.

Other Devices has no instructional empty message. Its header contains a native trailing refresh symbol and localized scan accessibility label, calling the existing `startScanning()`. No added scan timer, poller or identity reset. Existing UUID filtering, same-name distinct devices, connection progress and retry/auto-connect ownership remain unchanged.

Mounted tests establish native navigation and same-card connection/failure/retry/reconnect. Discovery model tests cover connectability, identity and active-state rules. These are not physical touch-routing tests: passive-row taps, refresh interaction and real Bluetooth results still need manual acceptance.

## 10. Device Name Geometry

The name/battery HStack already had 12 pt spacing but also contained `Spacer(minLength: 4)` between them, adding another spacing slot plus minimum spacer. Removing that spacer recovers 16 pt. Name now takes the legitimate remaining proposal with leading alignment, one line, tail truncation and layout priority.

At a 393 pt viewport and 361 pt card: content insets 44 total, close clearance 38, inter-item gap 12, battery 49, leaving name width 218 pt rather than 202. Name remains 24 pt bold; battery remains 23 pt medium monospaced digits. Cube placement, buttons, close reservation and glass surface are unchanged.

Mounted SwiftUI measurement gives `GAN16 MagLev Pro` width 215.33 pt: it fits now but did not fit the old 202 pt proposal. OCR confirms the full name and 76% battery. `GAN 16 MagLev Pro` is actually 220.33 pt and legitimately truncates at this viewport. UIFont's 218.16 pt estimate was not a reliable substitute for actual SwiftUI text measurement; the test was corrected rather than shrinking production type.

DEBUG measurement callbacks are opt-in; no GeometryReader is mounted for ordinary management cards unless the test environment supplies a metrics sink. No measurement-driven production sizing loop was introduced.

## 11. TNoodle: Binary and Runtime Evidence

The frozen device binary is `Vendor/TNoodleLibNative.xcframework/ios-arm64/lib-scrambles.dylib`: 37,867,808 bytes; SHA-256 `35ca5611930688d63e6e43b9e2a5d49d6c9dec08ca54a98a136645ce454b4103`; Mach-O UUID `D2D6B149-54E0-319A-BAFA-6A8A55C0AA73`; minimum iOS 11, SDK 16.2. It first appears in foundation commit `49a6967e`. File timestamps are not a reproducible build provenance chain.

Embedded Maven metadata identifies `scrambler-min2phase` 0.18.1; this does not prove the entire native binary corresponds to an unmodified upstream release. No exact native-image build recipe, Graal version, flags, custom entry-point source, reachability metadata or SBOM was found. The [official upstream project](https://github.com/thewca/tnoodle-lib) provides Java/Gradle sources, not a proven reproducible replacement for this iOS binary. Graal's [shared-library guide](https://www.graalvm.org/latest/reference-manual/native-image/guides/build-native-shared-library/) explains C entry points and generated headers, but is not itself an iOS cross-compilation recipe.

Imports include stat/fstat/lstat, mach_absolute_time and fstatvfs. Disassembly additionally confirms call instructions, including fstatvfs at `0x5ce2f8` to stub `0x5d5b8c`; `tnoodle-call-sites.txt` retains the evidence. Stripped internal labels do not establish which high-level Java operation reaches them or their purpose. This is stronger than an import-only finding, but still not an actual runtime trace.

The device bridge creates/attaches the Graal isolate and invokes the scramble entry; Simulator uses a stub. Simulator success therefore cannot prove device runtime privacy behavior. Disk capacity, timestamp and uptime execution/purposes during actual initialization or scramble generation remain unproven. No binary execution, modification or rebuild was performed here.

## 12. TNoodle: Confirmed Packaging Risk and Remediation

The current `Sign TNoodle Runtime` build phase copies the bare dylib to the app root, not a framework bundle. The XCFramework label does not make that product a valid dynamic framework. Apple's [bundle placement rules](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle) explicitly disallow third-party standalone dylibs on iOS, with an exception for Xcode's Swift system libraries. This is a concrete distribution-structure risk independent of the unknown Required Reason API execution.

Apple's [required-reason declaration rules](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) also require accurate declarations for SDK code; the app manifest is not evidence of the SDK's purposes. TNoodle/Graal is not named on the currently inspected [listed SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/); absence from that list does not waive general API/privacy or packaging obligations.

The existing app manifest remains unchanged: UserDefaults CA92.1, FileTimestamp C617.1, SystemBootTime 35F9.1/3D61.1. No speculative DiskSpace reason was added.

Before TestFlight: obtain exact build provenance and vendor/runtime-purpose evidence; separately authorize device tracing of isolate initialization and representative scramble calls; obtain appropriate SDK declarations. Prepare a properly structured/signed `TNoodle.framework` with Info.plist and SDK manifest plus correct loading/install paths, or a justified reproducible rebuild after permission. Merely placing a manifest beside the bare dylib or renaming its extension is not remediation. Neither packaging nor binary was changed in this pass.

## 13. WCA OAuth: New Deployed Evidence

Safe unauthenticated GETs to WCA's [OpenID configuration](https://www.worldcubeassociation.org/.well-known/openid-configuration) and [authorization-server metadata](https://www.worldcubeassociation.org/.well-known/oauth-authorization-server) returned HTTP 200 with identical JSON, preserved in `research/`. No authorization attempt, login, code exchange, token exchange or registration access was made.

The deployed metadata advertises authorization_code and refresh_token among its grants. Token authentication methods are `client_secret_basic` and `client_secret_post`. It does **not** advertise `none` or `code_challenge_methods_supported`. These are deployment-advertised facts, not proof that a separately provisioned public client or S256 request is rejected or securely enforced.

Previously pinned [WCA schema](https://github.com/thewca/worldcubeassociation.org/blob/7961dc8453530ef827d2c35d7c3b5d9972c362f7/db/schema.rb) lacks grant challenge columns; its [initializer](https://github.com/thewca/worldcubeassociation.org/blob/7961dc8453530ef827d2c35d7c3b5d9972c362f7/config/initializers/doorkeeper.rb) and registration controller do not establish public-client self-service. Version-matched Doorkeeper [grant model](https://github.com/doorkeeper-gem/doorkeeper/blob/v5.9.9/lib/doorkeeper/models/access_grant_mixin.rb) and [code exchange](https://github.com/doorkeeper-gem/doorkeeper/blob/v5.9.9/lib/doorkeeper/oauth/authorization_code_request.rb) condition verifier validation on model PKCE support. Framework capability is not deployed-provider confirmation.

The [WCA API help](https://www.worldcubeassociation.org/help/api) and [legacy OAuth documentation](https://docs.worldcubeassociation.org/knowledge_base/v0_api.html) describe secret-bearing flows, not a verified native S256 migration. Production authentication stays frozen: ASWebAuthenticationSession and Keychain retained, embedded-secret and missing attempt-state/callback validation concerns unresolved. No credential value was printed, copied, rotated or revoked.

## 14. OAuth Architecture and Provider Questions

Prefer a native public client **if WCA confirms and verifies** S256 enforcement and usable public-client registration. Per-attempt random state, S256 verifier, strict expected callback, one-time consumption and cancellation/replay handling belong to the native flow; credentials stay out of the binary, tokens stay in Keychain. [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252) treats distributed native apps as public clients; an embedded shared secret cannot provide confidentiality.

Doorkeeper's version-matched [URI checking](https://github.com/doorkeeper-gem/doorkeeper/blob/v5.9.9/lib/doorkeeper/oauth/helpers/uri_checker.rb) checks registered redirects, including scheme/path/query rules and loopback exceptions. Framework acceptance of a custom scheme does not prove WCA registered CubeFlow's exact redirect or make that scheme exclusive. The [refresh implementation](https://github.com/doorkeeper-gem/doorkeeper/blob/v5.9.9/lib/doorkeeper/oauth/refresh_token_request.rb) binds refresh to the issuing client; a new client is not automatic token migration.

If native public S256 is unavailable, a confidential backend exchange at `api.cubeflow.com.cn` is a conditional architecture option, not an already deployed service. Server owns provider state/callback and client secret; the app gets an attempt-bound, verifier-protected, short-lived one-time handoff, never WCA tokens in a URL. Provider refresh credentials stay encrypted server-side; native app credentials stay in Keychain. This adds security/operations/network/privacy dependencies and remains subject to explicit backend authorization and the ICP gate.

Both migrations need an existing-user plan: old-client token compatibility must be confirmed; a new client likely requires reauthentication. Coordinate retirement/rotation, supported-build cutoff and token revocation with WCA. Secret rotation does not establish revocation of all existing tokens. Do not ship a replacement secret in the next native binary or rewrite history without separate approval.

Questions for WCA Software Team:

1. Is S256 PKCE enabled and enforced in production, including rejection of missing/wrong verifier and downgrade attempts?
2. Can CubeFlow register a genuinely non-confidential native client, and which registration process enables it?
3. Can that client exchange code and refresh tokens without a secret; what rotation/reuse rules apply?
4. Which exact custom-scheme or claimed-HTTPS redirects are supported, and what matching constraints apply?
5. Can the existing registration be converted, or is a new client required; what happens to existing grants/tokens?
6. What do secret rotation, application revocation and individual token revocation actually invalidate?
7. If needed, can an HTTPS backend callback be registered with the same required scopes and supported flow?

## 15. Files and Verification

Changes relative to this pass's preserved baseline:

- Production: `SmartCube3DView.swift`, `SmartCubeLabView.swift`, `SmartCubeDiscoverySections.swift`, `SmartCubeManagementCard.swift` under `CubeFlow/Views/iPhone/`.
- Updated tests: `SmartCubeAnimationRegressionTests.swift`, `SmartCubeDevicePolishTests.swift`, `SmartCubeSolverAuditTests.swift`, `SmartCubeTimerIntegrationTests.swift`.
- Added test: `CubeFlowTests/SmartCubeMountedRendererTests.swift`.
- Added this report.

No production Guidance/controller/solver changes in this pass. Project/signing/version configuration, OAuth, TNoodle binary, app manifest, canonical presentation engine, unrelated competition/Explore code and existing X implementation are preserved.

Final focused run: **88 XCTest plus 37 Swift Testing tests, 125 total, zero failures**, exit 0. Evidence: `focused-complete.xcresult`, `focused-complete.log`, `focused-complete.exit`. This includes actual mounted renderer/Timer tests, native title/name screenshots, management/HUD/discovery, lifecycle/ownership/current/latest Guidance, native comparisons, replacement policy, ordered presentation and scramble persistence. Counts are from the final run, not sums of reruns.

The **one authorized unsigned generic iOS Debug build passed**, exit 0: `final-generic-debug.log` / `.exit`, destination `generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO`. No second generic build was launched. The only build warning is skipped AppIntents metadata extraction without an AppIntents.framework dependency. Simulator runtime WebKit process-assertion messages are retained in test logs and did not fail tests.

Coverage boundary: that generic build and the 125-test run preceded the user's additional large-title padding correction above. The padding follow-up is compiled/verified by focused simulator tests; it is not represented as covered by another generic device build. No additional generic build was run.

Padding verification: 19 distinct relevant cases pass across `title-inset-final` (18 passing cases) and the final targeted `title-inset-restored` rerun (the remaining navigation case). Measured initial and restored large-title ink insets are both 22.31 pt; native bar height collapses from 106 to 54 pt and returns to 106 pt. Final screenshots in `title-inset-images/` were visually inspected. The return-to-top test must reveal the actual collapsed title extent, not stop at the smaller inline inset; this is test driving only, not production scroll compensation. An initial UILabel introspection assumption was replaced with actual OCR/pixel geometry. The measured pre-fix inset regression failed as expected at 0.066 pt in `title-inset-measure`. Earlier return-fixture failures remain retained rather than counted as successful runs.

After this follow-up, exactly three of the frozen 7,382 source/configuration files differ: `SmartCubeManagementCard.swift`, `SmartCubeLabView.swift` and `SmartCubeDevicePolishTests.swift`; the other 7,379 remain identical. Only the local navigation-inset correction and its tests changed since the successful generic build. `git diff --check` remains clean; no physical-device check, commit or push occurred.

All **7,382 source/configuration hashes** match before versus after the final build. Compared with this pass's starting baseline, **7,576 files remain unchanged, eight scoped existing files changed and none are missing**. The mounted-renderer test and this report are additions. Project configuration, OAuth, manifest, vendor binary, Guidance production code, `CubeTurnPresentation.swift` and unrelated dirty changes remain byte-identical to baseline.

The final device `.app` contains the unchanged app manifest and original TNoodle dylib, both byte-equal to their sources. Manifest and English/Simplified Chinese/Traditional Chinese Localizable.strings pass `plutil -lint`. This confirms packaging contents, not TNoodle privacy compliance. `git diff --check` and additional no-index whitespace checks for untracked scoped files produce no diagnostics. No task-owned build/test process remains active.

Reviewed actual final screenshots, not only OCR: native expanded and inline titles, passive rows, empty Other Devices header/refresh, fitting name with battery, and Timer Guidance at deviations 7/19/20. They are in `final-images/`; `manifest.json` maps test names to exact attachments. The 19-deviation image visibly retains completed gray history and orange correction; the 20-deviation image visibly shows the adopted replacement. No physical acceptance is inferred.

Earlier failures remain visible in the evidence, not counted as success: deterministic pre-fix snapshot race; actual mounted slow Timer failures; an async XCTest autoclosure compilation issue; lazy-List end-scroll fixture positioning; virtual settle cancellation bookkeeping; and an invalid UIFont-based name-fit assumption. The latter three were test-harness defects, not changes to production scroll or solver behavior.

The virtual clock now releases already-advanced settle registrations, preventing a cancelled prior waiter's presence from falsely standing in for the current task. Real production settle/cancellation semantics are unchanged. Final source tests retain exact replay, actual rendered Text and real intermediate-angle assertions.

## 16. Manual Physical Acceptance

1. Run this source manually in Xcode. Connect normally under the established state policy; do not use Mark Solved solely to force a fixture.
2. Open same-card discovery from Timer. Check native large title, native collapse/restore, unchanged X, empty Other Devices with working refresh, passive offline rows, only eligible Connect and same-card connected management. Browsing must not change Active.
3. Compare a fitting device name and a genuinely long alias at narrow/wide widths, with and without battery. Preserve approved type and close-button clearance; genuine overflow may truncate.
4. At low TPS perform slow `U`, pause, `U`, pause, `U2`, then `R F' L2` in Settings, Timer and management. Observe intermediate angles; repeat after Settings -> Timer, card open/close and a normal reconnect. Boundary resync remains intentionally a snap.
5. For the open Guidance P0, use the printed 20-move original, execute exactly 19 moves and record the visible pending F2. Start the existing Guidance capture and screen recording; perform the mixed sequence, pausing after 1/2/3/5/7/10/12/15/17/19/20. Include stationary time at seven. Preserve screen evidence plus capture so the current original/target/request digests and actual pixels can be correlated. This is a focused acceptance reproduction, not a claim the solver now improves earlier.
6. Check ordinary Smart Cube solve/save/next assignment and stored original scramble/reconstruction remain correct. No device action was performed by the agent.

## 17. Outstanding Blockers

- **Unresolved P0:** historically proactive Guidance quality for the exact long mixed-deviation workflow; no demonstrated safe solver restoration yet.
- **Unverified physical behavior:** elimination of Timer/card snapping and native discovery touch behavior on the user's iPhone/iOS build. Simulator evidence is not physical acceptance.
- **Proven packaging defect and unknown SDK runtime use:** TNoodle's bare dylib structure and missing attributable Required Reason API purposes/declarations must be resolved before distribution clearance.
- **External provider/security dependency:** verified WCA public-S256 support or separately approved backend-assisted migration, plus state/callback hardening and credential retirement planning.

Passing Debug compilation is not TestFlight readiness. No distribution or production authentication changes are authorized or claimed.
