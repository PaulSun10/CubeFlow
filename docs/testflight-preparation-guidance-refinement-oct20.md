# CubeFlow TestFlight Preparation and Guidance Refinement

Status: **This engineering pass is complete: focused tests, final unsigned Debug build and preservation checks passed. This is not a release approval or physical acceptance.**
Updated: October 21, 2026, Asia/Shanghai. The complete original goal is retained.

## A. Baseline and Scope

Working tree: `/Users/paulsun/Desktop/Projects/CubeFlow`. This pass continues the existing dirty checkout, not a new implementation. Initial status, tracked diff, hashes and source copies are under `build/testflight-guidance-oct20/`. The baseline includes earlier accepted Competition Browser scrolling, Top Cubers, Filter, Results/PR/Live, native Back and Smart Cube corrections.

Reviewed reports: `smart-cube-root-guidance-oct20.md`, `explore-filter-lifecycle-oct20.md`, `targeted-reliability-oct20.md`, `competition-record-integrity-oct19.md`. The earlier twips assessment was reused, not repeated or integrated.

Changes are confined to current-state guidance/native interruption/DEBUG evidence, regional Explore event layout, connected-cube management, date-window/query/publication correctness, focused tests and this report. Filter comparative experiments are test-only; the TestFlight audit is read-only. No protocol mapping, Combined lifecycle, move animation, accepted Browser self-sizing/scroll physics, Top Cubers, Results transitions, or native Back redesign is included.

The final source-freeze hash audit found 23 pre-existing source/test/resource files changed, seven source/test additions, zero removals and 7,286 unchanged baseline files. The externally accepted project file remains byte-identical to baseline. `final-source-sha256.txt` includes the final DEBUG publication observer and extreme-accessibility test additions; its prebuild verification passed.

Existing files changed in this goal:

```text
CubeFlow/Min2PhaseBridge.h
CubeFlow/Min2PhaseBridge.mm
CubeFlow/Vendor/min2phaseCXX/src/Search.cpp
CubeFlow/Vendor/min2phaseCXX/src/Search.h
CubeFlow/Views/Shared/CompetitionService.swift
CubeFlow/Views/Shared/DeviceBatteryIndicator.swift
CubeFlow/Views/Shared/SmartCubeBluetoothManager.swift
CubeFlow/Views/Shared/SmartCubeDiagnostics.swift
CubeFlow/Views/Shared/SmartCubeGuidanceController.swift
CubeFlow/Views/Shared/SmartCubeReplacement.swift
CubeFlow/Views/iPhone/CompetitionBrowserPublicationAcceptance.swift
CubeFlow/Views/iPhone/CompetitionTabView.swift
CubeFlow/Views/iPhone/Explore/ExploreCompetitionEventStrip.swift
CubeFlow/Views/iPhone/SmartCubeManagementCard.swift
CubeFlow/Views/iPhone/SmartCubeScrambleProgressView.swift
CubeFlow/Views/iPhone/TimerTabView.swift
CubeFlow/en.lproj/Localizable.strings
CubeFlow/zh-Hans.lproj/Localizable.strings
CubeFlow/zh-Hant.lproj/Localizable.strings
CubeFlowTests/CompetitionNavigationLoadingTests.swift
CubeFlowTests/ExploreRegionPackingTests.swift
CubeFlowTests/SmartCubeManagementTests.swift
CubeFlowTests/TargetedSmallUILayoutTests.swift
```

Additions: `CompetitionDateWindow.swift`, `SmartCubeGuidanceTrace.swift`, `SmartCubeLateGuidanceTests.swift`, `SmartCubeLatestGuidanceTests.swift`, `CompetitionDateWindowTests.swift`, `SmartCubeGuidanceTraceTests.swift`, `CompetitionFilterNativeComparisonTests.swift`, and this report. Their full directory paths are recorded in `task-new-files.txt`.

## B. Guidance Findings

The actual pipeline is canonical update -> trusted source and original target -> revision/epoch invalidation -> 120 ms trailing settle -> exact short search -> serial native search -> tighter improvement -> replay verification -> MainActor publication -> Timer adoption -> SwiftUI update.

