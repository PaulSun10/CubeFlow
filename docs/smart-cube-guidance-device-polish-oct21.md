# Smart Cube Guidance, Device Polish, Privacy and OAuth

Task dated 2026-10-21; final verification completed 2026-10-22, Asia/Shanghai.

## Status and Scope

Continued the existing dirty worktree after reading the recovery report, earlier regression/Guidance reports, production code and relevant Git implementations. No physical device access, signing/account setup, archive, upload, distribution, commit, push, revert, reset or cleanup. The preceding accepted changes were not restarted.

Implemented the unified management/discovery card, name fitting, connection-success feedback, Timer battery weight and renderer visibility ownership. Added the app Privacy Manifest and audited WCA OAuth without changing it.

**The reported physical 7-to-19-turn Guidance stall is not established as resolved.** Actual Timer regression fixtures now demonstrate stationary adoption, including 28-to-19 HTM after seven deviations, but do not reproduce the user's failure. No speculative solver-budget, cost-gate or target change was made. Likewise, renderer lifecycle defects are corrected, but intermittent physical stutter remains an acceptance gate. This is not first-TestFlight release approval.

## Unified Device Card

Previously Timer's disconnected entry routed to a separate picker sheet, while the connected-only card either rendered its empty fallback or replaced a disconnected selection with another connected cube. Neither implements the requested same-card transition.

The existing `CompetitionNativePresentation` and management surface remain. `SmartCubeManagementCard` now embeds the existing `SmartCubeDevicePickerView` in its disconnected branch. Both that picker and Settings continue using `SmartCubeDiscoverySections`; there is no new BLE state machine or parallel list implementation.

- Timer's compact device row and cube tap open this card even with no connection. Their previous separate-picker route is no longer selected by these entry points.
- An explicit managed UUID remains the managed identity when disconnected. It does not fall back to another connected device or change Timer Active. An initially unspecified selection may use the existing preferred connected identity.
- Connecting/failure/retry stay in the card's native list. Other Devices now displays progress and disables another Connect while its session is connecting; saved rows retain the existing eligibility rules.
- The connected body appears after that session's existing connection policy is resolved. This keeps the picker alive to handle its existing Keep State/Reset/prompt flow instead of removing its handler prematurely.
- Embedded picker approvals update the parent's selected identity, not `dismiss()`. Its separate management presenter is inactive in embedded mode. The outer card supplies its existing close button; discovery keeps a native Scan control.
- Disconnect/Forget remain existing manager operations. Disconnect preserves saved associations. Forget retains confirmation and removes only the selected association. Existing Many Connected/One Active reconciliation is untouched; the card does not invent another selection policy.
- Automatic reconnection of the managed identity returns the same card to its connected body. Selecting a different connected row is explicit inspection, not Active selection.
- Settings retains its existing discovery page and opens this same management card for connected entries. A card opened there now also transitions to embedded discovery on disconnect, instead of opening a discovery sheet.

Tests mount the real card through disconnected, connecting, failed, retry, connected, disconnected and reconnected phases and assert the host survives with no nested presented controller. Two-device tests verify that disconnecting an inactive managed cube leaves the other connection/Timer Active untouched. These simulate session transitions, not radio discovery or real connection callbacks.

### Name and Battery

The name previously accepted a multiline size proposal in the title HStack. It now uses one line, trailing truncation and layout priority 1. The battery retains its existing fixed intrinsic size, and the Spacer yields remaining width. No font shrinking or new fixed width was introduced.

- Management name: unchanged 24 pt bold Results title styling.
- Management battery: unchanged 23 pt medium, monospaced digits.
- Compact Timer battery: subheadline **regular -> medium**, same size and monospaced digits, matching the device name's subheadline medium.
- Management padding, centered 190 pt cube surface, Reset/Disconnect/Forget button styles, colors and confirmations are unchanged.

