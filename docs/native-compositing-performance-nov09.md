# CubeFlow native compositing, rendering, and performance

## Summary

This pass follows [native UI recovery](native-ui-recovery-nov09.md), [physical feedback](physical-feedback-nov08.md), and the [prior development report](development-performance-nov08.md). The latest physical feedback supersedes their simulator conclusions. Data uses a common native Glass container for its Search-to-selection transition. The system Tab Bar is still a system Tab Bar; it does not morph into a third-party toolbar. CubingChina's WebKit view now receives a constrained width and measures the full text extent at that width. Competition's title follows its own vertical viewport. Battle's outer exit is larger; other accepted Battle behavior, Report, Highlight and WeiPo source are unchanged.

All changes are in the existing dirty app worktree. No new DEBUG switch, private API, background cover, physical-device operation, Web/backend change, commit or push.

## Status

| Requirement | Status |
| --- | --- |
| Data Select/X genuine Liquid Glass | **Implemented for app-owned Search/action glass.** Public API does not expose the system Tab Bar's glass to an app namespace. The Tab Bar still hides/shows separately. Intermediate simulator screenshots captured the accessory changing shape; physical continuity and the exact requested system-bar morph are not claimed. |
| Select All, Deselect All, Move | **Existing motion refined.** Native symbol replacement, eased bulk update and a separate low-bounce Move layout spring. Final selection, filters, Delete and Move membership are covered. Physical motion feel and real-world interruption remain pending. |
| Data bottom rectangle | **Two competing bottom owners removed.** Search is not installed as a root tab accessory while a second selection bar moves through the same area. The new common inset does not add an opaque masking surface. The physical rectangle's exact rendering layer and its resolution remain unverified. |
| CubingChina clipping | **Concrete viewport/measurement problems addressed.** Added actual Jiangmen SSR replay in a mounted production WKWebView, narrow Dynamic Type and delayed-image checks. Exact physical glyph clipping remains pending. |
| Competition scroll warning | **Ambiguous ownership removed without losing the title observation.** Title measures the separator against the outer viewport's named space. Horizontal/nested scroll views do not provide its coordinate. Original physical warning not reproduced on hardware here. |
| Battle outer exit | **Implemented.** Visible glass 38 → 44 pt; glyph 18 → 20 pt. Same 44 pt hit target, corner diagonal, and safe-area constraints. The larger radius puts the visible edge 3 pt nearer even where the safe area fixes the center; the non-safe-area minimum inset also shrinks 2 pt. Other Battle controls unchanged. Physical appearance pending. |
| Performance | **Measured gains** in schedule date parsing and Timer PB computation; cancellable Data search indexing off main, bounded Move lookup. Not a whole-app FPS, memory-footprint or device-energy claim. |
| Frozen/deferred | **Preserved:** WeiPo implementation, Competition Report, Highlight, Battle cards/internal X/inputs/handicap/timing. No iOS 15 runtime or iPad/Mac runtime validation. |

## Data native interaction and compositing

The previous `setTabBarHidden(_:animated:)` implementation drove native Tab Bar visibility and could interpolate opacity; it did not hand the bar's glass geometry to the separate `safeAreaBar`. In addition, enabling/disabling a native TabView accessory as a child safe-area bar appeared created two competing bottom presentations. A previous intermediate screenshot showed both and a sharp edge. That established overlap and a changing viewport, not the renderer of the physical rectangle.

