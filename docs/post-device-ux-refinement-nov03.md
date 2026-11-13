# Post-Device UX Refinement - 2026-11-03

## Implemented

- Inline Keypad now has one centered interpreted-time display, a localized secondary empty placeholder, and a stable three-column circular keypad. Bottom row: Delete / 0 / Save. Raw digits remain internal. Removed Clear, separator keys, the extra raw/preview row, full-width Save, and candidate-switching UI. Default Keyboard still accepts explicit separators; both interfaces share parsing and saving.
- Save reuses `SessionNativeActionStyle.configuration` and the exact `UIColor.systemBlue` source used by Data > Sessions > Edit. Its compact native capsule has a single-line, bounded Dynamic Type title; this fixes the two-line/expanded Glass shape found during accessibility screenshot review. Numeric/time text still scales. Hold-delete cancellation, haptics, Reduce Motion feedback, assignment ownership, and duplicate-save protection are preserved.
- Scramble and keypad now share one vertical layout owner. A nested geometry proposal supplies the real remainder after top controls, so header allocation does not depend on asynchronously measured controls/input heights. This removes the measured approximately 40-point overlap between the former independent branches at large text sizes. No new clipping, arbitrary font reduction, scrolling compensation, footer relocation, or normal-Timer layout change.
- Classic temporarily resolves to Split only while Inline Keypad is active. The stored Classic preference is not changed and naturally resolves back when that condition ends.
- The absent/default Fixed preference is now `X:XX:XX.XXX`; explicitly saved formats remain unchanged. Tests cover `921 -> 9.21`, `6789 -> 6.789`, `110013 -> 1:10.013`, and `123456789 -> 12:34:56.789`. All nine formats and explicit-separator compatibility remain. Smart keeps session/event history ranking but selects automatically. Removed the settings explanatory paragraph.

## Competitions

Confirmed three separate issues: My Competitions bypassed the shared name cache; Traditional Chinese was excluded by a Simplified-only guard; and the lookup-key `??` chain could bypass suffix removal/case normalization. These are corrected using the same shared cache, not a second name-fetch mechanism. Old disk keys are normalized on read; Unicode names are retained. Matching available Chinese names no longer require an explicit CubingChina website field. English remains official/fallback presentation.

Chinese titles already present in persisted detail sections now populate that shared name cache. A delayed catalogue request merges, rather than erases, a title learned meanwhile from a detail page. My Competitions reads available names before publishing; optional background warming changes storage only, not visible rows. Its participation checkmark is vertically centered with the name/status row. Existing Browser cache-first publication, identities, self-sizing, and scrolling remain untouched.

The account/search competition-detail entry previously required a fresh summary API request before mounting details. It now displays a matching cached public summary immediately, then revalidates. Successful lookups persist public metadata in a bounded 128-entry, 30-day cache; existing query snapshots can also supply a same-language summary. Query-cache capacity is not consumed by individual lookups. The existing cached-content notice is reused while that summary is unvalidated/offline. Detail sections retain their existing non-Live disk hydration and empty-failure merge protection.

This is not a universal offline database. Uncached competitions still fail honestly. Private My Competitions account responses have no new persistent cache; an already-mounted page is retained on refresh failure, but cold offline account-list loading can still fail. Live/competitor/ticket freshness policies and transports are unchanged. The physical error's exact entry path was not reproduced on hardware; the confirmed network-only summary gate is fixed, not every possible WCA failure.

## Charts and Chat

Histogram/Graph now have a stable readable summary, sparse time-formatted axes, light gridlines, explicit useful domains, separated histogram bars, and fewer point symbols for dense data. Every solve remains in the line; selection still exposes exact values. Linear interpolation avoids invented smoothing extrema. Selection rules are drawn once, not once per data point/bin. Removed plot padding that visibly painted bars over axis labels. Statistical snapshots, penalty handling, bins, and values are unchanged. iOS 15 retains its existing unavailable-chart presentation; Charts remains iOS 16+.