Mounted Light/Dark title/battery/button screenshots and real multi-device Menu typography tests pass. The rendered `GAN 16 MagLev` name fits beside 76% on one line. Long/narrow names truncate rather than wrap or shrink. Accessibility-size physical inspection remains advisable.

## Connected HUD

History identifies the disappearance: `b0cf62dc` called the existing success HUD in Timer's readiness branch; `da9ad58d` replaced it with the explicit comment that ordinary connection/switch success is quiet. There was no process-level success replacement, and a Timer-owned announcement alone cannot cover every Settings or automatic connection.

The manager now owns success feedback immediately after its real `didConnect` has been accepted by the peripheral session. `announceConnectionSuccess` requires a connected session and an attempt UUID, then deduplicates by device UUID plus attempt UUID. It calls the existing localized `ScreenTransientFeedback.showSuccess`, not a new banner. Manual and automatic/restored connection paths converge here. Discovery, start, Active changes, view appearance and rerenders do not call it. Forget clears the corresponding association's announcement marker.

The HUD says Connected, not observation-ready. Existing policy, authoritative-state, readiness and timing gates are unchanged. Duplicate callback/attempt suppression, reconnection with a fresh attempt, disconnected attempts, multiple identities and unrelated view invalidations are tested through the same production announcement function. Actual foreground HUD delivery after manual/automatic BLE success remains a physical check.

## Guidance Investigation

### Model and Adoption Rules

The immutable target remains the original assigned scramble state. The latest accepted canonical source is distinct from the original target, accumulated inverse history, displayed route and solver candidate.

Recovery is a valid fallback, not a shortest-path claim. It is extended from the newest canonical move and simplified using the existing adjacent inverse cancellation, same-face composition and commuting-opposite-face simplification. A fallback's correction plus remaining original tokens is replay-verified before comparison.

The existing controller has an independent exact-at-most-three lane, a 120 ms trailing settle, one cooperative native worker and a replaceable latest request. A cancelled obsolete worker retains its slot until return, then drains the final settled request without another turn. Native state-to-state search is off the main actor. Its existing limits remain 350 ms primary and 100 ms tighter improvement, with depth bounded by 21 and any verified known upper bound. First-time table initialization and scheduler delay are separate from search time.

The normal native lane is bounded two-phase search, **not globally optimal HTM search**. A valid known path can beat its result or survive an unavailable bounded search. Exact <=3 results have a shortest-path guarantee within that proven result. No general shortest-path promise is made for a 19/20 HTM result.

The preceding displayed-versus-normalized cost fix is retained: compare a candidate with the actual submitted/displayed continuation, not an internally shortened route that has never reached the screen. Keep an equally short valid continuation; publish a strictly shorter verified route. Timer still requires matching device, epoch/revision, current source, immutable target, generation, trust and eligible non-running/non-inspecting lifecycle. No guard was relaxed in this pass.

### Physical Evidence and Limits

The accessible physical export at `/Users/paulsun/Downloads/Untitled.txt` remains the same previously analyzed file, SHA-256 `2aea3af5e841da18b063b6ea8b3c10b2076b1afe3ce3ea0fd5929b0f90726169`. It is not a post-latest-fix capture of the new 7/12/17/18/19 report.

Its complete 2,014 rows contain 97 contiguous decoded/routed/consumed moves, 152 valid displayed paths, 58 candidate arrivals, 56 valid-continuation reuses and two adoptions. Maximum native primary/improvement times were approximately 350.330/100.364 ms, and native queue wait 0.00867 ms. That does not demonstrate a 19-turn input threshold. The old file lacks the new shown/raw/normalized/selected notation and original visible-scramble affinity required to decide whether each reuse was appropriate. Its old view-context callback limitation was already fixed previously.

**No new source-level loss or incorrect shorter-candidate rejection explaining this latest physical stall was reproduced.** A five-second wait is long enough for these configured lanes under normal service, but cannot make bounded search prove a better answer. Conversely, a long valid fallback does not prove no shorter solution exists. The missing physical distinction is whether search found no improvement, a valid improvement was rejected, or an adopted path failed to appear. The current code and old evidence cannot truthfully select one of those explanations.

