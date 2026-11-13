# Performance, Battle and Sharing continuation - 2026-11-03

## Scope and preservation

Resumed the existing dirty `main` worktree, not a clean checkout. The initial
status, patch and file hashes are retained under the ignored
`build/performance-battle-sharing-nov03/` directory. Existing Timer launch,
manual-entry, competition caching, Live, algorithm and UI changes were retained.
No physical device, account authorization, backend, deployment, commit or push
was used. This is an iPhone implementation with iOS 15 deployment support, not
an iPad/Mac redesign.

## Performance and Smart Cube

- Generated immutable, bounded 2x2/3x3 face-move permutation tables from the
  existing integer-geometry implementation. Canonical face turns and exact
  short-path search share these tables. Slice-move semantics are unchanged.
  Tests compare all 18 moves over 50 successive states per puzzle against the
  independent original geometry.
- Comparable Debug simulator microbenchmark, 1,000 turns, three trials:
  2x2 approximately 29.3 ms to 2.7 ms; 3x3 approximately 53.8 ms to 5.1 ms.
  This is about 10-11x for this primitive, not BLE latency, device FPS or an
  end-to-end solver speed claim. Raw trials are in the test logs.
- Removed the default 120 ms Guidance trailing settle. Latest requests yield
  once to coalesce synchronous work; independent exact search does not queue
  behind old native solving. Existing identity, source, target, generation,
  device, sequence, cancellation and trust checks still reject obsolete work.
  A native worker retains ownership until it actually returns.
- Rendering uses a lifecycle-owned CADisplayLink at the display's supported
  cadence rather than an independent 120 Hz Timer. Existing move animation,
  TPS, interpolation and reconciliation are unchanged. This does not introduce
  idle-render suspension or establish a GPU/energy improvement.
- Added Scramble Navigation to a connected 3x3 management view. It accepts an
  explicit target scramble and solves from that device's authoritative current
  state; turns, policy changes, reconnects and new targets invalidate old work.
  Verified routes are distinguished from proven shortest HTM routes. Exact
  complete search through depth three can establish that proof; an ordinary
  Min2Phase answer is not labeled globally optimal. The prototype does not
  invent 2x2 physical-face mappings or support arbitrary puzzle notation.
- Fixed the malformed nested `UILaunchScreen` dictionary and provided an
  adaptive native launch background. No fake splash, delay or eager all-puzzle
  initialization was introduced. First-display diagnostics are DEBUG opt-in;
  persistence-relative time is not Apple's process launch metric. Physical
  black-frame/launch-animation timing is still an acceptance boundary.