Proven source-level mechanisms addressed:

- A cancelled synchronous native search continued owning the only worker, so a newer request, including an exactly short request, waited for its return.
- A primary native answer was held until the tighter second search completed. Probe limits count phase-two entries; they are not a wall-clock or phase-one node budget.
- A valid visible `.searching.fallbackPlan` was not read as the next continuation because Timer read only `.plan`.
- Ordinary valid continuation states did not consistently receive quiet best-known reevaluation.

The native relative transform remains **current inverse times exact target**, with the existing inverse-solution output convention. No solve-to-solved substitution or target rotation was introduced. Every candidate is replayed from its exact source to the original target, and the complete expected-state path is verified.

The simple legal late-scramble states tested here do **not** reproduce the user's 10-15 second hardware interval. These tests establish concrete starvation and held-candidate mechanisms, not attribution of that entire observed interval. Physical BLE, framework scheduling under actual load, and an uncaptured hard state remain open acceptance boundaries.

## C. Solver Strategy and Claims

HTM remains the cost metric. Exact exhaustive search through depth three proves optimality only for a hit within that radius. Min2Phase/tighter-budget candidates are **best verified**, not globally optimal. A historical inverse/continuation is retained only after exact replay validates it; its validity alone is not an optimality proof.

Production scheduling now separates cancellable exact-short work from the one native owner. It retains one latest pending native request, cancels obsolete work and rejects old tickets. Native code checks cooperative cancellation/deadline every 1,024 visited nodes. Search limits are 350 ms primary plus 100 ms tighter improvement; the original 1,000,000/10,000 phase-two probe ceilings remain secondary bounds. Legacy bridge callers install no interruption hook and retain their previous policy.

Table initialization and cubie normalization occur outside the search deadline. Deadline checks are periodic rather than preemptive. Therefore 450 ms is **not** a hard complete-request guarantee. The exact-short lane can publish while even an injected uninterruptible obsolete native owner remains held.

Known-path ties remain quiet; a verified one-move improvement is accepted. A shorter valid known route wins over a longer solver route. Following a continuation keeps progress instead of rebasing on an equal-cost alternative. Completion and replacement of the scramble cancel synchronously without waiting for obsolete native work.

Timer retains epoch, source, original target, generation, canonical trust, timing-mode and eligibility checks, and now explicitly checks Active device identity both before handling a publication and in the publication-to-progress adapter. Inspecting another cube does not change Active.

No twips code, dependency or replacement solver was added. Existing vendor license provenance is a separate release-audit item below.

## D. Measurements and Evidence Boundaries

All measurements below are simulator measurements, not iPhone BLE latency. Fixture: original legal 20-token scramble `R2 U F' D2 L B2 U' R F2 D L2 B' U2 R' F D' B U L' R2`. Early deviation uses its two-move prefix plus `L`; late cases use its 15-move prefix plus respectively `R`, `R U F`, and `R U F L D B`. The target is always the full original scramble state.

Initial native-stage baseline (`baseline-late.log`):

| Case | Known HTM | Primary ms | Improvement ms | Combined native stages ms |
| --- | ---: | ---: | ---: | ---: |
| Early | 19 | 128.55 | 759.91 | 888.46 |
| Five remaining, one deviation | 6 | 0.094 | 0.577 | 0.671 |
| Five remaining, three deviations | 8 | 0.075 | 0.635 | 0.710 |
| Five remaining, six deviations | 11 | 0.710 | 11.669 | 12.379 |

The early baseline includes cold native setup. It is not directly comparable to a warm full-planner measurement.

Five full current-planner samples per state (`guidance-measured-v2.log`), including exact-depth-three misses and replay but excluding settle/UI: early 132.15-134.38 ms; late-one 21.19-21.95 ms; late-three 22.14-22.86 ms; late-six 33.07-34.58 ms. Do not subtract these full-planner measurements from the native-stage baseline.

An additional paired warm comparison uses the actual production exact-short search and replay verifier with the previous native two-pass policy injected as a reference, versus the current bounded production planner. This is a policy reference, not an old binary or physical end-to-end benchmark. Five samples per cell, `focused-v3.log`:

| Case | Warm previous-policy reference ms | Current planner ms |
| --- | ---: | ---: |
| Early | 674.70-702.74 | 130.01-130.38 |
| Late-one | 19.51-19.69 | 20.16-20.66 |
| Late-three | 20.04-20.87 | 21.01-21.75 |
| Late-six | 29.83-31.41 | 30.77-32.77 |

The expensive early tighter-search tail is reduced. These simple late cases are not faster and add about 1-2 ms of normalization/verification overhead; the relevant late-state correction is obsolete-worker scheduling/cancellation, not a claimed same-state 10-second arithmetic speedup. The explicit uninterruptible-worker regression proves the latest exact-short path can publish before that old worker is released.

DEBUG tracing uses the existing 2,048-entry scalar ring. It records receipt/snapshot, settle/schedule, exact search, actor wait, native tables/normalization/search, improvement, verification, MainActor arrival, eligibility/mismatch checks, continuation reuse and SwiftUI update. Epoch/device IDs are shortened; state/target use stable non-authoritative digests. No raw scramble, facelets or personal names are added.

Export sorts timestamps and computes receipt-to-candidate/SwiftUI-update intervals off the critical path, matching epoch/source/target across a legitimate guidance-rebase revision change. A SwiftUI update is not a GPU-present frame, and missing receipt evidence after ring eviction never becomes an invented latency. All tracing/export additions are DEBUG-only.

## E. Exact-Target and Lifecycle Coverage

Deterministic production-component regressions cover early/late legal states; rapid latest-state coalescing; an optimal inverse; a real legal 13-to-12 HTM improvement; old native ownership; exact completion; immediate replacement target; navigation/owner release; another Active device with identical source/target/epoch; stale source/target/generation/trust; uninterruptible injected native work; cooperative phase-one cancellation; and eventual publication without another physical move.

Existing guidance lifecycle/current-state/ownership tests are retained. No old target or continuity prerequisite is weakened. The existing progress view's loading and unavailable flags are visually inert: no Updating Guidance, equivalent prose, spinner or placeholder. Tests compare actual mounted view geometry with those flags enabled/disabled. The valid same-scramble fallback remains presentation-only while stale highlighting/action eligibility remains guarded.

`focused-v3` passed 122 XCTest and 27 replacement Swift Testing tests. Final targeted follow-ups passed on the later date observer and accessibility assertions, as distinguished in L; physical acceptance remains open.

## F. Regional Explore Layout

Only `explore.in_region` changes. The balanced dynamic-programming partition was removed. The new deterministic greedy pack fills the first row to its measured minimum-gap capacity before starting the next row.

At each Dynamic Type size, square cells accommodate the actual font advance/ink overhang and the unchanged shared glyph's vertical padding. The minimum normal icon remains 18 pt. A capped maximum is derived from the shared event area's height and at most twice the scaled minimum; one/two icons cannot inflate to card width. A bounded binary search chooses the largest one-row square cells with proportional comfortable spacing. Gaps stay in 4-12 pt, with no negative gaps or overlap; only when minimum cells and minimum gaps cannot fit does the layout wrap.

The shared family reserves enough height for all 17 official events at the current width/text size (at least two minimum rows). Shorter one-row sets use larger cells and are vertically centered in that area. Extreme accessibility sizes can use additional rows without hiding events. No per-card GeometryReader-to-State sizing feedback, horizontal icon scroller, +N, event reordering or glyph-specific offset is introduced.

Widths stay 280 pt normally and 310 pt at accessibility sizes, with content widths 248/278. Nonregional Explore layouts and competition destinations remain unchanged.

## G. Explore Rendering

`ExploreRegionPackingTests` covers 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17 events, normal through extreme Dynamic Type, recreated hosts, changed widths/content and actual mounted family frames. Minimum font/gap, complete order, maximum first-row capacity, no clipping/overlap and equal family height are asserted.