This pass did not merely stop after new logging: it fixes independent device/presentation/rendering defects and adds actual Timer multi-revision verification. It also corrects one diagnostic ambiguity: `candidate-evaluated` now retains raw native tokens separately from adjacent-normalized `calculated` tokens. The prior calculated field was already normalized, not raw. Path evidence remains bounded and DEBUG-only. This is not represented as the Guidance root-cause fix.

### Actual Timer Stationary Regression

Mounted the production Timer with in-memory persistence, a routed canonical session, the production controller/planner/native solver and a deterministic virtual settle clock. Original target:

```text
R U2 F B R B2 R U2 L B2 R2 D F2 L2 U' B2 U2 L2 D F2 U
```

Physical-input fixture:

```text
U R F L B D R2 U' F2 L2 D' B2 R' U2 F' L' D2 B U
```

At 7, 12, 17, 18 and 19 turns, advance virtual settle time five seconds with no new move. Wait for actual native work and Timer adoption. Verify exact current-source-to-original-target replay, unchanged original scramble, generation, and the text produced by the mounted production Guidance view, not only a controller publication.

| Stop After | Source Digest | Displayed Before | Raw / Normalized / Selected HTM | Generation |
| --- | --- | ---: | --- | ---: |
| 7 | `6f0f00a8c890f0e` | 28 | 19 / 19 / 19 | 1 |
| 12 | `e7a70af95dd432ee` | 24 | 20 / 20 / 20 | 2 |
| 17 | `3d52f7cacb2c43fe` | 25 | 20 / 20 / 20 | 3 |
| 18 | `8f42f28641ba5d22` | 21 | 20 / 20 / 20 | 4 |
| 19 | `eaf73258e6801eba` | 21 | 19 / 19 / 19 | 5 |

Target digest is `2c703811e711695a` throughout these revisions. Every selected route replays exactly. These are best verified bounded candidates, not proven global optima. Schedule-to-adoption measurements in the final fixture were roughly 75-160 ms with virtual settle released; they are not physical-device latency guarantees or a real five-second idle benchmark.

The first adopted screen text is:

```text
L2 R D F2 D2 F2 L2 U' R2 B2 D L' D2 U F2 L B D' L'
```

Final fixture screenshots disable SwiftUI animations **only in the test's root transaction** so a mid-transition draw is not mistaken for a final text screenshot. Production animation is unchanged. The test app's existing background Timer owner can also emit diagnostics, so fixture conclusions are scoped by the controlled target/owner rather than raw process-wide event totals.

Existing focused tests additionally cover cancellation/composition, the actual 4-to-2 displayed-cost regression, valid equal retention, strict one-move improvement, late stationary publication, obsolete/out-of-order completion, device and target changes, and immutable original-target replay. The existing native optimal mode was compared against bounded two-phase mode on three seven-move relative fixtures: both returned valid seven-move paths; warmed calls were about 0.46-0.54 ms, with the first non-optimal call including initialization about 114 ms. These easy fixtures do not justify enabling global optimal search for arbitrary interactive states. No solver architecture, budget or scheduling policy changed.

## Renderer Lifecycle

Settings, management and Timer reuse `SmartCube3DView`, but their mounted lifetimes differ. Timer conditionally removes its cube when its tab becomes inactive. Presenting a native management overlay does not remove the underlying Timer cube. The coordinator previously started its repeating 120 Hz Timer in `makeView`, independently of window attachment, and `SCNView` rendered continuously until dismantling. Thus hidden/covered owners could continue consuming render/main-thread work. This is a proven ownership defect; its contribution to the exact physical intermittent symptom is not quantified.

The SCNView now reports window attachment to its coordinator. The existing animation clock and continuous playback run only while window-attached and explicitly enabled. Timer disables its underlying cube while its management card is presented. No second timer or replacement animation engine was added.