The pinned twips review in `smart-cube-root-guidance-oct20.md` was reused and
the upstream FFI was rechecked. Its existing C entry points expose scrambling,
not a production iOS source-to-target search adapter. The reviewed FFI also has
an explicit returned-string ownership TODO. No new dependency or toolchain was
installed; there is no honest twips iOS size/RSS/latency benchmark to compare.
Keep the bounded native solver plus verified exact short search for now.
Sources: [twips FFI](https://github.com/cubing/twips/blob/a9d702a2a3edfea7ddec001c8e1d037214705903/src/ffi/lib.rs),
[prior full evaluation](smart-cube-root-guidance-oct20.md).

## Face-to-face Battle

- Each player has independent event, Touch/Manual/Smart input, manual format,
  handicap and connected-device configuration. Both compact configuration
  panels may be open simultaneously. A cube cannot be assigned to both players.
- Smart subscriptions use the assigned peripheral session, never Timer's
  globally selected device. Supported Smart events are 2x2, 3x3, OH and 3BLD;
  this does not add hardware support for other puzzles.
- For two Smart Cubes, both authoritative targets must match before the first
  legal start. Early turns do not start and remove that player's readiness.
  After a legal first start, each starts/finishes independently, including when
  the opponent has already finished. Session boundaries invalidate only that
  player's unfinished solve. Timer still owns clocks, assignment consumption,
  handicap and scoring.
- Touch/Touch keeps the existing joint preparation interaction. Mixed input
  does not require a Manual/Smart opponent to hold a touch surface. Manual
  values use the existing fixed-format parser and consume one own assignment.
  Finishing does not overwrite the opponent's clock or completed display.
- A scored round re-enables Manual submission for the next round. Leaving the
  Timer cancels unfinished Battle timing; returning restores subscriptions and
  current targets rather than leaving a disabled device owner.
- Panels share equal available halves and a one-point center divider. Timer
  anchors are independent of scramble length and opponent status. Full scramble
  text is fitted in its own region. Player 2's head-to-head panel, including its
  controls, remains rotated 180 degrees. Nearby Battle is not redesigned.

## Sharing

- Competition Report is available in the existing competitor All Results card
  and personal competition groups; personal reports collect that competition's
  results across events, not just the currently visible event.
- Result Highlight is available on the existing round result card. Average/Mean
  is first when present; Single and individual ordinal attempts are selectable.
- Adapters reuse WCAResultFormatter and existing personal-result presentation.
  Single and average record metadata stay separate. A particular attempt never
  inherits an aggregate record badge. Missing attempts do not acquire invented
  times or shift the ordinal labels of subsequent known attempts.
- Preview, Photos save and native system sharing reuse existing image action
  infrastructure. A request snapshots its source data when tapped. The export
  is a compact event/round table, not stacked result cards.
- Explicit CubingChina banner/logo metadata is carried through the Info cache.
  Banners retain aspect ratio; logos use a side-by-side information header.
  Unavailable/unrecognized assets fall back to typography. No arbitrary page
  image is guessed to be a competition banner. WR/CR/NR/PR images reuse the
  existing badge view and image exporter, with an exported-pixel regression.
- No Photos permission is requested until Save. Network artwork is optional;
  results can be rendered without it. Very long multi-event reports and actual
  Photos/Share extensions still require physical acceptance.

## Competition data and UI

- Raw organizer information/regulations/travel/registration documents use an
  isolated, nonpersistent WKWebView with responsive images and horizontally
  contained tables. Automatic semantic venue/calendar sections retain their
  existing renderer. Only the nonce-bearing sizing script executes; external
  scripts, forms and frames are blocked, user links open externally, and
  message handlers are removed on dismantle. The initial own HTML navigation
  accepts equivalent normalized base URLs, not arbitrary remote navigation.
- Shared Chinese name lookup remains cache-first. My Competitions publishes
  asynchronous enrichment with unchanged row IDs and guards against stale
  language/page/auth-revision results. ICU script conversion presents Simplified
  or Traditional names; English keeps the official English title.
- Participation marks now use the native Sessions Edit tint configuration in a
  fixed square, giving a circular green status treatment, not a capsule.
- System keyboard remains the default; the optional inline keypad uses flexible
  rounded rectangles without changing the shared vertical allocation.
- Charts now use a compact summary surface, selection detail, Best/Mean/Median,
  sparse scales and a bounded-height plot. Dense time series scroll natively on
  iOS 17+; earlier supported Charts versions retain a full-series view. Linear
  interpolation preserves actual values. iOS 15 retains the existing unavailable
  presentation rather than calling newer Charts APIs.
- Corrected a real histogram defect: integral maxima could be counted in two
  bins. Bins are half-open except the final closed edge, with explicit count
  conservation tests. DNF exclusion and +2-adjusted times are unchanged.
- Historical regressions: official final podium metadata is now separate from
  advancement, while the accepted green rank appearance is preserved. Live
  personal decoration requires exact canonical WCA IDs. Browser cache tests
  establish an actual interior row with native scrollToItem rather than a fixed
  point during initial large-title positioning. Their existing publication,
  identity and scroll-preservation assertions were not weakened; production
  Browser scrolling/layout was not changed.

## Explicit unresolved items

- Data Filter is still the existing native Menu. Source review found no
  application-owned reopen timer, delayed state gate or custom presentation
  animation to remove. Physical rapid-reopen latency is not declared fixed.
- Chat's existing bottom toolbar remains. Apple's public tab accessory moves
  from an above-bar to inline placement, but does not establish the requested
  independently floating circular control synchronized with minimization.
  The rejected full-width accessory and private hierarchy inspection were not
  reintroduced. [Apple API](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)).
