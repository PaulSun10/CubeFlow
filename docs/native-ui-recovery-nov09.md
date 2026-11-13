# CubeFlow native UI recovery, organizer rendering, and performance

## Executive summary

This pass follows [November 8 physical feedback](physical-feedback-nov08.md) and the [preceding performance report](development-performance-nov08.md). The latest physical feedback superseded their simulator results. Data now uses an explicit UIKit tab-bar transition on iOS 26+, and the simulator records intermediate frames in both directions. WeiPo highlights the next verified original scramble token. Battle dims only the configuring player's region. Jiangmen organizer HTML reaches the intended renderer without moving adjacent structured content out of its native UI. The Report heading-to-first-row gap is shorter; the accepted Highlight is unchanged.

The Data rectangular artifact remains open. Simulator animation is demonstrated, not physical smoothness or artifact resolution. No physical hardware, Web/backend change, real OAuth, deployment, commit or push. The existing dirty worktree and DEBUG settings were preserved; no new debug switches, production sleeps, or animation masks were added.

## Requirement status

| Requirement | Result and verification boundary |
| --- | --- |
| Data Select/X | Implemented. iOS 26+ uses the existing UIKit tab controller's animated visibility API; old compatibility branches remain. Native presentation frames, hide/restore, rapid reversal, both list edges, Light/Dark, and hittable selection controls were exercised. Physical smoothness, chrome and interruption cadence remain pending. |
| Data Select All / Deselect All | Implemented and covered by the mounted 81-row selection cycle. A single SwiftUI transaction updates the selection set; only mounted rows have the existing native indicator transitions. Reduce Motion is respected. No per-row tasks or animation of off-screen rows; no user-interaction delay. Physical feel with a very large list remains pending. |
| Data rectangular artifact | Unresolved. One demonstrable overlap was removed: an installed search accessory can remain visible after UIKit hides the tab bar. The search accessory is now explicitly disabled only during Data selection, then returns. A sharp lower compositing boundary can still be seen in an intermediate simulator capture, and we have not attributed the physical black/white rectangle to a specific layer. |
| Data adaptive actions and Search | Existing width rules, four-digit count behavior, label priority, localization and hit targets retained. Toolbar titles stay single-line during animated width changes. Tests cover measured layouts, selection actions and delete confirmation. Search is still provided by the same root accessory and route; the mounted test verifies accessory removal and tab-bar restoration, not the full physical search gesture. |
| WeiPo 2x2 highlighting | Implemented. Verified prefixes drive the existing highlight capsule; iOS 15 uses a bold, underlined current token. Tests cover initial/advanced/returned highlights, both directions of a partial half-turn, deviation, and completion. This is the original scramble notation, not a guessed physical side or off-path route. Physical highlight and renderer synchronization need confirmation. |
| WeiPo intermittent Ready; PBL persistence | One concrete publication gap corrected: an authoritative A3 with a new matching A5 now propagates even if normalized stickers have not changed and the move chain is uncertified. Mounted fixture verifies that boundary and a later exactly-once positive PBL save. No claim that this was the user's isolated Ready failure or that all physical packet sequences are covered. |
| Battle independent dimming | Implemented. The original split is extended through each region's safe-area edges. Single- and dual-panel screenshots, both mounted layout/contact tests, and unchanged opponent hit handling provide simulator evidence. Verify actual landscape chrome and rotations physically. |
| Battle settings and exit | Trailing-only native Menu with a down chevron, passive leading label, compact separator, adaptive neutral selected event fill and original glyph geometry. Whole-card natural sizing wins before the constrained scroll branch, with shared symmetric insets and unchanged inner X. Outer exit follows the screen corner diagonal using the larger relevant safe-area inset and the existing touch target. UIKit has no public physical corner radius; pixel-exact concentricity across devices is not claimed. Menu interaction and corner appearance remain physical checks. |
| CubingChina organizer | Implemented for recognized organizer blocks and the existing embedded fallback. Verified against real website structure and mounted representative fixtures. Not equivalent to mounting every live document on a phone. Structured competition fields retain their original renderer. |
| Competition Report | Implemented and tested with actual PNG exports. Removes the extra event-to-first-round gap using existing line leading and row padding. No change to title font, round spacing, separators, banner/no-banner, single-PNG export, Highlight, Photos or Share flow. |
| Broader performance / cleanup | Targeted, measurable improvement in Data batch lookup plus redundant computation and renderer-lifecycle work across Data, Smart Cube and competitions. No verified whole-app speedup, BLE/SceneKit or launch claim. Algorithms, Explore, Settings, Timer and export changes outside these evidenced paths were deferred rather than speculatively rewritten. |