Canonical subscriptions and sequence fences remain independent from rendering. While previously mounted but hidden/disabled, new canonical moves synchronize the authoritative state rather than accumulate an invisible animation backlog. On remount/uncover, resume from that latest state, then animate subsequent moves normally. Stop clears the window callback, clock and subscription and cannot be resurrected by an old view's reattachment. Off-window deterministic coordinator fixtures may still manually drive render ticks; they do not start a live timer.

The two-mounted-renderer test verifies independent clocks, card-covered Timer suspension, card removal/remount, canonical correctness throughout, no hidden replay and subsequent intermediate half-turn angles. Existing rapid mixed/24-turn tests, stale snapshots, trust/boundary/rebinding, disposal and single-card subscription tests pass. `CubeTurnPresentation.swift` is byte-identical to this pass's baseline: no six-turn dropping was restored; continuity, 128 exceptional overflow bound, existing TPS/duration and ordinary visible ordered animation remain.

Physical display cadence, thermal load, BLE delivery and main-thread contention while Guidance runs remain unmeasured here. Do not interpret deterministic tests as elimination of physical stutter or a redesign of gyro following.

## Privacy Manifest

Added the app's `PrivacyInfo.xcprivacy` through its existing filesystem-synchronized target group. No project/configuration edit was required. Confirmed the simulator test bundle lookup and final generic-device `.app` both contain it; final bundled bytes equal the source and `plutil` passes. Minimum app OS remains 15.0.

| Category | Reason | Actual Use |
| --- | --- | --- |
| UserDefaults | `CA92.1` | Own-app settings/AppStorage and saved-device/profile preferences; no external app/global-domain preference access found. |
| FileTimestamp | `C617.1` | Own cache files: `PublicDataSnapshotStore` modification-date metadata and `CompetitionSnapshotCache` eviction metadata. |
| SystemBootTime | `35F9.1` | Elapsed timing, turn presentation, Guidance/protocol timing and app event intervals. |
| SystemBootTime | `3D61.1` | Optional DEBUG bug reports containing system-uptime timestamps, copied only at the user's choice. Not a claim of a Release diagnostic UI. |