- Native scramble generation, BLE radio latency, real rapid-turn FPS, haptics,
  simultaneous physical cubes and actual cold-launch animation remain unmeasured
  on hardware in this task. Simulator results do not substitute for these.

## Verification

Environment: Xcode 27.2, existing iPhone 17 Pro iOS 26.5 simulator, existing
DerivedData. No downloaded runtime or software. Final production source builds
for arm64 with `MinimumOSVersion = 15.0`; the app product is unsigned.

- `final-regressions.log` / `.xcresult`: **114/114 passed** across 16 focused
  suites: Guidance, canonical turns, mounted renderer, existing animations,
  Battle, assignment lifecycle, manual entry, sharing, organizer rendering,
  histogram accuracy, Chinese names, cache publication, official presentation
  and CubingChina Live identity. This is not a broad application/OAuth test run.
- `final-views.log` / `.xcresult`: **10/10 passed** after the final visual and
  relative-resource-base corrections. Includes the additional standalone Battle
  snapshot test, simultaneous configuration panels and actual exported badge
  pixels. There are 115 distinct passing test methods across these final runs.
- Unsigned generic iOS Debug builds succeeded. The last source-complete result
  is `generic-debug-verified.log`. Two small follow-up incremental builds were
  necessary after the initial successful build: the screenshot-discovered Exit
  overlap and the organizer relative-URL base. The first logging wrapper used
  zsh's read-only `status` variable after xcodebuild had already succeeded;
  subsequent wrappers use `result_code`. This was not an Xcode build failure.
- Existing TNoodle privacy-gate script warnings and unused AppIntents metadata
  warning remain. This pass did not change or re-evaluate that release policy.
- All three Localizable.strings files pass plutil; zero duplicate keys and
  parity for all 29 new/related keys. Config/Info.plist parses; git diff --check
  passes. All 7,665 baseline paths remain present; project.pbxproj and the
  pre-existing user scheme changes match their initial hashes.
- Inspected report/highlight exports, dense line/histogram light/dark renders,
  standalone Battle panels with a 60-token scramble and both configuration
  panels. The earlier Timer-hosted selector capture included transitional
  composition and was not accepted as static visual evidence. The standalone
  fixture avoids that outgoing Solo transition. The global Exit action is
  hidden only while either configuration is open, preventing it from covering
  the per-player controls; each panel retains its own Done/backdrop dismissal.
- The simulator launch log collector did not yield usable first-display
  milestones. No numeric process-launch or black-frame improvement is claimed.

Commands used the same project/scheme/DerivedData throughout:

```sh
DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer xcodebuild test \
  -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug \
  -destination 'platform=iOS Simulator,id=24E6D520-DF19-4F61-89DB-55F2F418484E' \
  -derivedDataPath build/competition-navigation-loading/DerivedData \
  -parallel-testing-enabled NO -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  <the explicit only-testing selectors recorded in each log>

DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer xcodebuild build \
  -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug \
  -destination 'generic/platform=iOS' -skipPackageUpdates \
  -derivedDataPath build/competition-navigation-loading/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
git diff --check
```

### Physical acceptance still required

1. Cold launch in Light/Dark mode and with different persisted events; measure
   the actual OS launch-to-first-frame interval in Instruments, not a mounted
   test or persistence-relative marker. Check the brief black interval.
2. Scramble a connected cube, deviate repeatedly, turn rapidly and switch/reconnect
   devices. Old guidance must disappear immediately; every displayed route must
   reach the current target. Repeat in Scramble Navigation and across background
   restoration. A verified route must not be advertised as proven shortest.