## Findings and implementation

### Data native ownership and animation evidence

Previously a local selection state and a root binding were written together, a SwiftUI toolbar preference changed tab-bar visibility, the root switched minimization policy, and the search accessory also entered/exited. The physical report showed a snap. Code proves overlapping responsibilities, not which private animation transaction iOS suppressed. The app now has one selection binding, the root's normal tab minimization policy stays fixed, and one UIKit owner controls the tab bar through [setTabBarHidden(_:animated:)](https://developer.apple.com/documentation/uikit/uitabbarcontroller/settabbarhidden(_:animated:)). The controller bridge restores only a bar it hid, with no manual offsets. The [SwiftUI bottom accessory](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)) retains its existing independent show/hide policy. An intermediate implementation kept the accessory enabled and a screenshot showed search overlaying selection controls; that version was not retained.

The mounted test samples the actual UITabBar presentation layer, not just a SwiftUI flag or final frame. It asserts intermediate opacity in both directions and verifies the native controller reports hidden with no accessory during selection, then visible again. Each appearance samples 32 frames across four reversals per list edge; the iOS 27 final run saw native opacity of 0.35–1.00 entering and 0.09–0.64 exiting in Light, 0.52–1.00 entering and 0.21–0.73 exiting in Dark during those interrupted samples. These are sampled ranges, not durations, easing, or compositor FPS. Screenshots still show a transient lower hard edge in some frames; do not equate the accessory overlap correction with resolution of the reported artifact.

### WeiPo

The earlier checkpoint implementation deliberately returned a nil highlight index for 2x2, even when the progress counter advanced. The existing Timer publication and highlight capsule now receive the verified prefix's next token. Off path hides the token, returning restores it, and full progress hides it and uses the existing readiness contract. No change to protocol mapping, solved timing, device ownership, Combined, or recovery solver.

Separately, the peripheral only published a snapshot boundary when its displayed facelets or trust changed or verified steps existed. This dropped valid matched physical activity in the same-normalized-state case. An advancing A3 with a matching accepted A5 now also qualifies, preserving timestamp and trust checks. The Timer still requires in-epoch activity. Duplicate/stale packets are not promoted, and a boundary does not certify a fictitious move chain.

### Battle and Report

The previous backdrop was placed above both panels. The new noninteractive layer is split at the original safe-area-adjusted divider, including unequal inset cases; configuration and contact layers keep their prior ownership. A visual pass identified that two layout-participating dividers made the Handicap control scroll at a representative size; the retained separator is an overlay and the final screenshot shows the whole control. The outer exit uses equal physical edge insets subject to the current safe area, not a per-device offset. The player's card close circles and widths are unchanged.

Report uses the existing 8 pt row padding less the heading's 3 pt trailing line leading, so the gap measured between the heading command's end and the first result label is 5 pt instead of 18 pt. The prior separator-to-heading check remains 10 pt and the previous bottom-spacing check remains 5 pt.

### Jiangmen actual website and iOS rendering

