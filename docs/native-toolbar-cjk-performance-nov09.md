# CubeFlow native toolbar recovery, CJK rendering, and performance

## Executive summary

This pass follows the [native compositing report](native-compositing-performance-nov09.md), [native UI recovery](native-ui-recovery-nov09.md), [physical feedback](physical-feedback-nov08.md), and [development performance](development-performance-nov08.md). The latest device report supersedes their visual conclusions. Data Search returns to the root system accessory and the selection actions return to an actual navigation toolbar. The exact Chinese reproduction was traced to native TextKit, not the organizer WKWebView. Data's derived session data, chart construction and Algorithms case sorting were optimized against equivalent outputs.

**Acceptance status:** CJK and the measured performance changes are verified in the mounted/unit harness. Data uses native owners again, but the full toolbar interaction is not accepted: the two native action discovery/interaction tests do not pass, and no end-to-end hit testing or exact animation claim is made.

No device operation, new diagnostic switch, Apple private API, backend change, commit or push. Report and Highlight design/export, Competition title scroll observation, WeiPo logic, and all Battle features other than the outer exit remain frozen.

## Status by requirement

| Item | Status and boundary |
| --- | --- |
| Data Search | Real root `tabViewBottomAccessory`, reusing the established Algs/Explore accessory host and original search request route. Search uses the system's inline/expanded placement and scroll minimization, with the previous local fallback only on pre-accessory systems. |
| Select/X | Selection mode presents the navigation stack's native `.bottomBar` toolbar. System Tab Bar visibility uses a single SwiftUI preference on modern iOS. The bars have separate native ownership. No public cross-bar shape morph is claimed. |
| Select All/Deselect All | Same actionable glass button and bar item; localized title, width and checkmark changes are separate from the Select/X transaction. |
| Conditional Move | Only present at positive selection count; no hidden disabled Move control occupies a slot. It still opens the same destination sheet. |
| Four digits, alignment, Delete | The native toolbar sets vertical position and safe areas. The measured label-or-symbol policy leaves room for native hit targets; flexible spaces lay out Move without offset math. Delete uses Apple's prominent Glass button style with red tint, not a colored rectangle. |
| Bottom rectangle | Default native toolbar background and a geometry wrapper restricting scroll content were addressed; exact physical appearance requires rechecking. |
| Chinese clipping | A mounted simulator reproduced a negative first glyph top in the exact provider title. The correction measures the actual ink and baseline in native TextKit. WebKit sizing alone cannot fix this case. |
| Other rich content | Typography follows the actual SwiftUI Dynamic Type environment. Existing link, inline control, table, selection and organizer WebKit paths remain; no CSP, nonce or allowlist change. |
| Swift concurrency | Pure `PuzzleEvent.localizationKey` switch is explicitly nonisolated. No annotation bypass, dispatch or actor hop. |
| Battle outer exit | Glass diameter 44 → 48 pt, glyph 20 → 22 pt, hit target 48 pt, minimum decorative edge inset 10 → 8 pt. Same safe-area maximum and corner diagonal in both layouts. No internal X or card changes. |
| Performance | Measured wins in session index, chart and Algorithms case ordering; details below. No device/energy/startup claim. |

## Data: Native presentation and motion

The original design was recovered from the tracked root accessory implementation and its introduction in `75698955f`. The root gates Search with the selected tab, child eligibility and the same selection binding used by Data. The child reports only eligibility; it does not independently animate accessory insertion. Search uses the existing navigation destination. The iOS 26.1+ `isEnabled` API remains on the established root adapter, with its iOS 26.0 branch and the pre-26 local Search fallback.