Observed normal 248-pt event area: 13 = **9+4**, 17 = **9+8**. At 278 pt and normal minimum: 13 = **10+3**, 17 = **10+7**. These are consequences of square-cell measurements, not hardcoded event thresholds. Few-event icons are approximately 35.5 pt, tapering toward 18 pt as the row fills.

Actual production-family frame measurements for all 13 fixture cards: normal height 210.33 pt, xxxLarge 294.33 pt, accessibility3 584 pt, and accessibility5 860.67 pt at the tested 320/393/440-pt windows; all cards within each family have the same height and event-region Y. The final `explore-extreme-v9` mounted run includes accessibility5, not only helper arithmetic. Names, dates and locations retain natural wrapping.

Light/dark adaptive galleries were exported and visually inspected. The original card family and large-text screenshots are retained under `build/testflight-guidance-oct20/layout-images/`; their xcresult manifest maps readable names to files. No raster editing was performed. The gallery includes 1/3/5/7/9/13/17; mounted tests cover the remaining requested counts.

## H. Management Card

The management list now derives from **currently connected supported 2x2/3x3 sessions**, not saved history. This preserves the accepted ability to inspect a connected inactive 2x2 while Timer Active remains a 3x3; it does not silently reinterpret viewing as selecting a Timer puzzle/device.

Opening defaults to a connected Active device, otherwise a genuinely connected supported cube, otherwise the existing localized no-connected-cube state. An explicit connected initial selection remains valid. A stale/offline initial ID is ignored. The displayed ID is validated synchronously on every render, and disconnects reconcile selection and pending destructive confirmation, so no disconnected renderer remains until a later user action.

Name is left and battery right, both title3-sized and vertically centered; battery retains lighter weight and existing color/accessibility/clamping. Reset remains full-width and immediate. Disconnect/Forget have equal-width labels below. Native `.glassProminent` / `.glass` styles are used on iOS 26+, with `.borderedProminent` / `.bordered` on iOS 15+. Forget retains destructive confirmation and existing association-only deletion/history safeguards.

The previous single-content overflow fitter is unchanged. Existing mounted ownership tests still assert one ongoing renderer/subscription and zero subscriptions after removal. New mounted tests cover Active default, offline rejection, inactive viewing, selected disconnect -> remaining device -> empty, retaining saved associations, and renderer removal. No BLE or renderer protocol behavior changed.

The UI screenshot of the actual inactive 2x2 card was inspected. Its fixture has no battery value; typography equality is specified by the shared title3 font, not falsely claimed as visually measured from that battery-absent screenshot.

## I. Date Semantics and Publication Race

WCA list start/end values are UTC-encoded **civil dates**, not venue instants. The user's Gregorian local today is converted into that same UTC civil-date domain. Calendar-day arithmetic is performed there, avoiding DST or western-timezone shifts of date-only metadata.

- Recent: start day in [today - 30 calendar days, today], inclusive (31 dates).
- Present: start day >= today, with no future cutoff.
- Past: end day < today; a date-only competition ending today has not yet ended.

An ongoing event that began yesterday is Recent, not Present. Recent/Present intentionally overlap for starts today, including multi-day events ending later. Reversed/nonfinite/missing/malformed dates fail closed. Existing display/venue/registration date semantics outside this list filter are not redefined.

The official API's `start` filters start_date while `end` filters end_date; `ongoing_and_future` filters end_date and cannot implement the new Present definition. This was verified against the [WCA competition search source](https://github.com/thewca/worldcubeassociation.org/blob/main/app/models/competition.rb#L1580). Present now requests start >= today. Recent requests ascending start >= recentStart, locally filters the upper start boundary and stops when a sorted page reaches future starts, rather than applying the wrong end-date upper bound or scanning all future pages. Past requests end <= yesterday. Future selected Past years finish empty without scanning the catalogue.

Each Browser query anchors a date window; in-flight requests do not drift across midnight. Current query/cache signatures include civil day and timezone. System significant-time-change and foreground notifications invalidate that identity without a timer, including when the page stays selected across midnight/timezone changes. Closed historical years retain stable keys. Persistent v3 snapshots are refiltered as stale fallback under the v4 semantics, not deleted or trusted as a complete new-window result.

