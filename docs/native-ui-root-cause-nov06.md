# CubeFlow native UI root-cause follow-up, November 6, 2026

Baseline: [recovery pass](performance-recovery-nov06.md), [native UI follow-up](native-ui-followup-nov06.md), and the subsequent physical acceptance. User-confirmed large Session switching, Recent Records, Timer, chart/Histogram, GAN Guidance, and Report ordering remain protected. Interesting Competitions and WeiPo hardware acceptance are deferred.

## Data

The physical hitch and the white/black rectangular fill are still open. No reliable physical or compositor reproduction established either cause or whether they are related. The root still owns a native tab accessory and tab minimization; the Data navigation container owns the inline toolbar and search destination, and its outer safe-area bar owns the selection actions. Entering selection changes all three of the bottom owners (tab visibility, search accessory, selection bar); simultaneous safe-area changes are plausible contributors, not proof of a compositing defect.

Confirmed app-side work was separate: every visible solve row emitted geometry preferences in normal mode and when Select/X had no range anchor, although the geometry consumer is inactive then. It is now collected only while an anchor exists. Layout and hit testing of ordinary rows are unchanged. The all-selected predicate now uses the selected-count invariant instead of scanning the list on each toolbar evaluation. Direct toggles and ranges add only visible IDs; every visibility replacement intersects the selection. All-selection continues to use the same visible scope, and confirmation does not change.

The action bar uses independent leading, centered, and trailing anchors rather than a centered intrinsic-width row. It measures each half against the centered action, adapts the red Delete label to a circular trash control first, and substitutes accessible symbols for neighboring labels when needed. Targets are at least 44 pt and native style/confirmation are preserved. Leading/trailing mirror with layout direction.

For the remaining iPhone issue, launch a Debug scheme with `CUBEFLOW_DATA_SELECTION_TRACE=1`. Record one screen video and collect Xcode/device Console entries from subsystem `com.paulsun.cubeflow`, category `DataSelection`. At the top and bottom, in Light and Dark, enter and exit selection once, letting each transition settle. Log output is one summary per transition: callback count, largest callback gap, and timestamped inset/offset/viewport changes. It contains no solve data and ends after the next callback at or beyond 0.55 s, or after 72 callbacks. Record an uninstrumented comparison first if the issue is intermittent. The timestamps can correlate a visible defect with layout and scheduling; they are not pixel or display-latency proof. If the same artifact appears without a callback gap, investigate compositor ownership independently rather than treating it as a frame stall. [Apple CADisplayLink guidance](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays).

Mounted simulator A/B matrix (32 geometry samples per appearance, both directions and both edges): window bottom safe area was 34 pt, native bottom content inset ranged from 0 to about 139 pt, and scroll offset stayed fixed within each edge/appearance group. Top was -183 pt. The two bottom fixtures started at different offsets after a native appearance/layout change, so do not compare their absolute offsets as a transition effect. The screenshot shows the native material but does not reproduce a defensibly attributable physical rectangle.

The iOS 27.0 iPhone 18 Pro simulator repeated the same matrix. Top and bottom offsets again stayed fixed within their respective groups; the maximum inset in those samples was 97 pt in Light and 139 pt in Dark. The opt-in sampler emitted 19 transition summaries, including long callback gaps (up to about 660 ms in the hosted test while it also performs screenshot/alert work). No synchronized compositor recording ties any of those gaps to the user-visible defect. The logger path was verified, not the physical cause.

## Result Cards And Battle

- Result detail had a 62 pt minimum on the **title row** whenever Share was stacked. The title is now intrinsic. The name/All Results field or profile link uses only the trailing rail where necessary. The first full-width event group clears the rail if the preceding content is short. Tall cards give their existing title/link area and actions a fixed header while the detail body alone scrolls; independent horizontal event tables remain inside that body. Fonts, labels, formatting and controls are unchanged.
- Battle still morphs the same per-player matched Glass ID. iOS 26 uses the native default animation and an explicit matched geometry glass transition instead of the custom spring transaction that suppresses the system's coordinated content effects. The earlier-iOS spring, no-motion branch, controls and timing are unchanged. [Apple matched geometry transition](https://developer.apple.com/documentation/swiftui/glasseffecttransition/matchedgeometry).

## Sharing

Two actual design sketches are under `build/native-root-nov06/`: `concept-split.png` and `concept-scorecard.png`. The split version narrowed both the result and identity columns, which gives long names and attempt rows less room. The selected compact scorecard gives the full width to the competition/person masthead, groups event/rank/primary and complementary statistics on one tinted result field, and places attempts in a separate footer. The export is 620 pt wide, with height determined by content, so it can stay near square without empty fixed space. No brand text or substitute logo. All badges use the existing compact Report visual language, including blue PR. The Highlight no longer waits for artwork it does not draw; Report still loads and renders the banner.

The short rendered sample is 1240 × 826; the long mixed-script sample is 1240 × 946. [Ordinary Light](../build/native-root-nov06/highlight-ordinary-light.png), [PR Light](../build/native-root-nov06/highlight-PR-light.png), [WR Dark](../build/native-root-nov06/highlight-WR-dark.png). All ten record/appearance combinations were inspected; the design remains pending user review.

Report's accepted geometry is preserved: no changes to typography, result order, width allocation, long-time inline packing, or single PNG. Pale filled blocks are replaced by a stronger consistent major divider on white; the finer rule remains only between rounds within an event. No border cards or shadows. Compare [previous long Report](../build/native-ui-followup/report-long-times.png) and [current long Report](../build/native-root-nov06/report-long-times.png).

