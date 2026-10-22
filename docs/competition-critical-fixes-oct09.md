# Competition Critical Fixes And Visual Consistency

2026-10-09. Continued the existing dirty worktree at `c551de97`, without resetting,
committing or pushing. This supersedes the earlier report's amber Scrambles
decision and China custom-title/Results-row presentation, not its provider work.

## 1. Scrambles Freeze: Demonstrated Synchronous CPU Work

The request path is selection -> PublishedCompetitionScramblesContent -> async
PublishedCompetitionService.scrambles -> URLSession -> actor-side decode/group ->
main-actor assignment -> SwiftUI body. No scramble diagram is generated just by
opening this destination; the existing detail sheet remains selection-driven.

The old view derived `events`, `eventID`, `eventSets`, `roundKeys`, `roundID`,
`roundSets` and `currentSet` through computed getters. Predicates called those
getters again for EACH element. Round sorting also rebuilt eventSets for each
comparison. Even the fallback `currentSet` lookup evaluated roundSets twice.
This multiplied synchronous selection work inside SwiftUI rendering. It was not
just an asynchronous screen waiting on a 60-second network timeout.

Evidence is retained in `/tmp/cubeflow-critical-fixes/`:

- Fresh official WCA Beijing scramble response: 166,903 bytes, 618 rows, 92 sets.
  URL: https://www.worldcubeassociation.org/api/v0/competitions/BeijingAutumnRivalry2026/scrambles
  SHA256: `1c2da9df4fd20c8a83d66b87b7e8ee5b7b0dd7cf404a2baa31cd2279bbfc21dc`.
- An offline Swift probe reproducing the old getter chain, without networking or
  SwiftUI layout, took **14,901 ms for ONE currentSet resolution**, rebuilding
  events **146,096 times**. Multiple view/binding accesses can compound this.
- The new production selection type, using the same response metadata/order,
  resolved the selection in **0.124 ms** in the same unoptimized host probe.
- iOS Debug regression: **1,000** full-size selections in **47.4 ms**.
- Actual mounted SwiftUI fixture with **618 rows / 92 sets**: first visible row
  **43.2 ms**; actor-side load/decode/group/assignment **5.6 ms**.
- A separate 1.2-second delayed-response fixture showed the loading spinner;
  a main-actor heartbeat and navigation away/back remained responsive. The
  cancelled/reopened view joined the same in-flight request: **one request**.

Fix: PublishedScrambleSelection resolves each selection level once into local
values, using a per-resolution round dictionary and direct option metadata.
The body and bindings reuse that snapshot; no nested derived getters in predicates.
Event changes still clear dependent round/group selections. Valid selections,
fallbacks, ordering, normal/extra separation, exact official strings, service
coalescing/caching, and the existing detail sheet remain intact. DEBUG assignment
timing and first-visible-scramble hooks support further hardware validation.

This establishes and fixes a reproducible main-thread-blocking path. It does not
retrospectively prove every millisecond of the owner's particular physical hang:
that device run did not include a stack trace. Physical acceptance remains below.

## 2. Tiny Inline Title

The detail page had `usesNativeDetailNavigationHeader == false` for BOTH providers.
China's collapsed title was a custom principal VStack: 14pt title, 11pt section
subtitle, 300pt maximum width, and title `minimumScaleFactor(0.35)`. Long titles
could shrink toward 4.9pt. This was not a nested navigation-stack defect or a
Results-specific title string. Selecting Results added the subtitle and exposed
the same custom shrink-to-fit path.

China now uses the existing navigation container's native `.navigationTitle`
and `.large` mode, not that custom principal view. The duplicated content title
is removed; the competition identity/title string and navigation hierarchy remain.
Native large titles can truncate long names, as UIKit normally does, instead of
shrinking the font. The complete title remains the navigation item's title.

The parent competition list customizes the shared navigation bar with 15pt inline
fonts. CompetitionNativeDetailTitle temporarily clears only inherited title-font
overrides, retaining the appearance's other attributes and restoring the saved
appearances on exit. No replacement title font size is hardcoded. All applicable
standard/compact/scroll-edge variants are handled with availability checks.