Native CubingChina chat is currently read-only: its transport provides GET messages and intentionally has no CubingChina cookie/credential session. The current [official Live page](https://cubing.com/competition/Beijing-Autumn-Rivalry-2026/live) and its public [Live UI module](https://cubing.com/_nuxt/DJ4m7igK.js) / [client wrapper](https://cubing.com/_nuxt/wD8pkf77.js), inspected November 3, expose sending, `canSend`, anonymous-login, and mute restrictions. Therefore sending has not disappeared upstream, but WCA login alone does not establish an authenticated CubingChina session. No authenticated POST or protected endpoint probe was performed. The existing official-website link is now always available in modern chat, not only after a load error. Native posting remains deferred rather than bypassing authentication.

Startup is unchanged. No demonstrated low-risk cause for the brief dark interval justified disturbing the physically successful launch improvements or adding a splash screen.

## Verification

The final input/UI cohort passed **17/17**. An additional final name-cache race test brings feature coverage to **18 distinct passing tests** across focused runs. These exercise parser/defaults, both interfaces saving the displayed value once, hold-delete cancellation, 320/768-point fitting, and mounted 320-point accessibility-size layouts for 3x3, Square-1, and a deterministic 100-move 7x7 fixture in Cards, Split, and Classic fallback. Assertions check the actual rendered scramble text inside its header, disjoint keypad bounds, reachable display/Save, unchanged stored preference, and single-line Save typography. Chart fixtures cover empty, single, and 2,000-solve datasets in both modes/appearances; count localization and existing numerical regressions are checked.

Aggregate latest-per-test results: **121 passed / 4 failed / 0 skipped**, 125 distinct XCTest cases across selected runs, not a single all-green run. Outstanding tests were retained:

- `CompetitionBrowserCacheTests.testActualBrowserKeepsCachedRowsWhenOptionalLocalizationFails`
- `CompetitionBrowserCacheTests.testActualBrowserRejectsLateCachedLocalizationAfterSameQueryRefresh`
- `CompetitionSectionLoadingTests.testPublishedPresentationUsesCanonicalRowsWithoutLiveIDsOrAdvancement`
- `CubingChinaModernLiveTests.testExactWCAIdentityNoNameCaseOrMissingIDInference`

The first two hit the existing list-interior precondition at offset -116 rather than greater than -115 before suspended localization is released; they cannot establish that interior-scroll comparison. The latter two assert nil published advancement and reject normalized WCA-ID spelling, respectively, while their unchanged production rules return advancement and canonicalize case/whitespace. Those test files and rule owners are hash-identical to this task's baseline. They were reported, not changed to force a pass. Top Cubers sizing/packing/animation, scramble lifecycle/reservation/position, snapshot cache, numerical trend regressions, official participation, and Live progress passed in the selected runs.

Final-source unsigned generic iOS Debug build: **PASS**, Xcode 27.2, arm64, iOS 15.0 deployment target. Three generic Debug builds passed as screenshot and cache-race corrections were incorporated; the last covers final production source. `git diff --check` and all three changed strings-file `plutil -lint` checks: **PASS**. Existing TNoodle privacy/AppIntents/run-script warnings were not addressed in this task.

Exact commands, logs, xcresults, baseline hashes, public research snapshots, and inspected images are retained in the ignored directory `/Users/paulsun/Desktop/Projects/CubeFlow/build/post-device-ux-nov02/`. Final evidence: `ux-verified.log`, `names-final.log`, and `debug-build-final.log`; earlier runs and failures remain available. No physical-device acceptance is claimed.

## Changed Files and Safety

Repository root: `/Users/paulsun/Desktop/Projects/CubeFlow`. Fourteen existing files changed; three added including this report:

```text
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/ManualTimeInput.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/CompetitionService.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/ManualTimeEntry.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/TimerTabView.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/SettingsTabView.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/DataTabView.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/CompetitionTabView.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/Explore/ExplorePublicDataViews.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/iPhone/WCAMyResultsView.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/en.lproj/Localizable.strings
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/zh-Hans.lproj/Localizable.strings
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/zh-Hant.lproj/Localizable.strings
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/ManualTimeInputTests.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/ManualTimeEntryLifecycleTests.swift
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Views/Shared/CompetitionSummaryCache.swift (new)
/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlowTests/PostDeviceUXTests.swift (new)
/Users/paulsun/Desktop/Projects/CubeFlow/docs/post-device-ux-refinement-nov03.md (new)
```

All pre-existing changes remain; no baseline files deleted. Confetti, startup/reservation code, Smart Cube, OAuth, TNoodle internals, Live model/transport/session correctness code, and project.pbxproj remain unchanged from the starting worktree. No commit, push, device operation, deployment, release, upload, or software installation.

## Physical Acceptance

1. In Cards and Split, enter/save the four default-format examples, then test rapid entry, hold/release deletion, and explicit Default Keyboard separators. Confirm the saved time and scramble match the display.
2. With Classic stored, switch Inline Keypad on/off and confirm temporary Split/restored Classic. Check 7x7, Square-1, large text, VoiceOver, Reduce Motion, and very short windows. Simulator bounds do not establish physical Glass/haptic quality or every top-control/window configuration.
3. In both Chinese languages, open a previously loaded Chinese detail and My Competitions; verify matching names. Open the same cached competition from account/search in airplane mode, then an uncached one. Verify cached notices, online revalidation, unchanged scroll behavior, and no stale Live data.
4. Exercise chart selection on sparse/dense real sessions in light/dark modes; confirm selected values/counts. Use the official chat link and the website's own login if posting is desired.
5. Confirm the already-accepted fast launch, tab switching, foreground restoration, Browser scrolling, and Top Cubers disclosure remain intact. The brief launch dark interval remains uninvestigated physically.