[Apple's Liquid Glass guide](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) and [WWDC25's morphing example](https://developer.apple.com/videos/play/wwdc2025/323/) describe grouping app-owned effects with `GlassEffectContainer` and `glassEffectID`. [WWDC25's SwiftUI overview](https://developer.apple.com/videos/play/wwdc2025/256/) shows system-managed toolbar morphs during navigation and the system Search-tab transition; those are not APIs for matching an arbitrary UITabBar to another view. The installed public SDK exposes Tab Bar visibility and accessory installation, not its internal glass identity. No private Tab Bar effect or shape was accessed.

Data now has one local bottom safe-area inset inside its navigation root. Search and selection are alternatives in one stable `GlassEffectContainer`, in one namespace. Search and the leading action share the transition identity; Move and Delete have stable own identities and use the native matched Glass transition. The UIKit buttons inside the shared effect use plain content rather than creating another native glass background. The ordinary Tab Bar uses the SwiftUI visibility preference on iOS 16+; the direct iOS 26 `setTabBarHidden` bridge is gone. The iOS 15 visibility fallback is retained and non-Glass versions retain ordinary native controls. The root Tab Bar and other tabs' accessories are not recreated on Data selection.

Different kinds of motion remain separate:

- **Select/X:** SwiftUI spring response 0.36 s, damping 0.90 drives the Glass transaction and normal visibility change. No manual opacity, blur, slide or matched-geometry simulation for the shape. The dedicated Search route and selection binding remain.
- **Select/Deselect All:** one ease-in/out 0.24 s transaction updates the existing selection set. Mounted checkmarks use the system symbol replacement and ease-in/out 0.20 s; the optimized Deselect All set clearing remains intact. No off-screen row tasks or per-row state cache.
- **Move:** the existing measured destination and RTL offset remain. Only center displacement gets a response 0.34 s, damping 0.92 spring, rather than inheriting the bulk curve. Opening the destination sheet remains native; Move persistence and confirmations are independent from its movement. Reduce Motion bypasses these app animation transactions.

The mounted harness stores Light/Dark intermediate images separately from endpoint actions and exercises reversals at both list edges with enlarged text. Earlier iOS 27 endpoint checks sampled two controls while their frames were still about 1 pt beyond the bottom during a transition. The corrected harness waits for all three controls to enter the window before asserting geometry and actual hit tests; it does not accept a permanently obscured or off-screen action. The inspected Light snapshots show the accessory shape changing while the native tab surface is separate. The final iOS 27 Dark intermediate images also include a dismissing Delete confirmation from the Light iteration, so they do not isolate the Dark bottom compositing. The images are selected snapshots, not a complete recording or proof of physical motion quality.

## Rendering and scroll ownership

Read-only comparison used [Jiangmen About](https://cubing.com/competition/Jiangmen-Open-2026), [Rules](https://cubing.com/competition/Jiangmen-Open-2026/regulations) and [Travel](https://cubing.com/competition/Jiangmen-Open-2026/travel), plus the captured SSR under `build/native-recovery-nov09/`. The previous split between structured UI and organizer prose is retained. No general redesign, changes to link dispatch, or change to provider content.

The old WebKit wrapper constrained height but did not give the native document an explicit width. The first iOS 27 replay of About observed a 672 pt WKWebView during mounting and a text extent of 5,916 pt against a 4,458 pt native viewport. The iOS 26.5 run before the final width/settling change also caught About at 292 pt wide with 7,780 pt of text and only 7,418 pt of native height. These are observed layout mismatches, not proof that either remained after all late work settled or caused the user's physical clipping. The wrapper now takes the actual outer proposal rather than measuring around WebKit's content width. The JS bridge checks width and nonce, measures the flow box, overflow and the full text range, rounds upward, and coalesces updates to a render frame. Late image loads, font readiness and native viewport changes can trigger remeasurement; a height-only resize with unchanged flow skips the range scan. A supported organizer card body with an author height/overflow cap is now allowed to grow, and heading/body/table line boxes are protected. Tables retain internal horizontal scrolling. CSS, stylesheet loading, navigation and image permissions remain under the existing CSP and allowlist. Appearance and Dynamic Type update the same document without a reload. A separate late image insertion verified the view expands and still includes the trailing heading.

Final mounted replays used 292 pt width and accessibility-size text, with deterministic media replacements rather than live CDN assets. Measured text bottom / native height, in points:

| Simulator | About | Regulations | Travel |
| --- | ---: | ---: | ---: |
| iOS 26.5 | 7780.38 / 7806 | 2296 / 2300 | 4214.75 / 4215 |
| iOS 27.0 | 7840.56 / 7866 | 2320.75 / 2325 | 4262.50 / 4263 |

The purple Competition warning came from a generic `onScrollGeometryChange` wrapper attached after result presentation modifiers had introduced nested scrolling surfaces. Its inset binding was no longer used in the title equation, yet triggered recalculation. Per [Apple's modifier documentation](https://developer.apple.com/documentation/swiftui/view/onscrollgeometrychange(for:of:action:)), an ambiguous hierarchy observes only the first scroll view and logs the warning. The actual title separator now observes a named outer viewport on iOS 16+ (preference fallback on iOS 15). It publishes only changes to the clamped 28 pt title fade, not every offset/inset update. This is separate from the WebKit height owner.

## Performance and resources

| Path | Baseline | Optimized | Interpretation |
| --- | --- | --- | --- |
| CubingChina time parsing, 601 strings with fractional, whole-second, offset and invalid cases; five iOS 26.5 Debug trials | 139.93–165.81 ms, median 148.00 ms | 37.56–39.73 ms, median 38.33 ms | Results matched exactly. Reuses the ISO parsers and date display formatting within a schedule load. Parser workload only, not network or end-to-end navigation. |
| Timer PB, approximately 8,000 solves, five iOS 27.0 Debug paired runs with DNF and +2 | 133.47–162.00 ms, median 140.35 ms | 88.37–98.15 ms, median 94.30 ms | About 33% lower median; same PB set as old rolling windows. New sample includes the normal sort. Avoids per-metric compression and the window arrays plus the prior-result scan. Equal prior values still suppress PB; no change to solve timing or persistence. |
| Data search, immutable 4,000-solve index, three iOS 27 Debug trials | 97.69–109.03 ms, median 101.06 ms, on main | 66.86–73.89 ms, median 67.16 ms, off main | Identical index strings and cancellation test passed. One output dictionary and request-local event labels. Worker compute only, not Core Data I/O, typing latency or whole-app speed. |
| Data Move | One unbounded predicate for all IDs | Reuses bounded 256-ID fetch with source predicate | Validates full membership before any change; single save and original per-object rollback. Avoids parameter growth, not claimed faster for small moves. |
| WKWebView | Resize-driven sizing and duplicate scans on incidental updates | Width-checked, coalesced, no extra WebView; JS ignores unchanged height-only resize | Actual rendered bounds and same document nonce tested. No peak memory or energy claim. |

Broader review: Timer still uses the existing scramble prefetch and snapshot gates; this pass optimizes the PB evaluator rather than touching timing state. Data's previous optimized Deselect All and bulk deletion stay in place. Algorithms already caches recognition artwork with bounded cost and count and uses indexed search; no benchmark justified changing recognition or asset ownership. Explore's cancellation and cache policy are untouched; organizer and schedule are the measured/confirmed work. Settings activation and persistence were left alone. Smart Cube on-demand rendering and BLE ownership are frozen; existing regression coverage was retained. Battle input and scoring are unchanged. Report/Highlight still use the bounded, cancellable export path and retain the previous memory lease; no duplicate writer or image buffer was added. Allocation reductions above are algorithmic; no new peak RSS, frame-rate, BLE, GPU, energy or cold-start benchmark was collected.

Repeated on final source: the iOS 26.5 schedule benchmark measured 131.54–161.59 ms (median 139.04) versus 33.08–36.13 ms (median 34.22); Data search measured 95.95–98.36 ms (median 97.27) versus 64.43–65.74 ms (median 65.49). The final iOS 27 PB repeat measured 121.85–131.49 ms (median 123.88) versus 81.42–87.97 ms (median 83.29). Each pair compared equivalent outputs in the same run; different simulator loads can shift absolute times.

## Verification

Logs and screenshots: `build/native-compositing-nov09/`. Xcode 27.2; arm64 iPhone 17 Pro iOS 26.5 and iPhone 18 Pro iOS 27.0 simulators.

| Run | Result |
| --- | --- |
| Initial iOS 26.5 focused (`focused.xcresult`) | 51 passed. |
| First iOS 27 focused (`ios27.xcresult`) | 26 passed, 2 failed: first-mounted Jiangmen About bounds and transient Data endpoint action frames. |
| Final iOS 27 focused (`ios27-final.xcresult`) | 29 passed, no failures or skips. Includes real SSR, late image and style tests, Data index and native UI, Move/Battle and Timer PB. |
| Broad iOS 26.5 (`full-unit.xcresult`) | 1,210 total: 1,203 passed (including all 360 Swift Testing cases), 1 failed, 6 skipped. The only failure was Jiangmen About's native height before the final width/settling correction. Five host Keychain cases skipped for missing entitlement (OSStatus -34018); the real-provider probe is opt-in. |
| Final iOS 26.5 targeted (`ios26-final.xcresult`) | 28 passed, no failures or skips. Includes the formerly failing Jiangmen About replay, Data mounted and search tests, and the WeiPo PBL save-once regression. |
| Final unsigned generic iOS Debug (`generic-final.log`) | Passed, built minimum iOS 15.0. |
| Whitespace and localization | `git diff --check`, staged whitespace check and 60 localization files passed. No locale content changed. |

The final targeted runs used the corrected source; the broad suite was not rerun in full after the last width/settling correction. The Jiangmen snapshot replay is optional when the local provider snapshots are absent; the synthetic mounted WebKit regression does not depend on them. Intermediate visual evidence is in `ios27-final-data/` (Light/Dark, enter/exit); the Data harness verifies final native action hit regions separately. No multiple-scroll-views diagnostic appeared in the inspected simulator logs; this is not a reproduction of the original physical warning. Generic build retained the existing TNoodle privacy and App Intents metadata warnings. Xcode also reported an unavailable `simctl` when collecting diagnostics after the earlier broad failure; the result bundle and subsequent focused runs were available. No accessibility audit of every platform or iOS 15 runtime was performed.

## Remaining risks

- Data's local inset changes which view owns bottom space. On the affected device, check native tab restoration, list-edge spacing and Search hit testing, not just whether the two endpoint screens look correct. A remaining rectangle would require identifying its actual rendering surface.
- WebKit bounds tests do not certify individual glyph rasterization or live media behavior. The organizer overrides are scoped to supported wrappers; provider content with a different structure can still require investigation.
- The title tracking change removes the ambiguous observation; its collapse feel with native Competition navigation and nested result presentations still deserves on-device checking.

## Physical acceptance checklist

1. On the affected iPhone, test Select/X in Light/Dark at both list edges, normal and rapid reversals. Distinguish the system tab hide/show from the Search/action glass change. Check whether the black/white region persists and whether Search returns and opens.
2. With a long Data session, select/deselect all and watch Move move toward its new layout position. Check partial/all counts, the existing four-digit behavior, large text, and Reduce Motion; confirm Move to another session and cancel without changes.
3. In Jiangmen About, Rules and Travel, inspect the previously clipped lines before/after images load. Check full width, late content, Dynamic Type, Light/Dark, table scrolling and links. Scroll the outer competition screen and verify inline title transition and the absence of the purple warning.
4. Open Battle in both orientations and inspect the outer X. Check its target and safe-area placement while leaving the accepted inner cards as-is. WeiPo hardware work remains deferred.

## Files changed in this pass

- Data UI: `CubeFlow/Views/iPhone/DataTabView.swift`, `IPhoneContentView.swift`, `SolveManagementViews.swift`, `SessionNativeActionStyle.swift`.
- Competition and Battle: `CubeFlow/Views/iPhone/CompetitionOrganizerHTMLView.swift`, `CompetitionTabView.swift`, `CompetitionNativePresentation.swift` (optional size defaults unchanged), `TimerLocalBattleView.swift`.
- Data/Timer/Explore computation: `CubeFlow/Models/PersistenceController.swift`, `SolveSessionMembership.swift`, `CubeFlow/Views/Shared/DataTabSupport.swift`, `TimerPersonalBestState.swift`, `CubingChinaDetailAdapter.swift`.
- Tests: `CubeFlowTests/NativeUIRecoveryTests.swift`, `CompetitionSharingNavigationTests.swift`, `CubingChinaDetailTests.swift`, `TimerPolishTests.swift`.
- Report: `docs/native-compositing-performance-nov09.md`.