Mounted tests cover Info / Results / Scrambles, expanded and collapsed, light and
dark. They verify the native navigation item, no custom titleView, default UIKit
font descriptor, large-title capability and actual 17pt inline label. Large and
inline screenshots were inspected, not inferred from compilation. UIKit fills
its default font attributes when overrides are removed; the tests compare those
defaults rather than incorrectly requiring nil attributes.

The existing international custom-title/header path remains unchanged. The source
did NOT support the initial assumption that international detail already used
native large titles; this pass avoids silently changing that approved path.

## 3. Palette Verification And Sky Blue

Re-fetched the current [Beijing page](https://cubing.com/competition/Beijing-Autumn-Rivalry-2026)
and its [stylesheet](https://cubing.com/_nuxt/entry.6hxXwaux.css).
The [navigation component](https://cubing.com/_nuxt/Bzh0emeU.js) defines the
semantic foreground/selected-background token pairs. Light values come from the
base theme; dark values from `.dark` overrides, with base fallback when absent.
Some dark orange/yellow tokens are intentionally darker, not accidentally swapped.
The original mappings were already correct and are retained. Hex is the rounded,
sRGB-clipped conversion of the site's OKLCH/OKLab tokens, not original hex CSS.

| Category | Foreground light / dark | Selected background light / dark |
| --- | --- | --- |
| About | #C10007 / #FF6467 | #C10007 / #E7000B |
| Regulations | #F54900 / #D42300 | #FF6900 / #DE4400 |
| Schedule | #D08700 / #B16A00 | #F0B100 / #C98B00 |
| Travel | #008236 / #05DF72 | #00A63E / #00A63E |
| Competitors | #1447E6 / #51A2FF | #155DFC / #155DFC |
| Register | #45556C / #ABB9CB | #62748E / #62748E |
| Results | #8200DB / #C27AFF | #9810FA / #9810FA |
| Live | #C6005C / #FB64B6 | #E60076 / #E60076 |
| Ticket | #00786F / #00D5BE | #009689 / #009689 |
| Scrambles, CubeFlow addition | #0069A8 / #00BCFF | #0069A8 / #0077A8 |

Scrambles foreground uses current sky-700 light / sky-400 dark. Its dark selected
fill is a deeper sky variant to retain at least 4.5:1 white-label contrast.
Both selected fills pass that contrast test. Amber/copper is removed. Hue tests
cover separation from blue, teal, purple, yellow and green. The entire table has
deterministic exact-channel coverage for all four light/dark roles.

Primary unselected text/icons remain adaptive `.primary`; selected semantic rows
use white. Info remains neutral `.primary` fill / `.systemBackground` foreground.
The horizontal China-only Info strip retains its semantic foregrounds. No China
semantic colors are applied to ordinary international navigation.

## 4. Actual WCA Live Row Reuse

Inspected CompetitionWCALiveRoundDetailView's existing compact results table, not
the separate wide summary table. Extracted its actual header, cells, statistic
values and row into CompetitionResultTable.swift. The real Live screen now calls
these shared components; its existing result-dialog helper calls delegate to the
same cells. Live statistics selection, formatting, advancement colors, dialog
behavior, transport, subscriptions and state machine are unchanged.

Published rows now call the same components with official published presentation
values, not fake Live models. Retained Live conventions: 34pt core row, 40pt rank
column, 14pt text, statistic widths/order/emphasis, record-tag placement, dividers,
small-radius table surface and subtle shadow. Published attempts remain a compact
second line; DNF/DNS, official ranks, means, best-of ordering and record tags are
preserved. Names truncate like Live rows; complete names remain available through
accessibility/person navigation. Existing top mode/event/round controls remain.

Source comparison verifies Live row/delegate replacement only, without changing
Live transport/state. Formatting tests validate the published adapter; inspected
published screenshots verify the extracted table rendering. This is not a claim
that a live network session, advancement update or profile interaction was tested.

## 5. Verification And Screenshots

Focused suites only: PublishedCompetitionTests **14 passed**;
PublishedCompetitionIntegrationTests **25 passed**. Total **39 passed, zero failed**.
`/tmp/cubeflow-critical-fixes/FinalFocused.xcresult` and `final-focused.log`.
Early runs caught missing delegates/import and incorrect nil-font assertions;
those were corrected, not omitted from the final run. No unrelated suite ran.

Exactly **one** unsigned generic iOS Debug build: **BUILD SUCCEEDED**.
Xcode 27.2 beta; `generic/platform=iOS`; `CODE_SIGNING_ALLOWED=NO`.
Log: `/tmp/cubeflow-critical-fixes/generic-ios-debug.log`.
That build reported three actor-isolation warnings from passing a main-actor
helper through Optional.map, plus the existing App Intents metadata warning.
Afterward the three function references were replaced with equivalent direct
main-actor calls. The final helper passed standalone arm64 iPhoneOS/iOS15
type-checking with zero diagnostics (`title-iphoneos-typecheck.log`). No second
generic build was run; the 39-test run predates only this equivalent call-site
cleanup. `git diff --check` passes on the final worktree.

Actual SwiftUI images inspected: native expanded/inline title; China selected
Scrambles light/dark; compact Results with attempts/record badges; international
blue navigation/results; larger localized Info navigation; full-size scrambles;
responsive loading spinner; final result/scramble above the real tab bar.
Fixture snapshots are not full live-provider/device acceptance.

Final attachments: `/tmp/cubeflow-critical-fixes/screenshots/manifest.json`.

- [Native expanded Results title](/tmp/cubeflow-critical-fixes/screenshots/9A6BA75C-EA5F-435A-BF35-79A6F943CC5F.png)
- [Native inline Results title and compact table](/tmp/cubeflow-critical-fixes/screenshots/AA230E03-BF73-4DD1-A066-5C5F740DB24B.png)
- [Sky Scrambles light](/tmp/cubeflow-critical-fixes/screenshots/2F31757C-B508-4622-8777-DEE99232840B.png)
- [Sky Scrambles dark](/tmp/cubeflow-critical-fixes/screenshots/0592A778-A59D-4365-B73D-94B5011CC1B4.png)
- [Full-size Scrambles](/tmp/cubeflow-critical-fixes/screenshots/18544A1A-5013-495A-834F-FA54C95B09C3.png)
- [Delayed loading](/tmp/cubeflow-critical-fixes/screenshots/137728D9-3A9B-41AD-B659-447A7DBBD447.png)

## 6. Completion Audit And Scope

- Freeze investigated before edits; old CPU path reproduced and measured offline.
- Bounded production selection, full-size first-render and delayed navigation tests.
- Native China title mounted/inspected across all destinations/appearances.
- Exact original four-role palette verification and contrasting sky-blue replacement.
- Actual shared Live row/header/value components, official semantics preserved.
- Publication lifecycle, historical Info subsections, optional Live, identity and
  official data preserved, with existing focused regression coverage still passing.
- iOS15 source compatibility retained; no project/deployment-target changes.
- Actual screenshots inspected, whitespace check passed, one generic build passed.
- All inherited dirty files preserved; no unrelated system changes or Git writes.

This pass changed PublishedCompetition.swift, PublishedCompetitionView.swift,
CompetitionTabView.swift, CubingChinaNavigationColors.swift,
PublishedCompetitionTests.swift, PublishedCompetitionIntegrationTests.swift;
added CompetitionNativeDetailTitle.swift, CompetitionResultTable.swift and this
report. Inherited CompetitionService/adapter/identity/schedule/localization changes
remain preserved. No Timer, Data, Algs, Smart Cube, BLE, other Explore, accepted
scramble diagrams, glyph metrics, Live transports or subscriptions were changed.

## 7. Physical Acceptance Still Required

1. Open Beijing Scrambles cold and warm; switch Info/Results/Scrambles during slow
   network loading; cycle event/round/group, then return and pull to refresh.
   Check immediate response, loading state, no repeated request bursts and no hang.
2. From the real competition list, push/pop China detail and scroll each primary
   destination. Check native collapse, long localized names, Dynamic Type, and
   restored international/list title appearance after leaving China detail.
3. Compare sky-blue selection and secondary colors in light/dark on physical displays.
4. Exercise published person/profile, means/rare formats, DNF/DNS, badges and
   attempt readability. Check a real WCA Live round and its dialog/advancement updates.
5. Verify copy/detail sheets and final-row reachability on older supported iOS,
   preserving exact official text and the existing scramble diagrams.

No commit. No push.