## Performance Evidence

Xcode 27.2, arm64 iPhone 17 Pro simulator, iOS 26.5, Debug. The paired 10,000-ID test performs 72 toolbar predicate evaluations per sample (empty/partial/all), checks equality, and isolates the previous guarded membership scan from the new count comparison. It does not measure the Select/X frame rate. Gating row geometry removes work outside anchored range selection; no physical latency number is claimed. The existing background Data reads and range min/max optimization are unchanged.

Five paired samples in the focused run: 19.72–20.83 ms for 72 previous predicate evaluations and 0.011–0.015 ms for the count implementation. The old scan affects repeated rendering after all-selected, not the normal empty-selection transition; these timings do not assign the hitch's cause.

The focused 68-round Report remained 1680 × 9946 (1,746,868 → 1,736,803 bytes); measured wall time was 289–298 ms versus 268–277 ms in the preceding focused runs. The 512-round Report remained 1077 × 43633 (8,151,604 → 8,148,012 bytes), at 1033–1037 ms versus 1029–1050 ms. The largest bitmap remains 2,580,480 bytes. These small samples establish no export speedup and are not a peak RSS bound.

No startup prewarming, cache expansion or network changes were justified elsewhere. Timer's existing prefetch and inactive-statistics guards remain; all-solves streak aggregation remains a candidate for hardware profiling, not an assumed bottleneck. Algs' inactive trainer path remains untouched. Explore already overlaps independent loads and retains the accepted exact-target path. Settings/shared UI retain lazy mounting and existing session ownership. Battle uses its existing renderers and does not add a clock. Smart Cube is read-only. PNG rendering/encoding and memory caps are unchanged; image-size differences from the visual grouping are not an export speedup.

Five XCTest launch samples averaged 1.608 s (6.67% relative standard deviation) versus 1.522 s (0.842%) in the preceding pass. Cold Timer controls appeared in 5.18–5.29 s including XCTest polling. Mounted first / subsequent tab samples in ms: Timer 107 / 337, Data 425 / 454, Algs 592 / 430, Explore 839 / 518, Settings 475 / 356. Data's 1,000-row fixture published after 606 ms with one initial fetch. These are harness timings and do not establish a broad improvement or a stable regression. Memory and energy were not measured on device.

## Verification

- Full iOS 26.5 application suite: 1,195 cases, 1,189 passed, zero failed, six skipped. This includes 837 XCTest cases and 358 Swift Testing cases. Skips are the opt-in real-provider probe and five host Keychain tests requiring entitlements. The 3,569/4,505-solve Session test still loads only the final selection and performs no hidden Timer statistics reads.
- Focused mounted/export suite: 31 passed. Six XCUITests passed, including opening both sharing presentations, keeping All Results actions hittable during vertical scrolling, preserving independent horizontal attempt access, and closing or navigating Back. Both actual rendered result-card fixtures were inspected.
- All 60 localization files pass `plutil -lint`; `git diff --check` and the staged check pass. No strings or deployment settings changed.
- Unsigned generic iOS Debug build passed; built `MinimumOSVersion=15.0`. Existing TNoodle privacy and App Intents metadata warnings remain. This is build/metadata verification, not an iOS 15 runtime test.
- One additional test-only Report fixture passed after the complete suite. [Its complete PNG](../build/native-root-nov06/report-bilingual-banner.png) verifies a banner, bilingual competition and long competitor names, multiple events/rounds and the last record. Production source did not change after the complete suite.
- iOS 27.0 simulator cross-check: four passed, covering both Data widths and both stacked result card modes. See `ios27.xcresult`, `ios27-data-selection-trace.log`, and the original iOS 26.5 screenshots preserved under `ios26.5/`.

## Artifacts And Acceptance

Generated artifacts in `build/native-root-nov06/`: `data-toolbar-{1,2}.json`, `data-delete-{1,2}.png`, `data-delete-text.png`, `round-stacked-after.png`, `all-results-stacked-after.png`, `battle-*.png`, `report-long-times.png`, `highlight.png` (short) and `highlight-{ordinary,PR,NR,CR,WR}-{light,dark}.png` (long). The physical before screenshots were described in the brief, but not included as files with it; the previous title-row minimum is recorded above rather than substituting a synthetic before screenshot.

1. Recheck Data at both scroll edges in both appearances, collecting the paired recording/log above only if the problem persists.
2. Check the right-hand actions in round and All Results cards with long names and a vertical scroll, and review Battle reversals and Reduce Motion.
3. Review the Highlight designs and complete Report. No repeat of the accepted Smart Cube, Session switching or Recent Records scenarios is requested.

## Worktree

App source: `DataTabView.swift`, DEBUG `AppExperienceTrace.swift`, `CompetitionTabView.swift`, `CompetitionResultsStyle.swift`, `TimerLocalBattleView.swift`, `CompetitionPagedExport.swift`, `CompetitionReportImage.swift`, and `CompetitionSharePreview.swift`. Tests: `NativeUIRecoveryTests.swift`, `CompetitionPagedExportTests.swift`, `BattleMixedInputTests.swift`, and `CompetitionResultsNavigationAcceptanceTests.swift`.

`main` remains at `82b455c39`, 0 ahead and 0 behind the local `origin/main` ref. The dirty tree contains 90 modified tracked and 75 untracked entries, with no staged changes; exact pre/post status is under `build/native-root-nov06/status-{before,after}.txt`. No commit, push, reset, rebase or deployment. No physical device, Web repository or OAuth configuration was operated.