[Apple's toolbar guidance and WWDC example](https://developer.apple.com/videos/play/wwdc2025/323/), [bottom-bar placement](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/bottombar), and [system tab accessories](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)) document native placement and grouping. The toolbar zoom example is a presentation transition, not a public way to assign an app identity to the Tab Bar's glass. [Native UIKit toolbar-item animation](https://developer.apple.com/documentation/uikit/uiviewcontroller/settoolbaritems(_:animated:)) likewise applies to a navigation controller's own toolbar, not a morph from a different controller's tab bar. No `setTabBarHidden(_:animated:)` bridge, custom glass container, matched geometry imitation, view-level offset or opaque overlay was added.

Trials with hosted UIKit buttons in SwiftUI toolbar items and with a UIKit navigation-bar ownership adapter exposed mount and hit-testing failures. Neither adapter is retained. The shipping-source candidate declares native SwiftUI buttons and stable `ToolbarItem` IDs in `.bottomBar`, with system `ToolbarSpacer` placement. The bar uses two flexible spaces only when Move is present. The layout model only chooses text or accessible symbol fallback based on locale, width and scaled type; it does not prescribe animated coordinates or screen-corner radii. Older iOS uses `ToolbarItemGroup` with flexible spacers.

- **Select/X:** one SwiftUI selection transaction (spring response 0.38 s, damping 0.90) publishes the native toolbar and Tab Bar preferences. A system-managed change is not evidence of genuine cross-bar morphing.
- **Select All/Deselect All:** low-bounce selection spring (0.32 s, damping 0.90), retaining the stable button and original selection semantics. Existing row-symbol replacement stays independent.
- **First/last selected:** the native Move item is conditional. The selection state uses a distinct spring (0.30 s, damping 0.92) for entering/leaving the nonempty state, with no operation or tap delay.
- **Width adaptation:** native flexible spacers adapt to the changing labels. No manual Move offset or frame animation is applied. Reduce Motion opts out of app-supplied springs. Exact interruption and width-animation behavior require mounted/physical evidence.

The first simulator snapshot of the reintroduced Toolbar showed a distinct flat bottom plane. The final approach uses the public toolbar background visibility policy, removes the unused modern Search inset from the modifier tree and moves list viewport measurement to a non-sizing background, leaving the List responsible for its own scroll edge. No extra bottom color is drawn to hide it. Two later iOS 26.5 zero-selection endpoints show actual selection mode and the native Select All capsule over continuous content/background, not the flat plane. They also show insufficient contrast on the disabled Delete glyph; the source now lets the system keep that item's background when disabled and uses prominent red Glass only when enabled. The endpoint images predate that last contrast adjustment. The old `GlassEffectContainer`, shared-glass UIButton branch, duplicated positioning and manual center offset are gone. Range selection now calculates one boundary per body rather than one per overlay.

## CubingChina: Exact reproduction

The real [Jiangmen About](https://cubing.com/competition/Jiangmen-Open-2026), [Regulations](https://cubing.com/competition/Jiangmen-Open-2026/regulations) and [Travel](https://cubing.com/competition/Jiangmen-Open-2026/travel) pages and existing SSR snapshots were checked. About and Regulations have a separate certification section before organizer prose. Its heading `世界魔方协会认证比赛` becomes a structured block title, then an attributed heading in `CompetitionRichHTMLContent` and its non-scrolling `SelectableAttributedContent` TextKit 1 view. It is not inside a WKWebView or the provider's clipped CSS.

At 292 pt, iOS 27 rendered the certification section with the first line baseline at 11.04 pt, but the shaped title's ink extended to -2.70 pt. The text view had a zero top inset, so its first line could lose those pixels even though the section height was sufficient. Explicitly binding the fallback face alone did not correct the baseline; that trial was removed. The final text layout uses the actual TextKit first-line baseline and Core Text glyph bounds to reserve only the missing top pixels, rounded to the display scale. The same Chinese test measured **+0.30 pt** after the fix on both iOS 26.5 and 27.0. It does not add a Chinese-specific constant or change the font/selection model. The computation runs only for heading-first groups and only on a new attributed document or width. Calculating in text-container coordinates makes the measurement independent of the current inset and avoids iterative growth. [UIFontMetrics](https://developer.apple.com/documentation/uikit/uifontmetrics/scaledfont(for:compatiblewith:)) now uses the supplied environment trait for this native renderer's headings and body.

The mounted test obtains the actual Chinese title through the production adapter, verifies it is outside the organizer branch, and checks shaped glyph bounds against the mounted native text view. It also checks the provider English title and a mixed-script heading. Organizer replay remains a separate coverage path for narrow width, wide tables, late images, links, style updates and security. Success on those tests does not prove physical rendering on the original device.

## Performance and resource review

Paired Debug simulator measurements use the old computation alongside the production path in the same XCTest, with equal output assertions. All times are milliseconds and summarize compute only, not frame rates or full user interaction latency.

| Workload | Baseline median (range) | New median (range) | Evidence |
| --- | ---: | ---: | --- |
| iOS 27.0, session index over 16,000 newest-first solves with ties/DNF/+2, 5 trials | 22.79 (21.57–25.57) | 19.52 (16.29–22.26) | Same positions, PB IDs and bounds. Moves one combined pass off main, with cancellation and source-generation checks before publication. Eliminates mapped tuple array and duplicate result conversion. Worker time excludes task launch, persistence and rendering. |
| iOS 27.0, 20,000 chart solves with mixed results and equal dates, 5 trials | 114.31 (113.74–114.77) | 45.79 (40.19–47.83) | Identical plotted points and histogram bins, including a Square-1 marker in an invalid solve. Sorts valid points instead of copying/sorting all solve records, builds one time array, avoids repeated event resolution. |
| iOS 27.0, 340 real CSP cases sorted by slice count, 5 trials | 90.73 (89.63–92.17) | 4.56 (4.43–4.63) | Same full order, stable ties; likely/unlikely also compared. Computes each expensive notation-derived key once and sorts lightweight indices. No global cache or additional retained result state. |

Data's earlier bounded persistence operations, Timer PB rolling metric work, search-index worker and date formatter reuse remain intact. Timer still prefetches and discards superseded scrambles; no scheduling changes were justified. Settings uses deferred tab activation and existing off-main imports. Explore's competition loading has keyed coalescing/cancellation, bounded semantic caching and organizer WebKit reuse; no evidence justified changing network/cache ownership. Smart Cube BLE/Guidance retains its device identity, task cancellation and stale-result rejection; SceneKit keeps the accepted on-demand lifecycle. Battle state and timing are frozen. Report export already limits strips, uses an export lease and removes temporary artifacts on failure; no changes to the accepted output or share path. No peak RSS, GPU, BLE, cold-start or energy data were collected. The memory reductions above refer to eliminated temporary arrays and repeated parsing, not measured process peak memory.

## Verification

Evidence is in `build/native-toolbar-nov09/`. Xcode 27.2, arm64 iOS 26.5 iPhone 17 Pro simulator and iOS 27.0 iPhone 18 Pro simulator.

| Run | Result |
| --- | --- |
| iOS 27 broader focused (`ios27-focus.xcresult`, earlier Toolbar trial) | 74 tests: 72 passed, 2 Data mounting tests failed, 0 skipped. Includes the exact CJK fixture and organizer replay, performance equality, Battle, and WeiPo regression. |
| iOS 26.5 broader focused (`ios26-focus.xcresult`, earlier Toolbar trial) | 74 tests: 73 passed, 1 Data mounting test failed, 0 skipped. The CJK and workload tests passed again. |
| Native declarative Toolbar runs (`ios26-declarative.xcresult`, `ios27-declarative.xcresult`) | On each simulator: the exact CJK test passed; rapid Toolbar actions and wide Delete action discovery timed out. |
| iOS 26.5 endpoint diagnostic (`ios26-endpoint.xcresult`) | Both Data mounted tests still failed to find the exposed UIKit bar items; both endpoints show a mounted native toolbar. In addition, an iOS 27 trial's runner failed to launch with Mach -308; later retries launched and reproduced the Data timeout. |
| Final unsigned generic iOS Debug (`generic-closeout.log`) | **Build succeeded** on the final source, including the disabled Delete contrast correction. Deployment target is iOS 15.0. The `localizationKey` actor-isolation warning is absent; existing TNoodle packaging and App Intents metadata warnings remain. |
| Static checks | All 79 localization resources linted; staged and unstaged `git diff --check` passed. No new localization keys or Info.plist changes. |

The Data mounted harness drives real state handlers and inspects public UIKit bar item exposure; it is not an XCUI touch run. The endpoint evidence distinguishes visible placement from the unresolved accessibility locator or interaction issue. It does not prove four-digit placement, Delete confirmation on the final path, all-state geometry or the absence of a rectangle on device. The earlier full unit run from the preceding pass was not repeated for this pass. Simulator accessibility label configuration is covered in source; no VoiceOver session or iOS 15/iPad/Mac runtime was performed.

## Physical acceptance

1. On the original iPhone, scroll Data both ways to minimize/restore the real tab accessory. Open Search, return, then rapidly reverse Select/X at the top and bottom in both appearances. Judge the native bar motion separately from cross-bar shape morphing, and check for any hard-edged rectangle.
2. Test zero/one, Select All/Deselect All and 9 → 1,000+ → 9 in a long session; watch Move and width/position changes. Check VoiceOver, large text, RTL, and Reduce Motion, then exercise Move and Cancel/Delete confirmation.
3. In Jiangmen About and Regulations, revisit the exact Chinese title. Compare English and mixed-script text at large sizes; check native links, then organizer media/tables/links in Travel. Ensure the competition title still collapses normally.
4. Open Battle in both orientations and confirm the larger outer X and its hit target. Do not revalidate or change WeiPo behavior until its hardware is available.

## Changed files in this pass

- Native Data: `CubeFlow/Views/iPhone/IPhoneContentView.swift`, `DataTabView.swift`, `SessionNativeActionStyle.swift`.
- CJK: `CubeFlow/Views/iPhone/CompetitionTabView.swift`, `CubeFlow/Views/Shared/ContentInteractionSupport.swift`.
- Performance and isolation: `CubeFlow/Views/Shared/SessionSolveTrend.swift`, `AlgCaseOrdering.swift`, `CubeFlow/Views/iPhone/TimerOptions.swift` and the Data session derivation above.
- Battle: `CubeFlow/Views/iPhone/TimerLocalBattleView.swift`, `CompetitionNativePresentation.swift`.
- Tests: `CubeFlowTests/NativeUIRecoveryTests.swift`, `CompetitionSharingNavigationTests.swift`.
- Report: `docs/native-toolbar-cjk-performance-nov09.md`.
