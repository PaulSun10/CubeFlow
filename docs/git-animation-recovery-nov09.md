# CubeFlow Git animation recovery, native Data toolbar, and performance

## Continuation

The earlier short pass is retained below for provenance. This continuation uses the original brief and the evidence in [native toolbar and CJK](native-toolbar-cjk-performance-nov09.md), [native compositing](native-compositing-performance-nov09.md), [native UI recovery](native-ui-recovery-nov09.md), and [physical feedback](physical-feedback-nov08.md). The user's physical results override prior simulator conclusions.

### Executive summary

| Requirement | Evidence and status |
| --- | --- |
| Recover Select/X | Restored the tracked native toolbar insertion/removal and snappy state transaction. Both directions have visible intermediate frames on iOS 26.5. No cross-bar Liquid Glass morph is claimed. Physical motion is pending. |
| Preserve native Search; eliminate the rectangle | Genuine accessory retained. Search restoration and opening verified. Reduced app-imposed material, but a short flat surface still appears during the simulator handoff. Exact physical renderer and resolution remain unverified. |
| Manual and bulk Move | Manual appearance and disappearance recorded, bulk endpoints and destination/cancel verified. Physical motion quality pending. |
| Primary Delete and concentric geometry | Same action remains disabled at zero and red when enabled; four-digit text and icon variants are directly tappable. Both outer actions retain the native toolbar baseline. Physical corner alignment and motion pending. |
| Battle outer X | Only the diagonal inset changed; 48 pt circle and 22 pt glyph retained. Physical verification pending. |
| Performance | Existing newest-first ranks reused; paired endpoint measurements and output-equivalence tests below. No app-wide latency, memory, BLE, or energy claim. |
| Frozen features | No continuation changes to CubingChina CJK, Competition Report, Result Highlight, Competition scroll ownership, or WeiPo. Battle's other controls and timing were not changed. |

### Historical recovery

| Revision | Evidence |
| --- | --- |
| `afecf2f95`, `46e32394f`, `9f701ea00`, `f521d9966`, `5ce26da37` | Select/X already used a 0.2-second no-bounce snappy transaction. Selection actions were still an app-owned bottom inset, not a system navigation toolbar. |
| `75698955f` | Added the root system bottom-accessory architecture; the earlier root and Data implementations were reviewed separately. |
| `da9ad58d6` | Moved selection actions from the inset to one conditional native `.bottomBar` group and added tab-bar visibility control. The Data selection state also published to a root binding, which gated Search and tab minimization. |
| `5464b5ef8` | Latest tracked Data change; retains the native group, 0.2-second snappy Select/X transaction, and SwiftUI tab-bar preference. |
| Later dirty worktree | Earlier reports record a UIKit tab visibility bridge and subsequent removal, then a change to separate independently managed native items and a different Select/X spring. The failed UIKit control-host and toolbar-ownership experiments were not revived. |

Read-only Git inspection identified the tracked mechanism, not a physical build hash or proof of the reason for the old jerk. Separate accessory, tab-bar, and toolbar state updates could produce uneven choreography. The implementation selectively restores the tracked Select/X timing and single conditional navigation-toolbar group. The group is hosted as one native item on modern iOS, with an internal SwiftUI row. The root's one selection binding and genuine `tabViewBottomAccessory` remain intact. There is no separate competing Data bottom bar, manual tab hiding, or claimed cross-bar morph. The legacy selection and Search branches remain for older iOS.

In `5464b5ef8`, Select and X changed `isSelecting` inside `withAnimation`. The same state inserted/removed the toolbar group and changed the tab-bar visibility preference. The parent binding controlled accessory presence and minimization; these remained distinct native hosts. Later independently identified toolbar items allowed UIKit to decide overflow and made a conditional item insertion dependent on transaction propagation across the host boundary. The prior UIKit `setTabBarHidden` attempt acted only on tab visibility. The `SessionNativeActionStyle` history applies to a separate native primary item in solve detail, not Select/X. That helper was not rewritten. The exact historical build on the phone and the cause of its reported jerk cannot be inferred from Git or reconstructed simulator footage.

### Selection and layout

- The manual zero-to-one and one-to-zero updates now use the same spring as bulk selection, with the selection and range anchor published inside that transaction. The mounted row also animates its own width and enabled-state changes, so Move does not rely on SwiftUI forwarding a transaction across the creation of a separate native toolbar item. The existing Move sheet and Delete alert remain unchanged.
- Delete remains the same directly accessible button, including when disabled. A single containing item makes individual actions ineligible for UIKit's independent ellipsis overflow. The row's width budget uses measured localized text and Dynamic Type, chooses the trash symbol first when compressed, and preserves 44-point targets. Move can also compact to a folder while keeping its localized count as the accessibility label. The leading and trailing controls use the native bottom placement and mirror in RTL.
- Each action uses the public native Glass effect. Delete changes from neutral disabled glass to red interactive glass without replacing the button. Before this change, the iOS 26.5 four-digit baseline was tappable but its enabled Delete appeared as low-contrast white text. The replacement is visibly red in both captured appearances.
- The Data tab no longer forces the old full-width tab-bar material on modern iOS. Other tabs and older versions keep their existing background policy. The native Search pill still participates in system tab minimization; it was not moved to an inset. A transient full-width pale surface was still seen in some iOS 26.5 entry/exit frames, so the forced material was not established as the only rendering cause. See the comparison below.
- Battle's outside X moves three points toward the rounded corner where the safe area previously determined the diagonal inset, and two where the decorative minimum wins. The circle remains 48 pt, glyph 22 pt, and hit area 48 pt. The center remains within the safe area; no per-device corner radius or timing change.

