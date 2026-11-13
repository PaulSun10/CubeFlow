# CubeFlow native UI follow-up, November 6, 2026

Baseline: [November 6 recovery](performance-recovery-nov06.md) and the user's subsequent iPhone acceptance results. Large-session switching, targeted Recent Records, the Battle interaction concept, chart/Histogram, GAN 3x3 behavior and the single-PNG contract are protected. Interesting Competitions and WeiPo hardware acceptance were deferred. No physical BLE hardware or other device was operated.

## Implementation

| Issue | Evidence and change | Status |
| --- | --- | --- |
| Data Select/X hitch and bottom rectangle | Selection previously changed the child first, then an observation changed the root and ran a separate animation for the search accessory. One transaction now changes local selection and root mode, with the root deciding when search is presented. The native nav title and existing Select/X toolbar identity stay mounted. The action row lives in the outer navigation surface's `safeAreaBar` on iOS 26 and `safeAreaInset` on earlier releases. No color mask, forced offset, disabled animation, or artificial delay. | Two layout triggers consolidated. The physical hitch and rectangle have not been reproduced or attributed; it is unknown whether they share a cause. |
| Data Delete overflow and geometry | A separate bottom toolbar item could be overflowed independently even with a trash image. A trial with all three as one toolbar item still yielded UIKit bounds of 34.67 pt. An inner `safeAreaBar` yielded offscreen X coordinates in the mounted fixture. The outer bar sizes the native glass controls as one bounded row: localized text widths include Dynamic Type and button insets, then Delete switches to a circle, then the neighboring labels switch to accessible symbols if necessary. All three share the same height. | The compact case is verified in both appearances with actual window hit testing and the existing destructive confirmation. Physical geometry and compositor behavior remain open. |
| Battle | The previous fixed easing curve is replaced by a low-bounce spring using the same matched native Glass IDs and unchanged no-motion and material fallback paths. The settings start immediately beneath a compact header instead of a separate divider and padded settings top. The redundant scrambling label is removed; ready, disconnected and result feedback remain meaningful. A native Stepper retains the player's independent 0–10 second handicap and the same setter. | Simulator captures show compact setup, handicap, and both panels. Timing/scoring and device ownership did not change. Physical animation feel still needs acceptance. |
| Competition Report | The previous calculation used full em-space attempt separators and 22 pt column gaps. If that measured layout fails, the renderer tries en-space separators and 12 pt gaps before wrapping, using the same font sizes and keeping all rows, values, badges and localized location data. | A six-event multi-minute fixture verifies inline attempts and exports a single image. Extremely long values still use the established wrapping path. |
| Result Highlight | Replaced the duplicate-summary/report-style panel with one dominant result on a warm paper or dark graphite canvas. Event and placement anchor the top; the selected metric is the hero with the existing record badge, followed by identity, competition, complementary result and attempts. The active appearance is captured in the export task identity. The selected summary is not repeated. Competition logo, when present, stays secondary; wide banners no longer dominate the card. | Production export generated ordinary, PR, NR, CR and WR PNGs in both appearances. Design is pending user review. |

Data: `DataTabView.swift`, `IPhoneContentView.swift`, `SessionNativeActionStyle.swift`; DEBUG probe: `AppExperienceTrace.swift`. Battle: `TimerLocalBattleView.swift` and the DEBUG-only `LocalBattleTestProbe.swift`. Sharing: `CompetitionReportImage.swift`, `CompetitionPagedExport.swift`, `CompetitionSharePreview.swift`. Focused coverage: `NativeUIRecoveryTests.swift`, `BattleMixedInputTests.swift`, `CompetitionPagedExportTests.swift`.