A demonstrated independent pull-refresh ABA differed from the old identity-bound `.task` path: filter A -> B -> A restored the same signature, while the separately launched old refresh was not necessarily cancelled. Request UUID ownership now guards every relevant cache/page/preparation publication and terminal error/success; same signature alone cannot authorize that old completion. Source-revision checks also reject older same-query prepared rows. A mounted negative control disables only this new epoch check and reproduces the obsolete refresh overwrite; the normal production path rejects it.

The initial date-v1 run passed all date boundaries and the negative control but exposed stale DEBUG preference snapshots despite apparently correct collection observations. Adding the list-publication revision to the DEBUG snapshot produced a passing date-v2 (21 tests) and focused-v3. A later repeated run contradicted the claim that this alone fixed the observer: one cache-ABA iteration still failed, and the mounted day-change test recorded a duplicate initial read.

Inspection found the native display callback and injected cache/page hooks were process-global while retired/retiring Browser hosts could still have asynchronous callbacks using the same fixture row IDs. A DEBUG per-mounted-root scope UUID now isolates those hooks, and teardown explicitly delivers disappearance. However, this scope correction alone did **not** resolve the terminal preference assertions: date-scope-v7 failed 24 assertions across two methods, with `ignoredForeignDisplays=0`. Foreign callbacks are therefore not established as the cause of those failures. The duplicate-read case subsequently passed, but its exact origin is not uniquely proven.

The failing runs also emitted SwiftUI's "Bound preference CompetitionBrowserPublicationKey tried to update multiple times per frame" warning. A last-delivered Preference snapshot is not a reliable acknowledgement of the actual publication commit. The final DEBUG observer records source IDs, published IDs, actual prepared-row IDs, query, phase and revision synchronously at the production `publishPreparedCompetitionListItems` commit. Terminal consistency is now asserted at that commit; the full post-release commit history must also exclude obsolete IDs in all three arrays. This replaces an unreliable observation boundary with stronger direct evidence, not a relaxation of the correctness invariant. Existing preference histories still reject stale IDs and provide active/inactive observations; independent native diffable-display histories and the deliberate UUID-guard negative control remain tested. All observer/scope hooks compile only in DEBUG and are inert outside the test environment. No production publication is skipped to make a test pass.

Final date-commit-v8 passed all 22 XCTest: eight date-window, nine cache and five mounted navigation/loading methods. The mounted scenarios include repeated cache ABA (12 iterations), page/error ABA (eight), reactivation (four), day/foreground changes and the independently launched refresh negative control. The stale request-UUID race is established independently of the unreliable Preference observation; no additional production race is inferred merely from a dropped/coalesced DEBUG snapshot.

## J. Filter Comparative Investigation

Production Filter presentation is unchanged. New test-only comparison: independent SwiftUI `.popover`, minimal UIKit `UIPopoverPresentationController`, actual full CubeFlow Filter. Each records content-controller lifecycle, a real transition-coordinator completion, presentation type, actual content/surface size, anchor and window coordinates. Programmatic UIKit dismissal completion is separate from the delegate callback; an uncalled delegate is not fabricated as an observed native event.

The initial iOS 26.5 comparison passed: independent SwiftUI and CubeFlow approximately 0.78 seconds, UIKit approximately 0.54 seconds to the native completion boundary. However, UIKit's original toolbar anchor differed, and SwiftUI did not expose a native sourceView. A later anchor-preference probe failed on the separately hosted toolbar in iOS 27.1; that run is **not** a valid controlled anchor comparison.

The harness now observes actual UIKit window coordinates using a passive view, and anchors the UIKit comparison to the measured same rectangle. Aligned runs passed on installed 26.5 and 27.1. Each has one warmup and three samples per variant:

| Runtime | Independent SwiftUI completion ms | UIKit completion ms | CubeFlow Filter completion ms |
| --- | ---: | ---: | ---: |
| 26.5, final-edges-v5 | 781.44-792.06 | 525.71-542.52 | 790.35-800.96 |
| 27.1, filter-native-27-v4 | 1214.43-2917.12 | 533.81-1088.19 | 1254.55-1396.76 |