Read-only sources: [Jiangmen About](https://cubing.com/competition/Jiangmen-Open-2026), [Rules](https://cubing.com/competition/Jiangmen-Open-2026/regulations), [Travel](https://cubing.com/competition/Jiangmen-Open-2026/travel). The fetched Chinese SSR snapshots are in `build/native-recovery-nov09/jiangmen-*.html`; About has organizer hero/cards/images, Rules has a provider certification sibling before the organizer prose, and Travel uses wide rich tables. The repo's previous Jiangmen snapshot corroborates the same `prose` and `data-cc-block` pattern. No provider CSS or text was copied into the repository.

The previous WebKit size fix was not on the principal Info/Rules/Travel rendering path: server-rendered organizer content had semantic-section IDs and entered `CubingDetailDocumentBlock`'s generic rich renderer. The older WebKit branch recognized only embedded fallback IDs and was not called by that view. This explains why WebKit changes alone could not help the main path; it does not identify the exact physical line clipping algorithm.

The adapter now identifies balanced provider prose containers, preserving the native structured text before/after them and their ordering. A recognized complete server-rendered prose document avoids decoding Nuxt state merely to find the duplicate embedded document; the prior embedded and semantic fallbacks remain. Both organizer paths share one WebKit renderer. The renderer preserves heading/list/table/image/link structure, groups provider cards with an adaptive surface, clamps outer widths, and scrolls wide tables internally. A nonce-guarded in-place update applies color and Dynamic Type changes to the same document. The existing HTML sanitization, script CSP, height-message nonce and navigation allowlist remain. Representative tests exercise provider-shaped routing, adjacent certification preservation, clipping/long headings and links, tables/images, and the same WebView/document nonce across an appearance and size change.

## Performance and maintainability

| Workload | Before | After | Interpretation |
| --- | --- | --- | --- |
| Data selected-solve lookup, 1,024 existing IDs plus one missing, three paired trials on arm64 iOS 26.5 Debug, in-memory Core Data | 53.33–54.01 ms, median 53.60 ms; 1,025 fetches | 3.76–4.48 ms, median 3.89 ms; five bounded fetches | About 14x for the measured lookup only. Results equal the old lookup and exclude the other session. Not an end-to-end delete time or SQLite benchmark. |
| Data search rendering | Evaluated the same indexed filter for the empty check and the result list | Once per render | Removes a full duplicate scan for a non-empty search; no latency benchmark. Best/Worst Single also avoids a temporary materialized tuple array. |
| Completed/unchanged 2x2 progress | Rechecked exact target equivalence when asking whether fully verified progress was complete, and rebuilt the completed Set even for an unchanged prefix | Trust the target-only checkpoint count; keep the Set when the count is unchanged | Existing indexed/exhaustive equivalence regressions retained; no BLE or frame-rate benchmark. |
| CubingChina parse and WebKit lifecycle | Recognized SSR text also walked embedded data; ancestor Set copied at recursive resolve; theme and text-size changes reloaded HTML | Skip duplicate embedded lookup for recognized prose, reuse a bounded recursion path, update style without navigation | Measured by equal mounted WKWebView and unchanged document nonce across a style update; no timing or memory claim. Resolver keeps the existing cycle/depth/budget guards. |
| Export | Prior 512-round sample: 1,040 ms, 1116 x 42385 | 1,015 ms, 1116 x 42316; same 2,580,480-byte maximum strip | Separate full-suite samples and different image heights. Long-report regression checks all rows and one decodable output; no encoder speedup inferred. |

Reviewed the existing deferred Algorithms tab, active-only Explore load with stale-account checks, Settings activation, SceneKit's idle render gate and teardown, and the export actor's cancellation between strips. No new evidence justified removing those gates, changing Timer prefetch, or rewriting ownership. This pass did not collect a new cold launch, SceneKit/GPU, long-session memory or hardware energy profile. The batch lookup and WebKit work reduce specific operations without hiding required UI updates.

## Verification

Artifacts and logs are under `build/native-recovery-nov09/`. Xcode 27.2, arm64 simulators: iPhone 17 Pro (iOS 26.5), iPhone 18 Pro (iOS 27.0). No iOS 15 runtime, iPad/Mac simulator, device signing, or device acceptance. App target minimum remains iOS 15.0.

| Run | Result |
| --- | --- |
| First iOS 26.5 focused suite (`focused.xcresult`) | 86/86. A screenshot exposed an accessory overlap that endpoint assertions missed; code was corrected afterward. |
| Refined iOS 26.5 tests (`refined.xcresult`) | 38/38, including batch lookup, actual native bar visibility, same-state WeiPo boundary and export geometry. |
| Final iOS 27.0 focused suite (`ios27.xcresult`) | 26/26, including intermediate native presentation-layer frames, rapid selection, Battle both layouts, organizer style update and WeiPo save. |
| Final iOS 26.5 full unit suite (`full-unit.xcresult`) | **1,201 passed, 0 failed, 6 skipped** (848 XCTest including skips, plus 359 Swift Testing). The final Data mount passed and again captured intermediate native tab-bar opacity for each direction in both appearances. |
| Final unsigned generic iOS Debug (`generic-debug.log`) | Passed. |
| `git diff --check`, 60 localization plist files | Passed. No translations changed. |

Skipped: one opt-in real provider probe and five host-entitlement-dependent Keychain tests. Simulator logs include existing UIKit hosting/appearance warnings, some QoS inversions and WebKit process lifecycle diagnostics; these were not attributed to the physical Data artifact. The generic build retains the existing TNoodle privacy advisory and App Intents metadata warning. The built Info.plist confirms iOS 15.0 minimum. No privacy or authentication changes.

Notable local evidence: `ios27-data/data-toolbar-*.json`, `search-on/data-toolbar-*.json` (final 26.5), `ios27-data/data-delete-2.png` (intermediate, not an endpoint screenshot), `battle-one-configuration.png`, `battle-dual-configuration.png`, and `report-long-times.png`. The full run reproduced the lookup benchmark (median 51.11 ms individual vs. 3.71 ms batched).

## Remaining risks and physical checklist

1. Data on the affected iPhone: Select/X at both list edges in Light/Dark, then rapid reversals; assess animation and the rectangular edge separately. Verify the accessory returns and opens Search. Select/Deselect All and confirm the accepted four-digit Move/Delete layout, including larger text and Reduce Motion.
2. WeiPo: follow a 2x2 scramble with a half-turn and one deliberate deviation/return. Check highlight advance, Ready, a normal PBL, exactly one nonzero saved result and next scramble. A physical final state with no matched move evidence remains intentionally unverified.
3. Battle: test single/both panels in both orientations, touch only the trailing Timer Input control, check selected glyph and all controls on a compact screen. Verify the other player can stop, safe-area dimming is local, and the outer X appears concentric on the affected device.
4. Open Jiangmen About, Rules and Travel with light/dark and enlarged text. Check the adjacent native sections, end of the organizer prose, links, imagery and table pan. Remote images and arbitrary organizer styling still vary. Export one multi-event Report with and without a banner and confirm the previously accepted single-image sharing flow.

## Changed files

Paths are relative to the existing app repository. This inventory does not attribute earlier dirty changes to this pass.

- `CubeFlow/Models/PersistenceController.swift`: bounded bulk solve lookup.
- `CubeFlow/Views/Shared/CubingChinaDetailAdapter.swift`, `SmartCubeExperience.swift`, `SmartCubePeripheralSession.swift`: organizer split/resolve, state-only highlight index, checkpoint and snapshot publication.
- `CubeFlow/Views/iPhone/DataTabView.swift`, `IPhoneContentView.swift`, `SolveManagementViews.swift`, `SessionNativeActionStyle.swift`: selection and native tab-bar ownership, accessible single-line actions, data lookup/render cleanup.
- `CubeFlow/Views/iPhone/SmartCubeScrambleProgressView.swift`, `TimerLocalBattleView.swift`, `CompetitionTabView.swift`, `CompetitionOrganizerHTMLView.swift`, `CompetitionReportImage.swift`: highlight accessibility/fallback, per-player dimming/settings/exit, organizer route and rendering, spacing.
- `CubeFlowTests/BattleMixedInputTests.swift`, `CompetitionPagedExportTests.swift`, `CompetitionSharingNavigationTests.swift`, `CubingChinaDetailTests.swift`, `NativeUIRecoveryTests.swift`, `PhysicalRecoveryRegressionTests.swift`, `SmartCubeCurrentStateGuidanceTests.swift`: regressions, paired fetch benchmark and artifact isolation.
- `docs/native-ui-recovery-nov09.md`: this report.
