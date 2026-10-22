# Competition Navigation And Color Polish Closeout

Completed 2026-10-09, continuing the preserved October 8 dirty worktree at
`c551de97919551e2ef1051a2ba45adbef16f1836`. No commit or push.
This supplements `competition-published-restoration-oct08.md` and supersedes
its navigation description and earlier test count, not its provider findings.

## Completed Behavior

- One canonical CompetitionDetailView; CubingChina remains an enrichment provider.
- China unpublished/unknown/loading/failed primary: Info / Register / Competitors,
  with Live only when the existing provider supplies a valid Live experience.
- China published primary: exactly Info / Results / Scrambles. Only validated,
  nonempty official WCA Results establish publication; dates and Live do not.
- China unpublished Info secondary: About / Regulations / Schedule / Travel.
- China published Info secondary adds Register / Competitors, in that order.
  Existing public registration content, participant list, search and Psych paths
  remain separate from official Results -> By Competitor.
- Publication while Register/Competitors is mounted preserves the corresponding
  destination inside Info. Normal Live transitions to Results; explicitly opened
  supported Live deep links remain supported. No Live transport changes.
- Invalid selections recover; failed refresh retains a validated published snapshot.
- Expired/published registration actions are suppressed without deleting history.
- China uses the established vertical primary list, one competition heading, and
  compact scrollable, localized, Dynamic Type-aware secondary Info navigation.
- Latest STEER: every unselected primary label/icon uses adaptive `.primary`.
  Selected semantic rows have their semantic background and white label/icons.
  Info has `.primary` selected background and `.systemBackground` foreground.
  This override affects only China's vertical primary styling. Secondary Info
  colors and ordinary international primary blue styling remain unchanged.

## Actual Colors And Sources