Native APIs: [Apple safeAreaBar](https://developer.apple.com/documentation/swiftui/view/safeareabar%28edge%3Aalignment%3Aspacing%3Acontent%3A%29) extends the scroll-edge effect for content whose safe area it insets; [Apple glassEffectID](https://developer.apple.com/documentation/swiftui/view/glasseffectid%28_%3Ain%3A%29) identifies shapes for morphing. These API contracts do not establish behavior on the user's iPhone beta.

The mounted Data trace sampled 16 states per appearance at the top of the list. Offset stayed at -183 pt while the native inset and viewport height changed. The test also verifies that the compact controls' centers actually resolve to their UIKit buttons in window hit testing. That separates actionable placement from a button that merely exists in the view tree, but it is not a frame-paced trace of the iPhone compositor.

## Performance

- Data's range initialization previously allocated four arrays and scanned them separately after a background snapshot was published. It now aggregates in one pass and skips recomputing a dimension when its filter is active, preserving the chosen bounds. Changing an inactive filter's default boundary no longer triggers list filtering. The 8,000-solve fixture compares exact bounds, penalties, and ordering-independent results. Initial five-run measurements: 8.4–9.0 ms before, 2.7–3.3 ms after. This is CPU-side wall time in a Debug simulator test, not selection latency.
- Timer's deferred statistics ownership, background scramble prewarming, prefetch and stale-result guards remain. Its streak aggregation still walks the full collection on relevant updates; no isolated startup evidence justified changing its persistence or scheduling in this pass.
- Algs' overview contains multiple trainer history readers, but they are behind `showsAlgTrainingEntrypoints = false`; no production cache was added for an inactive path. Existing lazy tab mounting and search indexes remain.
- Explore's records and competition refresh already overlap. Targeted Recent Records loading and the existing cache tiers were left intact. No provider probe, speculative prewarm or recommendation change was introduced.
- Settings and shared UI retain lazy mount and existing session restoration. No new startup task was added. The Data toolbar changes are local to Data and have no always-on instrumentation. Battle continues to keep both players and renderers mounted without adding clocks or observers.
- The Smart Cube and Guidance review was read-only. No claims about hardware frame pacing, reconnection, or power use.
- For PNG exports the streaming strip and preview tile architecture is unchanged. Compare equivalent 68- and 512-row fixture logs against the November 6 baseline; changed output dimensions are not a benchmark of the encoder alone. A per-strip storage maximum is not whole-process peak RSS.

Environment: Xcode 27.2, arm64 iPhone 17 Pro simulator (iOS 26.5), Debug. Report timing is wall-clock including layout and export; the focused runs and full suite have different process loads.

| Fixture | November 6 baseline | Follow-up |
| --- | --- | --- |
| Bounds, 8,000 solves, five paired runs | Array-based reference in the same run: 9.65–10.07 ms | 3.07–3.55 ms with identical min/max values; no intermediate arrays |
| 68 rounds | 1680 × 9946, 1,746,868 bytes, 269–278 ms | Same dimensions and bytes; 268–277 ms in two focused samples, 469 ms in the full suite |
| 512 rounds | 906 × 51855, 7,181,773 bytes, 939–996 ms | 1077 × 43633, 8,151,604 bytes; 1029–1050 ms in two focused samples, 1947 ms in the full suite. The largest individual bitmap remains 2,580,480 bytes. |

The new layout is shorter and wider at the same approximate pixel budget for the long fixture, with a larger compressed file and no demonstrated export speedup.

The mounted all-tab fixture reported first / subsequent entry wall times in ms: Timer 117 / 436, Data 411 / 519, Algs 711 / 387, Explore 1105 / 434, and Settings 474 / 425. The 1,000-solve Data fixture published at 577 ms with one initial fetch. These include harness drawing and scheduling; the previous full run had materially different readings. They do not establish faster first entry, warm launch, or physical frame pacing. Physical memory and energy were not measured.

## Artifacts

Outputs are under `build/native-ui-followup/` (ignored). Data: `data-search-1.png`, `data-search-2.png`, `data-delete-1.png`, `data-delete-2.png`, `data-delete-text.png`, `data-toolbar-1.json`, `data-toolbar-2.json`. Battle: `battle-panels.png`, `battle-one-configuration.png`, `battle-dual-configuration.png`, `battle-small-dark-reduce-motion.png`. Report: `report-long-times.png`. Highlight: `highlight-{ordinary,PR,NR,CR,WR}-{light,dark}.png`.

## Verification

- Complete application suite: 1,193 cases, 1,187 passed, zero failures, six skipped. This includes 835 XCTest cases and 358 Swift Testing cases. The skips are the opt-in provider probe and five host Keychain cases requiring entitlements. See `full-final.xcresult`.
- The 3,569/4,505-solve Session fixture still showed zero hidden Timer reads and one final destination load. Its five synchronous preference publications were 1.15–2.15 ms, and dismissal to loaded rows was 877 ms including harness and presentation work.
- After the full suite, the text-Delete fixture alone was refined to use the real root tab and check settled window coordinates and hit testing. That test-only rerun passed and produced the inspected `data-delete-text.png`; production source did not change after the full suite.
- Focused XCUITest suite: six passed, zero failed. Covered competition navigation and native Back, official By Competitor/horizontal attempts, sum-row navigation, Explore's competition entry, cold Timer controls and launch timing. Five XCTest launch samples averaged 1.522 s (0.842% relative standard deviation) versus 1.534 s in the preceding pass. Cold Timer controls took 5.21–7.01 s including XCTest polling. Neither measurement establishes a meaningful change to first visible frame.
- Unsigned generic iOS Debug build passed; built app metadata shows `MinimumOSVersion=15.0`. This verifies compilation and deployment metadata, not runtime on iOS 15. All 60 `.strings` files pass `plutil -lint`; `git diff --check` passes. The existing TNoodle privacy and App Intents metadata warnings remain. Xcode reported a `simctl` lookup failure while collecting optional post-test diagnostics; the test command and result bundle passed.
- Git: `main` at `82b455c39`, 0 ahead/0 behind the locally recorded `origin/main`, 89 modified tracked files, 74 untracked files, no staged changes. The checkout was dirty before this pass; only this report is an additional status entry. No commit, push, reset or deployment.

## Physical acceptance

1. In Data, scroll to both ends and switch Select/X repeatedly in Light and Dark. Check for the hitch and rectangular fill, then select all and activate and cancel Delete at normal and larger text sizes.
2. Open and reverse both Battle panels; check top spacing, the stepper, and Reduce Motion.
3. Review the supplied Highlight variants and inspect a long Report in the iPhone share sheet. No Smart Cube test is requested.