All are actual transition-coordinator completion observations, not first-visible-frame timing or invented delegate acknowledgements. Anchor rectangles match within each runtime: (311,66,62,36) on 26.5; (243,16,62,36) on 27.1. Requested content is 290x348. Native geometry is not pixel-identical: UIKit includes a 13-point arrow extent and begins below its anchor, while SwiftUI's presented surface is 290x348 and is placed differently. That discrepancy is measured, not hidden by changing production presentation. The later harness records content bounds before dismissal; an earlier after-dismissal bounds field was unsuitable for sizing conclusions. Programmatic UIKit delegate didDismiss remained uncalled and is reported as such.

Different installed simulator device models, native hosting hierarchy, and highly variable 27.1 timings prevent a pure OS-version or physical-root-cause conclusion. Independent SwiftUI reproduces the long interval without CubeFlow's coordinator, so that coordinator is not necessary for the measured simulator delay. This does not prove an OS bug or justify a UIKit production replacement.

The existing physical captures were re-read: 112/256 events, zero reported dropped events, native-will-disappear to coordinator-completion intervals respectively 1243.03-2091.32 ms and 1242.71-1732.84 ms. They still do not identify when the entire visual dismissal surface disappears. Application completion follows the observed native acknowledgement promptly. No new physical capture, runtime installation or physical-device access was requested/performed.

A framework boundary difference would not prove the cause of the user's longer physical delay, nor justify bypassing dismissal, replacing the architecture, removing Glass or changing animations. If the aligned comparison establishes no application-specific cause, the physical attribution remains explicitly unresolved.

## K. Read-Only External TestFlight Audit

Actual app Release settings were inspected with `-showBuildSettings`, **not built/signed**: marketing 0.10.0, build 1, bundle `com.paulsun.cubeflow`, minimum iOS 15.0, automatic signing, Swift language mode 5 with MainActor default/approachable concurrency. Unit/UI test targets require iOS 26.2; that does not raise the app's minimum. iPad/Mac/vision targets are already present but no expansion was performed.

### BLOCKER / Release Gates

