# Comprehensive Performance and Reliability - November 3, 2026

## Scope and Preservation

Continued the existing dirty App worktree after reviewing
`deep-performance-stabilization-nov03.md` and
`performance-battle-sharing-nov03.md`. The initial status, patch, file hashes,
measurements and test bundles are under the ignored
`build/comprehensive-performance-nov03/` directory. Existing work is preserved.
No physical device, real OAuth, backend, deployment, commit or push was used.
No dependency, runtime or software was installed. No iPad/Mac redesign or
TNoodle/privacy change was made.

Environment: Xcode 27.2, Debug arm64 iOS 26.5 iPhone 17 Pro simulator. Device
compilation targets iOS 15.0. Simulator timings are not physical launch,
BLE latency, frame pacing, energy or total-process memory measurements.

## Measured Changes

| Measurement | Before | After | Boundary |
| --- | --- | --- | --- |
| Build 7,901 ao100 entries from the same 8,000 samples, three trials | 54.07 / 47.58 / 48.63 ms | 28.36 / 26.91 / 26.83 ms | Comparable CPU microbenchmark, about 44-48% less work time; not whole Data-tab latency |
| Format 500 dates in each of English, Traditional Chinese and Arabic | 14.27 / 16.20 / 15.26 ms | 1.01 / 1.17 / 1.06 ms | Same localized strings, about 14x; not an end-to-end scrolling FPS measurement |
| Mounted Algorithms first entry, selection through snapshot completion | 757.5 ms | 387.9 ms | One sample per version; includes native mounting and drawHierarchy overhead, not a statistically established 49% gain |
| Complete 4,000-row layout | Previous production single-image path rejected more than 256 rows | 82 pages, 1,162 ms worker layout | New completeness baseline; excludes rendering and the test's much slower exhaustive token assertions |
| Export 512 rows to full-resolution PNG files | No complete production export at this size | 8 pages, 910 ms; largest bitmap 47,026,560 bytes | Serial background export, fixed 2x readable scale; not a hard RSS cap or Photos/share-extension measurement |
| XCTest application launch, five samples per run | Previous pass: 1.550 s | 1.657 s, RSD 2.33%; same-binary repeat 1.692 s, RSD 7.19% | No further launch improvement established; both means are slower than the previous run, with no contemporaneous controlled old-binary comparison |

Raw before measurements are in `baseline.log`; `optimized.log` contains the
after measurements above. First-entry tests mount all five actual tabs twice.
Timer first entry remained approximately 115-124 ms. Warm tab return samples
were approximately 330-437 ms in the last focused run, dominated in part by
the measurement's hierarchy snapshot. These are not physical touch-to-photon
latencies. Explore and Settings showed substantial run-to-run variance.

The first Data baseline exposed a correctness problem: it loaded the global
persistent store instead of the test/environment store and displayed zero of
the intended 1,000 rows. The corrected run displays all 1,000. Comparing those
two Data timings as equivalent loads would be misleading. With the same
correct 1,000-row load, the intermediate and final runs measured about
1,026 ms and 824 ms respectively, but this single sample is not an isolated
cache-effect benchmark. No speculative post-launch all-tab prewarming was added.

Final full-suite measurements on the same implementation were 25.32-26.25 ms for
the average-entry build, 1,128 ms for 4,000-row layout, and 855 ms for the 512-row
PNG export. Both date-cache and average-window CPU reductions persisted.

The launch comparison remains unresolved. The two new launch runs use the exact
same simulator binary; the second uses `test-without-building`. Values were
1.705 / 1.650 / 1.637 / 1.599 / 1.693 s, then
1.925 / 1.619 / 1.596 / 1.703 / 1.619 s. Earlier 1.550-s samples were collected in
the previous pass under a different overall test workload. This does not prove
that the difference is solely simulator noise, nor establish a new source-level
startup regression. No speculative startup change was made to improve a number.
Paired physical cold/warm launches and a process/first-frame trace remain required;
preservation of the entire previous launch gain has not been demonstrated.

## Runtime Corrections

### Data and Algorithms

- A private-queue `SessionSolveSnapshotReader` reads the actual environment
  store on `context.perform`; managed objects never escape that queue. Every
  load resets its reader context so same-count edits do not reuse stale values.
- Data and Data search cancel superseded loads and reject stale generations.
  Disappearance invalidates pending publication. The existing empty-snapshot
  behavior on read failure is preserved, so a failed new-session load cannot
  expose the previous session's results. Cancelled/obsolete reads cannot clear
  newer data.
- Removed a feedback fetch triggered by publishing the newly loaded solve count.
  Personal-best IDs and solve positions are rebuilt for a new snapshot, not
  every filter/sort operation. Default newest ordering reuses the fetched order.
- New solve notifications invalidate record and average snapshots even when the
  count is unchanged. Session/language keys additionally reject late results.