### Bottom-surface isolation

The root tab controller owns Search and its tab bar; Data's navigation toolbar owns selection. Modern Data does not install the legacy Search safe-area inset. The selection toolbar's background and the new grouping item's shared background are hidden without covering the list. Removing the forced tab material did not eliminate every transitional surface. On iOS 27.0 Dark, disabling only the List's bottom scroll-edge effect removed the fading of underlying rows but did not remove the temporary full-width dark handoff surface. The test completed, but the visual hypothesis failed; that experiment was removed. Neither the list's edge effect nor the app-imposed material is established as the sole renderer. The transitional surface should not be assumed identical to the reported physical artifact until correlated with the device recording.

The final-source iOS 27.0 mounted comparison reused the existing DEBUG Search isolation switch, with identical app code and test inputs. Both variants passed; each sampled 32 frames in each appearance across top/bottom reversals. With Search on, the scroll viewport ranged roughly 719–874 pt and the measured bottom inset ranged 0–139 pt. With Search off, the viewport stayed 874 pt and the inset ranged 83–86 pt. Offsets stayed constant within each list edge in both runs. The Search-on light entry sample shows a larger flat region; the Search-off sample shows a softer transition. The frames need not represent the exact same fraction of the animation, and this does not prove absence across the complete Search-off transition. The comparison establishes accessory participation in the changing viewport, not which native backing layer paints the reported rectangle. See `search-isolation-comparison.png`, `final-search-on.xcresult`, `final-search-off.xcresult`, and the copied geometry JSONs. The shipping Search path remains enabled.

### Performance

The high-frequency range-selection path reused the complete displayed ID list and filtered its indices twice for each viewport update. The newest-first unfiltered path now reuses the existing snapshot's position map and iterates only mounted/visible IDs, without building another index or retaining another full-size array. Locally shortened lists, active filters, and alternate sort orders use a single allocation-free scan in actual display order instead. The benchmark compares old and new outcomes for both anchor directions, anchors inside the visible range, missing anchors, and stale rows.

| Workload | Historical scan median | Existing-rank lookup median |
| --- | ---: | ---: |
| iOS 26.5 Debug, 16,000 rows, 98 endpoint requests, five paired runs (final full suite) | 126.98 ms | 0.161 ms |
| iOS 27.0 Debug, same workload | 137.03 ms | 0.181 ms |

The final iOS 26.5 sample ranges were 125.29–129.17 ms before and 0.149–0.196 ms after; the iOS 27.0 ranges were 129.67–143.20 ms and 0.176–0.188 ms. The position-map build is excluded because Data already computes it for solve numbering. These numbers are endpoint-computation measurements, not end-to-end FPS, memory, or device timings. Prior Data, Core Data, chart, Algorithms, Timer, and CJK optimizations were not reverted. There was no substantiated need to reopen Timer, BLE, Guidance, Competition, or export logic. The UIKit action lookup and dispatch in the incorrect mounted toolbar tests were removed; there is now an actual XCUI action test and a separate mounted lifecycle/state test.

### Verification

- iOS 26.5 candidate: 34 focused tests passed. Final English and Arabic RTL XCUI flows: 2 passed.
- Final full application unit target on iPhone 17 Pro simulator, iOS 26.5 (23F77), Xcode 27.2: 849 XCTest passes and 361 Swift Testing passes, 0 failures, 6 skips. The skips were the opt-in real provider probe and five real-Keychain tests unavailable in this simulator host. `full26.xcresult` reports 1,216 tests at the test level; the per-device aggregate counts parameterized cases separately. The unrelated broad UI test target was not run; the new Data XCUI tests ran separately on both runtimes.
- iOS 27.0 Dark and XXXL: final focused suite 13 passed, including both XCUI flows. The first Dark trial showed a visible toolbar but XCTest reported its nested buttons as not hittable. The final test uses the public accessibility identifier to obtain each button's frame and sends a real screen-coordinate tap. It requires the bulk selection outcome, Delete confirmation and cancellation, Move destination and cancellation, and Search navigation; a coordinate tap that does not activate the target fails the test. The dedicated mounted test still independently checks actual tab/accessory ownership and selection state through rapid changes in both appearances.
- 1,021 solves, 26.5: Delete uses a text label, 70×44 pt, when it fits. 27.0 XXXL: Delete 84 pt wide at one selected solve, then 44×44 pt with trash symbol at four digits; Move compacts to 44×44 pt, and all three remain directly reachable. The screenshot and Arabic test cover placement and non-empty accessibility names. VoiceOver service, maximum accessibility sizes, and hardware motion are not certified.
- In iOS 26.5 recordings, Select and X have intermediate frames, manual and bulk Move visibly fade in and out, the bulk label crossfades, and Delete changes color in both directions. This is a native bar handoff plus animation within the toolbar, not Liquid Glass morphing between bars. See `final26-enter.png`, `final26-exit.png`, `final26-manual-add.png`, `final26-manual-remove.png`, `final26-bulk-add.png` and `final26-bulk-remove.png`. These are frame strips from actual UI taps, not a physical-device recording or a smoothness benchmark.
- Unsigned generic iOS Debug build succeeded, deployment target 15.0. No new production actor-isolation warning. Existing TNoodle release-evidence and App Intents metadata warnings remain. The simulator test build also reports existing test-only deprecations and a captured-variable concurrency warning in `CompetitionWCALiveIntegrityTests.swift:196`. Runtime logs include simulator WebKit/process suspension, QoS, appearance and geometry update diagnostics in mounted tests. No iOS 15 runtime, physical device, or iPad/Mac runtime check was performed.
- Localization: 79 string and pluralization files passed `plutil -lint`; this change adds no translation keys. `git diff --check` and `git diff --cached --check` passed. Raw evidence: `build/git-toolbar-recovery/`.