3. Assign two different physical cubes and different targets in Battle. Turn
   early, verify no start, restore both targets, start/finish in both orders,
   then disconnect one during a solve. The other timer/score must be unaffected.
   Also exercise Touch/Manual/Smart pairings and successive manual rounds.
4. Open both configuration panels, adjust handicaps, test long scrambles,
   head-to-head rotation, side-by-side landscape and keyboard presentation.
5. Share real official/Live/personal results across five/three/single-attempt
   formats, FMC and multi-blind. Verify badges, authentic banner/logo handling,
   ordinal attempts, Photos permission denial/save and actual Share extensions.
6. Check complex organizer documents/relative images/links, cached and newly
   enriched Chinese names in all three languages, charts with penalties and
   accessibility sizes, Data Filter rapid reopen and native Chat minimization.

## Files changed in this continuation

The pre-existing dirty files not listed here were preserved without changes.
- `Config/Info.plist`
- `CubeFlow/Assets.xcassets/LaunchBackground.colorset/Contents.json`
- `CubeFlow/Views/Shared/AppExperienceTrace.swift`
- `CubeFlow/Views/Shared/CompetitionSectionLoading.swift`
- `CubeFlow/Views/Shared/CompetitionService.swift`
- `CubeFlow/Views/Shared/CompetitionSharing.swift`
- `CubeFlow/Views/Shared/CubeTurnPresentation.swift`
- `CubeFlow/Views/Shared/CubingChinaDetailAdapter.swift`
- `CubeFlow/Views/Shared/CubingChinaLiveModels.swift`
- `CubeFlow/Views/Shared/PublishedCompetitionPresentation.swift`
- `CubeFlow/Views/Shared/ScrambleDiagramView.swift`
- `CubeFlow/Views/Shared/SessionSolveTrend.swift`
- `CubeFlow/Views/Shared/SmartCubeGuidanceController.swift`
- `CubeFlow/Views/Shared/SmartCubePeripheralSession.swift`
- `CubeFlow/Views/Shared/SmartCubeTargetPath.swift`
- `CubeFlow/Views/Shared/WCACompetitionPresentationSupport.swift`
- `CubeFlow/Views/iPhone/CompetitionOrganizerHTMLView.swift`
- `CubeFlow/Views/iPhone/CompetitionSharePreview.swift`
- `CubeFlow/Views/iPhone/CompetitionTabView.swift`
- `CubeFlow/Views/iPhone/DataTabView.swift`
- `CubeFlow/Views/iPhone/LocalBattleDevices.swift`
- `CubeFlow/Views/iPhone/LocalBattleScrambleState.swift`
- `CubeFlow/Views/iPhone/LocalBattleTestProbe.swift`
- `CubeFlow/Views/iPhone/ManualTimeEntry.swift`
- `CubeFlow/Views/iPhone/SessionNativeActionStyle.swift`
- `CubeFlow/Views/iPhone/SmartCube3DView.swift`
- `CubeFlow/Views/iPhone/SmartCubeManagementCard.swift`
- `CubeFlow/Views/iPhone/SmartCubeScrambleNavigator.swift`
- `CubeFlow/Views/iPhone/TimerLocalBattleView.swift`
- `CubeFlow/Views/iPhone/TimerTabView.swift`
- `CubeFlow/Views/iPhone/WCAMyResultsView.swift`
- `CubeFlow/en.lproj/Localizable.strings`
- `CubeFlow/zh-Hans.lproj/Localizable.strings`
- `CubeFlow/zh-Hant.lproj/Localizable.strings`
- `CubeFlowTests/BattleMixedInputTests.swift`
- `CubeFlowTests/CompetitionBrowserCacheTests.swift`
- `CubeFlowTests/CompetitionSectionLoadingTests.swift`
- `CubeFlowTests/CompetitionSharingNavigationTests.swift`
- `CubeFlowTests/FocusedPerformanceTests.swift`
- `CubeFlowTests/PerformanceBattleSharingTests.swift`
- `CubeFlowTests/PostDeviceUXTests.swift`
- `docs/performance-battle-sharing-nov03.md`