Current official sources inspected October 8, not the obsolete v1 site:
[Beijing competition](https://cubing.com/competition/Beijing-Autumn-Rivalry-2026),
[navigation component](https://cubing.com/_nuxt/Bzh0emeU.js),
[stylesheet](https://cubing.com/_nuxt/entry.6hxXwaux.css).
Downloaded evidence is retained in `/tmp/cubeflow-navigation-polish/`.

The website defines OKLCH/OKLab values. Hex below is the implemented rounded,
sRGB-clipped conversion, not a claim that the site's original CSS uses hex.
All values are centralized in `CubingChinaNavigationColors.swift`.
Foreground values apply to semantic secondary navigation, NOT unselected primary
rows after the STEER. Selected primary semantic foreground is always white.

| Category | Foreground light / dark | Selected background light / dark | Site token |
| --- | --- | --- | --- |
| About | #C10007 / #FF6467 | #C10007 / #E7000B | red-700; dark background red-600 |
| Regulations | #F54900 / #D42300 | #FF6900 / #DE4400 | orange-600 / orange-500 |
| Schedule | #D08700 / #B16A00 | #F0B100 / #C98B00 | yellow-600 / yellow-500 |
| Travel | #008236 / #05DF72 | #00A63E / #00A63E | green-700 / green-600 |
| Competitors | #1447E6 / #51A2FF | #155DFC / #155DFC | blue-700 / blue-600 |
| Register | #45556C / #ABB9CB | #62748E / #62748E | fg-muted / slate-500 |
| Results | #8200DB / #C27AFF | #9810FA / #9810FA | purple-700 / purple-600 |
| Live | #C6005C / #FB64B6 | #E60076 / #E60076 | pink-700 / pink-600 |
| Spectator Ticket | #00786F / #00D5BE | #009689 / #009689 | teal-700 / teal-600 |
| Scrambles | #BB4D00 / #DE9900 | #BB4D00 / #DE9900 | CubeFlow addition: amber-700 / dark amber-400 |

The current site's ticket navigation is teal, within the requested cyan family;
it is not literally a cyan-600 token. Ticket tokens are recorded centrally, not a
new ticket destination. Info is an adaptive neutral container, not About red.
Scrambles uses warm amber/copper from the current palette, clearly separate from
Competitors blue, ticket teal, Results purple and Register slate. It is a CubeFlow
choice, not an asserted official Scrambles color. White selected labels follow
the owner's explicit STEER rather than luminance-based black/white switching.

## Results And Scrambles Polish

- Results keeps modes, compact glyphs, rounds, dense rows, official formatting,
  record badges and profile navigation. Unselected glyph surfaces are quieter;
  glyph metrics/mappings remain frozen. Attempts use opaque adaptive gray
  (light white=0.34, dark white=0.76), with focused contrast coverage.
- Scrambles integrates round/group controls, improves number/formula hierarchy,
  spacing/wrapping and touch areas, and adds localized Copy of the exact string.
  Existing supported detail and unsupported selectable text paths remain.
- Existing scroll-view adjusted safe-area insets keep final rows above the real
  TabView bar. Verified readable bottom and bar top both 769pt, bottom inset 83pt
  in the fixture host. No guessed fixed bar-height padding was introduced.
- International navigation, blue theme, Info and Live remain unchanged. The small
  shared Results/Scrambles presentation refinements also benefit international
  pages; this does not claim every shared results pixel is unchanged.

## Verification

- Prior focused suites: **47 passed, zero failures**, confirmed from
  `/tmp/cubeflow-navigation-polish/Focused.xcresult`.
- Mounted publication-transition rerun: **1 passed, zero failures**,
  `Transition.xcresult` in the same directory.
- After STEER: only the existing full-detail rendering test rerun,
  **1 passed, zero failures** in `Steer.xcresult`; no new tests, no repeat of 47.
- `git diff --check`: passed before the final build and after report creation.
- Exactly one final unsigned generic iOS Debug build: **BUILD SUCCEEDED**,
  Xcode 27.2 beta, `CODE_SIGNING_ALLOWED=NO`, `generic/platform=iOS`.
  Log: `/tmp/cubeflow-navigation-polish/generic-ios-debug.log`.
  Only build warning: App Intents metadata extraction skipped because the app
  does not depend on AppIntents.framework. No compile errors.

Actual SwiftUI screenshot inspection, not inferred from passing unit tests:
China published/unpublished, Info/Results/Scrambles, historical Register/Competitors,
light/dark, larger localized Dynamic Type, mounted publication transitions, and
international blue navigation. Existing earlier screenshots also verify Travel
tables and the final scramble in both appearances. No screenshot of the Live
screen/transport was produced; only its navigation availability was exercised.
These are deterministic fixture screenshots, not complete live provider datasets.
The international fixture uses Toronto's identity with placeholder summary facts.

Final STEER captures are in `/tmp/cubeflow-navigation-polish/steer-screenshots/`;
`manifest.json` maps descriptive names to exported files. Representative images:

- [China Info light](/tmp/cubeflow-navigation-polish/steer-screenshots/9FE83D35-A2AD-4C3E-8DC6-CCC0E0B815B3.png)
- [China Info dark](/tmp/cubeflow-navigation-polish/steer-screenshots/5907BE1B-6045-4325-8172-9E04ACCA007E.png)
- [China Scrambles dark](/tmp/cubeflow-navigation-polish/steer-screenshots/CBA4198A-8ED3-4732-BF72-A56AF6CCF4C6.png)
- [Mounted Register publication transition](/tmp/cubeflow-navigation-polish/steer-screenshots/CEF6A1BE-893E-48FA-A006-D1B8DCB53E96.png)
- [International Info](/tmp/cubeflow-navigation-polish/steer-screenshots/623ECDF1-5C87-4766-9365-FAF31FED0F4E.png)
- [Final result above bar](/tmp/cubeflow-navigation-polish/steer-screenshots/56DC0B83-A363-498A-9D28-0E9D8ED99A3A.png)

Pre-STEER snapshots remain in `screenshots/` and `transition-screenshots/` beside
these. No full pre-navigation-change rendering baseline is available; source
snapshots are retained. Do not treat old colored-unselected screenshots as final.

## Files And Boundaries

Navigation/color pass files: CompetitionTabView.swift,
CubingChinaNavigationColors.swift, PublishedCompetitionView.swift,
en/zh-Hans/zh-Hant CompetitionPublished.strings,
PublishedCompetitionIntegrationTests.swift, and this report.
This resumed closeout changed only the two primary foreground helpers and added
this report. Existing adapter/service/published/schedule changes and build output
were preserved. No project configuration, dependencies, deployment target,
Timer, Smart Cube, BLE, Algs/CSP, icon metrics, accepted scramble diagrams,
Live transports/subscriptions, or unrelated Explore changes were made.

## Remaining Physical Acceptance

- Real provider loading/refresh: Beijing published and an unpublished China event;
  confirm historical registration, participant search/Psych and closure gating.
- Supported Live navigation/deep links and live-to-published selection handoff;
  no claim of transport or reconciliation validation from fixture tests.
- Copy/detail actions, remote organizer images/links/tables and large real datasets.
- Light/dark and large text on physical devices, including iOS 15-era safe-area
  behavior and final result/scramble accessibility above each actual tab bar.

No commit. No push. All existing working-tree changes remain preserved.