1. **Missing privacy manifest:** no `PrivacyInfo.xcprivacy` was found in Config, app, vendor or current app product. Production uses UserDefaults/AppStorage and file timestamps. Inventory the actual required-reason API categories and add justified declarations before distribution, not invented blanket reasons. Apple explicitly requires declaration for [UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults) and describes [required-reason API submission requirements](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api). No manifest was added in this read-only audit.
2. **OAuth security decision before broad external distribution:** WCAAuthManager contains an embedded confidential-client secret, has no authorization-request `state` round trip and no PKCE parameters, and accepts a nonempty callback code without explicit host/path validation. Do not reproduce credential values in reports. Treat the embedded secret as public; the owner must decide a supported public-client/PKCE or separately approved backend flow, state/callback validation and credential rotation. This is an engineering security gate, not a claim that Apple has already rejected the app. No server deployment or authentication rewrite is undertaken here.
3. **Distribution prerequisites are not locally proven:** active Developer Program/agreements, correct app record/bundle ID, distribution signing/provisioning, required beta information and Beta App Review approval must be checked by the owner. Automatic Debug signing settings and an unsigned build cannot prove them. The first external build requires full review; later builds may still require review. Do not choose Internal Only distribution for an external beta. [Apple external-testing instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
4. **Physical acceptance gate:** the final focused tests, permitted final unsigned generic Debug build and source-preservation checks passed. The user's real BLE guidance symptom and exact Filter dismissal behavior still require manual acceptance; automated verification does not close that gate.

### SHOULD FIX / Confirm

- Confirm the callback registered at the WCA application matches `cubeflow-wca://oauth/callback`; success, cancellation, expiration/refresh, sign-out and account changes require manual validation. ASWebAuthenticationSession mediates the supplied callback scheme. Absence of CFBundleURLTypes alone is **not** declared a proven failure of that session API. Tokens use Keychain; the public profile uses defaults. No token/secret contents were accessed from a user's account.
- `Config/Info.plist` includes Bluetooth Always usage text and bluetooth-central, local network/Bonjour, calendar, location and photo-save descriptions. Explain background Bluetooth and optional account use in review notes. Ensure privacy policy and App Store privacy answers match actual optional profile/network use. User-selected local diagnostics are not automatically classified as analytics collection.
- No encryption declaration was found in the checked-in plist. Review BLE AES and HTTPS against actual export-compliance requirements; do not automatically assert an exemption or add a Boolean without that review.
- Core Data uses automatic migration/inferred mapping and a programmatically assembled model; store load failure currently fatalErrors. No model/schema was changed here. Those flags do not prove an existing install upgrades safely. Back up a representative local store and perform same-bundle upgrade/restore tests, including sessions/solves/reconstruction, saved devices and OAuth. Query-cache v4 retains a stale v3 fallback, independently of solve persistence.
- Release-only compilation was not exercised by a Debug build. Source-level DEBUG guards around the new ring/export/probes/native timing getter were checked, but dead-code/optimization/link/signing behavior still needs the owner-authorized distribution workflow. No Release build or archive is hidden in this pass.
- Vendor provenance: min2phaseCXX README contains both GPLv3 and MIT sections and source carries additional copyright notices; root MIT alone does not establish every bundled component's redistribution terms. Resolve/preserve the applicable notices for exact vendor revisions, TNoodle and other dependencies before public distribution. This audit does not invent a licensing determination or import twips/GPL code.
- Confirm exact Xcode/SDK beta upload eligibility at distribution time. Apple's [upload guidance](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) lists supported minimum tools but does not establish acceptance of this exact 27.2 beta. No automatic beta-tool blocker or upload success is inferred.

### OPTIONAL / Owner Preparation

Prepare a small external group, What to Test, feedback email/contact, account instructions or demo route if needed, and known hardware/OS limitations. [Required beta test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/). Keep iPhone-only acceptance first; defer platform expansion and alternate solvers. TestFlight/account/transport secrets must not be placed in local diagnostics or reports.

No version/build/bundle/signing/profile/entitlement/App Store Connect setting was modified. No upload, archive, signed build or physical-device inspection was performed.

## L. Verification Ledger and Preservation

Artifacts: `build/testflight-guidance-oct20/`. Reruns and samples are not distinct tests.

- baseline-late: one measurement test, passed.
- guidance-p0-v1: 29 XCTest passed.
- guidance-measured-v2: 8 XCTest plus 27 Swift Testing cases passed; overlaps earlier suites.
- date-v1: 20 XCTest, two tests failed at six DEBUG preference assertions; not a passing run.
- date-v2: 21 XCTest passed with original assertions retained.
- explore-v1: test compile failed on explicit escaping self capture; corrected.
- layout-management-v2: 26 of 27 tests passed. The new default-selection observer asserted inside a callback during teardown/disconnect; assertion moved to the mounted test boundary, without weakening the required connected-list assertion. Six Explore and five ownership cases passed.
- filter-native-v1: test compile failed due to missing explicit Combine import under member-import visibility; corrected.
- filter-native-v2: 13 XCTest passed (12 management, one initial comparative experiment).
- filter-native-27-v3: anchor preference instrumentation failed; not valid aligned evidence.
- focused-v3: 122 XCTest plus 27 Swift Testing cases passed.
- explore-routing-management-v4: test compilation caught a one-argument closure where the observer requires two; corrected explicitly.
- final-edges-v5: six XCTest plus 19 composition Swift Testing cases passed, including no-Active fallback and mounted day/foreground refresh.
- filter-native-27-v4: aligned 27.1 comparison passed using test-without-building; not a generic build.
- date-final-v6: 22 XCTest executed, two tests failed (three cache-ABA preference assertions and one duplicate-read assertion). Not a passing run; triggered the scoped observer audit above.
- date-scope-v7: 22 XCTest executed, two methods failed at 24 terminal preference assertions. Scope isolation alone was insufficient; not a passing run.
- date-commit-v8: 22 XCTest passed with synchronous publication-commit evidence, native display history, stale-ID history and the negative control retained.
- explore-extreme-v9: six XCTest passed, including actual mounted accessibility5 family and glyph bounds.

The final passing coverage union is **126 distinct XCTest plus 46 Swift Testing cases = 172 tests** (27 replacement, 19 composition). Reruns are not counted again. `verified-test-union.txt` records the individual XCTest identities. Later targeted runs exercise the final source/stronger assertions for the only subsystems edited after focused-v3; the final unsigned build separately covers the complete frozen production source. This is focused coverage, not the entire project test suite.

The October 21 record-summary follow-up ran 19 related record tests and the separately authorized unsigned generic build successfully **before** the later date/Explore/management/guidance source in this continuing goal. That earlier build is not represented as verification of subsequent source.

The user explicitly approved one final additional build after the final corrections. The first launch wrapper exited before invoking Xcode because it attempted to assign zsh's read-only `status` variable. Correcting the wrapper did not change source or consume another actual build. The **one actual final unsigned generic iOS Debug build passed**, exit 0, with the frozen source unchanged before and after. Log: `final-unsigned-debug.log`; exit record: `final-unsigned-debug.exit`.

```sh
xcodebuild -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/competition-navigation-loading/DerivedData \
  -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
```

The build used Xcode beta 27B5019j / iOS 27.2 SDK with app deployment target iOS 15.0. No signature/archive/upload was produced. Remaining warnings: the pre-existing explicit-return ViewBuilder annotation on `configureWCALiveSession`, and skipped AppIntents metadata extraction because the app has no AppIntents.framework dependency. Neither was changed as unrelated cleanup.

Final `git diff --check`, task-file trailing-whitespace checks (including untracked additions), and pre/postbuild SHA-256 checks passed. The baseline comparison confirms **7,286 unchanged files, 23 scoped changed files, no missing baseline files and seven added source/test files**. The final freeze additionally covers Config/Info.plist and Finder metadata excluded from the initial inventory; those are not counted as task source additions. The accepted external `project.pbxproj` is byte-identical to baseline. Existing build/simulator/device data was not deleted or cleaned. No commit, push, physical-device operation, signed build, archive or App Store Connect change occurred.

## M. Risks and Physical Acceptance

The agent has not accessed a physical Apple device or claimed physical BLE success. The hardware 10-15 second guidance symptom remains unverified after these changes. Native table setup and cooperative checks are not a hard end-to-end deadline. Deep solutions remain best-known, not globally optimal. Filter's exact physical delay is unresolved. External TestFlight is not ready until its explicit gates are addressed by the owner.

Manual acceptance after a final verified build:

1. Use one approved trusted cube and original scramble: deviate early, then with about five original moves left; compare real response time and verify the displayed route reaches that exact target.
2. Follow a valid optimal inverse; it should remain quiet. Exercise a known one-move improvement fixture; only the shorter verified route should replace it.
3. Perform rapid consecutive moves; stop. The final state must receive guidance without another turn. Complete the target while old work runs, then immediately get the next scramble: no old path, Updating Guidance, spinner or placeholder.
4. Switch/navigation-away/reconnect while work runs; no old-device/old-epoch candidate may appear. For bounded timing evidence, enable existing Development diagnostics and Smart Cube Protocol Debug. The new TSV is currently a DEBUG debugger export (`po SmartCubeDiagnostics.shared.guidanceExport()`), not a new user-facing share screen. Capture it promptly after a short reproduction, before the ring overwrites the receipt. Simulator evidence is not a substitute.
5. Inspect regional cards with few/all events, long names/locations, Dynamic Type and both themes. All events remain visible and card heights equal.
6. Connect multiple supported cubes, view an inactive one without changing Active, reset/disconnect/forget only that selected cube. Disconnect the displayed cube and verify immediate fallback/empty. Repeat short and overflow layouts.
7. Switch Recent/Present/Past rapidly, including cache/offline and day boundaries; old results must not overwrite the selected filter. A today-start competition belongs to both Recent and Present.
8. Perform native Filter dismiss/reopen on the physical OS without changing Glass/animation. Keep this separate from date correctness. Verify accepted Browser scrolling, Top Cubers, Results/PR/Live and card/Back behavior remain unchanged.