Reasons were checked against [Apple's permitted reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons?language=objc). Boot-time report use requires explicit voluntary sharing and prominent disclosure; the Guidance screen and exported first-column header now identify monotonic time since device boot. No automatic diagnostic upload was added. See also [Apple's required-reason rules](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

Tracking is false with no tracking domains. `NSPrivacyCollectedDataTypes` is deliberately not populated with invented server-side assertions; this file is not a completed App Store privacy questionnaire. Owner confirmation remains necessary for WCA/provider request logging/retention, third-party-hosted competition/avatar requests, optional submitted diagnostics and any future server/account handling. Local solves/preferences are not automatically characterized as server collection.

### Dependencies and Remaining Distribution Gate

Audited project dependency references, source, vendored notices and device-binary imports. SwiftConfettiView is vendored UIKit/Core Animation source with its existing MIT notice; no covered API call was found there. The min2phase source/bridge was inspected rather than assigned SDK reasons merely for being a solver. No new package or tracking SDK was added.

The precompiled TNoodle/Graal device dylib imports `stat`/`fstat`/`lstat`, `mach_absolute_time` and `fstatvfs`, and has no supplied manifest. The app's TNoodle bridge dynamically loads it on devices, while Simulator uses a stub. Imports prove binary references, **not which runtime calls execute or why**. Own Swift/Objective-C source has no disk-space API call. It would be dishonest to add DiskSpace `E174.1` merely to silence a symbol when no user-visible disk-capacity-dependent behavior is established.

Obtain the vendor/runtime usage audit and an appropriate SDK manifest/packaging, or rebuild after establishing/removing unused required-reason paths, before distribution clearance. Do not assume the app manifest substitutes for the SDK's obligations: [Apple explicitly addresses third-party SDK and dynamic-library declarations](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api). The app manifest is implemented; whole-distribution privacy compliance, particularly TNoodle, is not declared complete. No vendor binary was modified.

## WCA OAuth Read-Only Findings

Production authentication, credentials, registration, callbacks and history remain unchanged. No login/token endpoint was exercised and no credential was printed or copied into this report.

### Official Capability vs Assumption

The [WCA API help](https://www.worldcubeassociation.org/help/api) and [official legacy v0 OAuth documentation](https://docs.worldcubeassociation.org/knowledge_base/v0_api.html) describe secret-bearing flows; the latter documents authorization code without PKCE. Its implicit flow documentation is not a modern native-app security recommendation.

For stronger evidence, pinned WCA source at `7961dc8453530ef827d2c35d7c3b5d9972c362f7` (2026-10-21T14:06:00Z):

- [Gemfile.lock](https://github.com/thewca/worldcubeassociation.org/blob/7961dc8453530ef827d2c35d7c3b5d9972c362f7/Gemfile.lock) locks Doorkeeper 5.9.9.
- [OAuth initializer](https://github.com/thewca/worldcubeassociation.org/blob/7961dc8453530ef827d2c35d7c3b5d9972c362f7/config/initializers/doorkeeper.rb) enables authorization code and refresh tokens; no PKCE/custom grant model is configured.
- [Schema](https://github.com/thewca/worldcubeassociation.org/blob/7961dc8453530ef827d2c35d7c3b5d9972c362f7/db/schema.rb) has `oauth_applications.confidential` default true, but **no `code_challenge`/`code_challenge_method` grant columns**.
- [Application controller](https://github.com/thewca/worldcubeassociation.org/blob/7961dc8453530ef827d2c35d7c3b5d9972c362f7/app/controllers/oauth/applications_controller.rb) permits name, redirect URI and scopes only; the self-service form likewise exposes no public/confidential switch.

Version-matched upstream [grant model](https://github.com/doorkeeper-gem/doorkeeper/blob/v5.9.9/lib/doorkeeper/models/access_grant_mixin.rb) enables PKCE only if the grant table has the challenge column. Its [code exchange](https://github.com/doorkeeper-gem/doorkeeper/blob/v5.9.9/lib/doorkeeper/oauth/authorization_code_request.rb) checks verifiers only when that capability exists. Merely adding client-side challenge parameters could therefore provide no PKCE protection. The pinned WCA schema does **not** establish enabled PKCE; actual deployed database/configuration may differ and needs provider confirmation.

Doorkeeper's [application lookup](https://github.com/doorkeeper-gem/doorkeeper/blob/v5.9.9/lib/doorkeeper/models/application_mixin.rb) supports non-confidential clients without a secret. This proves framework capability, not that WCA offers public-client registration to CubeFlow. The source's confidential default and self-service permitted fields are reasons to confirm with WST rather than assume registration exists.

Authorization-code exchange without PKCE is supported in inspected WCA source/docs. Backend-assisted confidential exchange is compatible with that protocol, but is not a mandatory property of all possible WCA registrations. A safe no-backend native migration depends on verified PKCE and public-client support; it is not established today.

### Current App Facts and Risks

`WCAAuthManager` uses ASWebAuthenticationSession, authorization code and HTTPS token/refresh requests, with tokens in Keychain. Profile/preferences are stored locally. It embeds the client secret and submits it from the client for code and refresh exchange. A credential literal equality scan, without printing the value, found the current secret in four file-history revisions; oldest matched revision is `49a6967e6c36101560e8a843452980b94cd43c2d`.

No authorization `state` or PKCE verifier/challenge is generated, persisted, validated or consumed. Callback handling extracts a nonempty code but does not explicitly validate full scheme/host/path or an attempt-bound state. `cubeflow-wca://oauth/callback` is configured consistently as the app's custom-scheme redirect, but its exact provider registration was not queried. A custom scheme alone is not exclusive ownership or proof of protection against interception/injection.

[RFC 8252](https://www.rfc-editor.org/rfc/rfc8252) treats distributed native apps as public clients: a compiled shared secret cannot provide confidentiality. It recommends external-user-agent authorization with PKCE and owner-based redirect schemes or claimed HTTPS. The present use of ASWebAuthenticationSession is appropriate; embedded-secret secrecy and missing attempt validation are not.

### Prioritized Next Pass, No Deployment Authorization

1. Confirm actual deployed PKCE/S256 enforcement and public-client registration with WST. Specifically verify verifier mismatch/missing-verifier rejection, not just successful authorization with extra parameters. Use an approved test registration in a separately authorized pass.
2. If supported, migrate to a native public client with a per-attempt S256 verifier, random state, exact callback validation, one-use consumption and cancellation/replay/concurrent-attempt tests. Remove the secret from the binary. Validate code and refresh flows with the provider.
3. If unsupported, assess a separately authorized confidential backend exchange with provider callback/state ownership and an attempt-bound one-time app handoff, or defer authenticated account functionality. Do not replace this with implicit/password flow or pretend a secret shipped in iOS is confidential. Backend work/deployment remains subject to the existing owner/ICP gate.
4. Treat the embedded/history credential as non-confidential. Coordinate rotation or retirement of the old registration **after** choosing migration and supported-build cutoff. A replacement secret must not be shipped in another native binary. Explicitly plan existing refresh/access-token revocation and user reauthentication with WCA; do not assume secret rotation itself revokes all tokens. Any Git-history cleanup requires separate approval and does not revoke credentials or erase prior copies.

No registration, redirect, credential, token, backend or production-authentication change occurred here.

## Verification and Files

Artifacts: `/Users/paulsun/Desktop/Projects/CubeFlow/build/smart-cube-guidance-device-polish-oct21/`.

- `solver-baseline.xcresult`: one new seven-move native-mode comparison test passed.
- `device-timer-lifecycle.xcresult`: initial test compilation failed on two test-only issues (missing Combine import and closure arity); corrected before executing tests.
- `device-timer-lifecycle-v2.xcresult`: one existing management test failed at five assertions because the simulator's asynchronous unsupported-Bluetooth callback invalidated its seeded session. The fixture now prepares/waits before seeding, as the existing integration fixtures do. No production BLE guard was weakened.
- `focused-final.xcresult`: 71 XCTest plus 37 Swift Testing tests passed, zero failures.
- `evidence-final.xcresult`: 22 relevant XCTest passed after raw-token evidence/header/test-screenshot refinements. This is a subset, not 22 new distinct tests.
- Final distinct passing union: **109 tests**. No broad unrelated suite or zero-test success counted.
- The **one** authorized unsigned generic iOS Debug build passed, exit 0, `CODE_SIGNING_ALLOWED=NO`, Xcode 27.2 (`27B5019j`). No second generic or Release build. Only build warning: AppIntents metadata extraction skipped without an AppIntents.framework dependency.
- Source and bundled manifest plist validation, byte comparison, three localization plist checks and `git diff --check` passed. App minimum remains iOS 15.0.
- Inspected actual card/discovery, Light/Dark typography and mounted Timer screenshots. Initial Timer screenshots captured mid-animation; final `final-images/` screenshots use test-only disabled animation and display the adopted path correctly. They are not a physical cadence check.
- All 7,343 source/config/vendor hashes match immediately before and after the final build. Against this pass's baseline, 7,563 existing files remain byte-identical, 18 scoped files changed, none are missing. App project, Info.plist, signing/version configuration, OAuth, canonical animation engine, competition/Explore work and native button styling are unchanged from baseline.

Changed existing files, relative to this pass's baseline:

- [SmartCubeBluetoothManager.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/SmartCubeBluetoothManager.swift): process-owned success HUD and attempt deduplication.
- [SmartCubePeripheralSession.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/SmartCubePeripheralSession.swift): DEBUG connection-phase fixture only.
- [SmartCubeDiagnostics.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/SmartCubeDiagnostics.swift): explicit optional-report uptime header.
- [SmartCubeReplacement.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/SmartCubeReplacement.swift): distinguish raw from normalized DEBUG candidate evidence; selection/search behavior unchanged.
- [ConnectedDevicesView.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/ConnectedDevicesView.swift): unified-card route and compact battery medium weight.
- [SmartCube3DView.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/SmartCube3DView.swift): window/explicit visibility render ownership and canonical resume.
- [SmartCubeLabView.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/SmartCubeLabView.swift): reuse picker in the card without nested presentation/dismissal.
- [SmartCubeManagementCard.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/SmartCubeManagementCard.swift): identity-bound discovery transition and name fitting.
- [SmartCubeDiscoverySections.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/SmartCubeDiscoverySections.swift): unsaved-row connecting progress.
- [TimerTabView.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/TimerTabView.swift): unified routing, covered-renderer enablement and DEBUG injected controller.
- [SmartCubeScrambleProgressView.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/SmartCubeScrambleProgressView.swift): DEBUG mounted text observation only.
- [SmartCubeTimerGuidanceProbe.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/SmartCubeTimerGuidanceProbe.swift): DEBUG displayed-text probe.
- [SmartCubeGuidanceCaptureView.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/SmartCubeGuidanceCaptureView.swift): optional uptime-report disclosure.
- [SmartCubeAnimationRegressionTests.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/SmartCubeAnimationRegressionTests.swift).
- [SmartCubeManagementTests.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/SmartCubeManagementTests.swift).
- [SmartCubeSolverAuditTests.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/SmartCubeSolverAuditTests.swift).
- [SmartCubeTimerIntegrationTests.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/SmartCubeTimerIntegrationTests.swift).
- [SmartCubeGuidanceTraceTests.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/SmartCubeGuidanceTraceTests.swift).

New files:

- [PrivacyInfo.xcprivacy](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/PrivacyInfo.xcprivacy).
- [SmartCubeDevicePolishTests.swift](/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/SmartCubeDevicePolishTests.swift).
- This report. Build/research/screenshot artifacts stay under the existing `build/` directory.

## Minimal Physical Acceptance

1. On the latest source, enable the existing DEBUG Guidance Capture and record the original visible scramble. Make seven deviations, stop for five seconds and inspect the actual path. If still stuck, retain that stationary interval; do not force more input merely to unlock it. A captured same-source shown/raw/normalized/selected comparison is needed to attribute the still-unresolved failure.
2. In a separate continuous attempt, pause at 12, 17, 18 and 19 deviations. Verify the original target remains fixed, strictly shorter verified candidates appear without another move, and equal valid continuations do not churn. Optionally copy the bounded report only if sharing is intended.
3. Compare Settings, Timer and management with `U U`, `U2`, mixed turns and a rapid short burst while Guidance updates. Open/close the card, switch Timer -> Settings -> Timer and background/foreground once. Verify visible intermediate motion, correct final stickers, no hidden backlog and resumed smooth input. Intermittent physical stutter remains unproven until this check.
4. With no connected cube, open Timer's Smart Cube entry: the same card shows My Devices/Other Devices. Connect, Disconnect, retry a failed/unavailable connection and reconnect in that card. With two connected same-model cubes, manage/disconnect the inactive one and verify Timer Active is unchanged. Check existing Reset/Forget confirmations.
5. Confirm one native Connected HUD after manual connect and automatic reconnect, none merely on navigation, scan or rerender. Check single-line/truncated names, management 24/23 pt typography, Timer medium battery weight and unchanged buttons in Light/Dark Mode.

The remaining blockers are actual physical Guidance/animation acceptance, TNoodle runtime/privacy validation and separately authorized OAuth security migration. Apple account/signing setup is already complete and was not repeated.