- Average entries retain immutable slices of one sample buffer rather than
  allocating a separate overlapping array per entry. Detail access preserves
  the existing array API. The ao100 fixture previously copied 790,100 sample
  memberships; now its 7,901 slices share the 8,000-sample backing buffer.
  This is a structural allocation reduction, not a measured RSS claim.
- Date display reuses at most eight immutable configured formatters. Locale and
  time-zone notifications invalidate the cache. Locking protects cache ownership;
  concurrent read-only formatting uses Apple's documented DateFormatter thread
  safety on iOS 7+. Language, calendar and date/time styles are unchanged.
  [Apple DateFormatter documentation](https://developer.apple.com/documentation/foundation/dateformatter).
- Algorithms' per-section list contents and overview grid are now lazy. The
  existing outer lazy list, navigation identity, row design and search behavior
  are preserved; offscreen sections no longer eagerly create all their previews.

### Complete, Bounded Competition Exports

- Production export now produces a document of PNG file URLs, never a single
  shrinking bitmap or an in-memory array of full-resolution page images.
  The 256-row limit survives only in the DEBUG historical single-image fixture.
- Immutable request/artwork/record-badge snapshots are prepared on MainActor.
  CoreText line wrapping, page planning, drawing, PNG encoding and file writes
  run on one serial export actor. Each page is rendered inside an autorelease
  pool, at 840 logical points wide and 2x scale, below 12 million pixels.
- All input rows are indexed independently of provider row IDs. Variable-length
  names, competition metadata, round labels and attempts wrap completely.
  Ordinary rows stay intact; exceptionally tall content splits only between
  complete text lines/artwork. No row, badge or metadata is silently omitted.
- Existing WCA format adapters preserve DNF, DNS, penalties, FMC/MBLD values,
  means and attempt ordinals. Existing WR/CR/NR/PR badge images are reused;
  explicitly supplied personal records are no longer dropped by a regional-only
  record-tag normalizer. Individual attempts never inherit aggregate badges.
- Preview is a lazy stack of all pages, with ImageIO thumbnails loaded by a
  separate serial actor. Preview work therefore does not queue behind another
  complete report export. Missing optional artwork retains the typography-only
  fallback; late cancelled exports cannot replace a newer selection.
- Native sharing receives every page URL. Photos saves every page in one
  transaction without recreating a full-image array. A document lease remains
  owned by the native share coordinator or save task until the operation ends.
  Dropping the last lease deletes that document's temporary directory.
- Cancellation checks cover layout, rendering, encoding boundaries and writes.
  Failure or cancellation removes partial files and never publishes a partial
  document. Concurrent requests have independent files and source snapshots;
  expensive bitmap work is serialized. There is no total report row cap.

### Smart Cube, Guidance and Existing Behavior

No further BLE/protocol, Guidance algorithm, Battle timing or animation redesign
was necessary in this pass. Added mounted stress coverage uses two independent
canonical feeds and real simulator CADisplayLinks, not a manually advanced clock:
each owner wakes immediately, processes 36 mixed turns, displays intermediate
animations, reaches its exact final state and pauses again with zero idle ticks.
Independent Guidance owners each receive 100 rapid updates plus target/attempt
changes; executing their final routes reaches only their current targets.
Distrusting one owner does not clear the other's route. Existing foreground,
background, cancellation, disconnect, Battle round and WebKit lifecycle tests
remain in the complete regression run.

Competition Browser native scrolling, Top Cubers sizing/disclosure, Interactive
Glass, Filter, Result Card transitions/Back and Timer ownership were not changed.

### Regression Harness Corrections

- The passive Filter observer test used the persistent shared capture store.
  Its four retained Filter captures correctly prevented starting another session,
  so the test could not attach its observers. It now uses an isolated temporary
  store and additionally asserts that recording really started. Existing capture
  files are not cleared. All observer, touch and detach assertions are unchanged.
- The mounted Smart Cube test previously assumed a sufficiently advanced native
  display callback would occur within one fixed 60-ms sleep. Under complete-suite
  load it once observed an intermediate angle of 0.0348 instead of more than 0.05.
  It now observes the real clock within that animation's existing deadline.
  The same renderer identity, animation identity, angle bounds and exact settled
  state are required. No manual clock advancement or production timing change
  was introduced.
- Result Card transition fingerprinting synchronously PNG-compressed every full
  screenshot on the MainActor while sampling a 160-ms animation. A later complete
  run saw only three distinct Back frames. The test now hashes every rendered
  pixel directly, excluding row padding, without compression. The strict minimum
  of four distinct frames, dimmer, presentation identity and navigation assertions
  are unchanged. A before/after capture-overhead measurement is logged separately
  before the animation, not inside its observation interval: the same full-screen
  image took 101.74 ms for PNG encoding plus hashing versus 19.87 ms for direct
  pixel hashing. The latter run passes the original transition assertions. This
  is a test-observation improvement, not a production animation speed claim.

## Verification

Final source is covered by a complete application unit run, not just individual
retests. Every complete run includes all 795 XCTest cases and 357 Swift Testing
cases. The six skips are five real Keychain checks unsupported by the unsigned
host (OSStatus -34018) and one opt-in real-provider network probe. No real account,
physical device or credentials were used to bypass these gates.

| Artifact under `build/comprehensive-performance-nov03/` | Actual result |
| --- | --- |
| `full-final.xcresult` | 1,144 passed, 2 failed, 6 skipped; persistent diagnostics store and 60-ms renderer sampling failures |
| `full-verified.xcresult` | 1,145 passed, 1 failed, 6 skipped; both preceding failures fixed, Result Card screenshot-compression sampling failed |
| `regression-final.xcresult` | 1,146 passed, 0 failed, 6 skipped; complete suite green before final read-failure compatibility correction |
| `regression-audited.xcresult` | **1,146 passed, 0 failed, 6 skipped; complete suite on final production and test source** |
| `launch-final.xcresult` | 1/1 launch-performance test passed; five samples, 1.657-s mean |
| `launch-confirmation.xcresult` | 1/1 passed without rebuilding; five samples, 1.692-s mean; unresolved comparison described above |
| `generic-debug.log` | One unsigned generic iOS Debug build passed; actual app `MinimumOSVersion` is 15.0 and `codesign -dv` confirms it is unsigned |
| Localization | Existing validator passes all 19 catalogs; `plutil` passes all 60 strings files |
| Whitespace | `git diff --check` and checks of new/touched untracked files pass |

Earlier focused runs also passed:

- `implementation.xcresult`: 13/13 XCTest.
- `optimized.xcresult`: 13/13 XCTest, including two concurrent-cube stress tests,
  first-use navigation, date equivalence/concurrency and paginated exports.

The final read-failure correction preserves the previous Data behavior instead
of retaining another session's displayed snapshot after a failed switch. Both
list and search publication still check cancellation and generation before any
empty or successful result can affect UI.

Remaining warnings are not hidden: mounted tests emit UIKit/WebKit/QoS and some
SwiftUI preference diagnostics; one existing nested test capture function has an
actor-isolation compiler warning. No attributable physical responsiveness cause
was established for those messages. Xcode's optional simulator diagnostic
collection reports that its helper cannot locate `simctl`; test execution and
result bundles still complete successfully. The generic build retains existing
TNoodle privacy-evidence-gate and AppIntents metadata warnings, outside this task.
The successful build is not an Apple privacy/TestFlight clearance or iOS 15
runtime acceptance result. No new production concurrency warning was reported.

### Changed Files in This Pass

App source: `Models/SessionSolveSnapshotReader.swift` (new),
`Views/Shared/SolveDisplayDateCache.swift` (new), `DataTabSupport.swift`,
`SolveMetrics.swift`, `ContentInteractionSupport.swift`, `AppExperienceTrace.swift`
(DEBUG probe), `CompetitionSharing.swift`, `Views/iPhone/DataTabView.swift`,
`AlgTabView.swift`, `CompetitionPagedExport.swift` (new), and
`CompetitionSharePreview.swift`.

New tests: `WholeAppPerformanceTests.swift` (4),
`CompetitionPagedExportTests.swift` (5), `ConcurrentCubeStabilityTests.swift` (2).
Updated regression fixtures: `CompetitionProfileDiagnosticsTests.swift`,
`SmartCubeMountedRendererTests.swift`, `CompetitionNavigationLoadingTests.swift`.
This report is new. Other pre-existing dirty files are not changes from this pass.

## Physical Acceptance Still Required

1. Cold and warm launch with representative large local data, actual black-frame
   interval, first visible Timer frame and first/return visits to all tabs.
2. Two real cubes: isolated and rapid turns, camera/peek interactions, exact final
   state, reconnect/background restoration and idle GPU/energy/thermal behavior.
3. Guidance under real high-frequency deviations and target/device changes;
   independent Battle readiness, starts/finishes, disconnects and round return.
4. Long mixed-event reports, late/missing artwork and concurrent exports: inspect
   every page and final-row record badges, save all pages to Photos, and exercise
   actual share extensions including cancellation/dismissal. The bitmap bound
   does not establish a whole-process RSS or extension input-count limit.
5. Existing List/Glass scrolling, Top Cubers, Filter, Result Card/Back, special WCA
   formats and iOS 15 runtime behavior remain hardware acceptance boundaries.

No Instruments hardware trace or device operation was performed. Local automated
success must not be described as physical FPS, BLE latency or energy acceptance.