### Acceptance still needed

1. On the affected phone, scroll in both directions to minimize/restore Search, then check Select/X while Search is expanded and minimized, in both appearances, at the top and bottom of a long session. Automated checks verified accessory ownership, return, opening and measured list geometry, not a complete gesture-driven minimization trace. Record any hard-edged flash separately from the visible native movement. If reproduced, correlate its timing and screen bounds with the existing DEBUG Search-on/off experiment before changing another surface.
2. Confirm Move on manual and bulk selection; select more than 1,000 solves at enlarged text, confirm Delete stays primary and red while enabled, then cancel the alert and Move sheet. Check with Reduce Motion and VoiceOver.
3. Confirm the Battle X in both orientations. The physically accepted CJK correction and frozen Competition, Highlight, scroll-warning, and WeiPo behaviors were not changed.

### File inventory

- `CubeFlow/Views/iPhone/DataTabView.swift`, `IPhoneContentView.swift`, and `CubeFlow/Views/Shared/ViewCompatibility.swift`: toolbar presentation, animation, material ownership, and existing rank integration.
- `CubeFlow/Views/Shared/SolveSelectionRange.swift`, `CubeFlowTests/SolveManagementCloseoutTests.swift`: range endpoint computation, equivalence, and benchmark.
- `CubeFlow/Views/iPhone/TimerLocalBattleView.swift`: outer X inset only.
- `CubeFlow/CubeFlowApp.swift`, `CubeFlowUITests/DataToolbarInteractionTests.swift`, `CubeFlowTests/NativeUIRecoveryTests.swift`: isolated simulator-only DEBUG fixture, actual UI interactions, mounted lifecycle coverage, and a corrected UIButton lookup for the separate Solve Detail action.

No device operation, backend changes, reset, clean, commit or push.

## Earlier short pass (historical record)

### Status at that interruption

This pass is incomplete. The Select/X animation, four-digit Delete overflow, bottom rectangle, toolbar interaction failures, and Battle positioning remain unresolved. No physical device was operated.

### Git evidence recorded then

The most recent commit touching `DataTabView.swift` is `5464b5ef8`. Its implementation has a `ToolbarItemGroup(placement: .bottomBar)` conditional on selection, uses the SwiftUI tab-bar visibility preference, and wraps Select and X state changes in `.snappy(duration: 0.2, extraBounce: 0)`. The preceding `da9ad58d6` has the same basic mechanism. The tracked source alone does not establish which revision was physically observed to animate or why it was jerky; no historical binary or recording was correlated in this pass.

The current dirty worktree instead declares separate identified toolbar items with flexible toolbar spacers, uses a root-owned selection binding, and has an independent native tab accessory. It uses a different spring for Select/X. The earlier report `native-ui-recovery-nov09.md` describes an uncommitted UIKit animated tab visibility bridge that was later removed; it explicitly did not establish physical acceptance. The rectangle's actual rendering owner was not established.

### Change recorded then

Manual transitions between zero and one selected solve now use the same 0.32-second, 0.9-damping spring as Select All/Deselect All, while retaining the Reduce Motion check. This aligns transactions but does not prove why the prior manual transition failed or that the system toolbar animates. No other behavior was intentionally changed.

### Verification at that interruption

- `git diff --check` and `git diff --cached --check` passed.
- No tests or build were run for this single-line change. Previously reported mounted toolbar failures still require investigation using actual public accessibility/UI interactions.
- Identify the exact physically working historical revision and validate a selective restoration before changing the accepted Search accessory or corner geometry.
- Verify Move insertion/removal, direct Delete accessibility at four-digit counts, disabled/enabled styling, overflow, Search behavior, and the rectangle in both appearances. Physical verification is required.
- Battle outer X remains unchanged. No additional performance optimization or benchmark was performed.
- Changed in this pass: `CubeFlow/Views/iPhone/DataTabView.swift` and this report. All other existing worktree changes were preserved.
