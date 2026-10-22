# Physical Competition Scroll Owner Investigation

October 16, 2026. Dirty worktree retained. No commit/push.

## Authoritative Physical Result

The user tested the latest source on iPhone 17 Pro, iOS 27.2 beta. Ordinary
scrolling STILL visibly pulls content backward near the end of scrolling or
deceleration in BOTH List and Glass, without any disclosure action. The user
explicitly distinguishes this from accepted native interactive glass feedback.

The earlier simulator empty-section spacing correction did not resolve the
physical complaint. It is evidence for one simulator layout defect only, not
evidence establishing the remaining physical movement owner. No additional
production spacing, layout, scrolling, publication, or animation correction is
made in this follow-up.

## Shared Production Path Inspected

Both appearances use `CompetitionVirtualizedList`, `CompetitionVerticalListLayout`
(native UICollectionViewFlowLayout), and `CompetitionHostingCollectionViewCell`.
The shared cell fits hosted content at the actual row width and rounds its height
up. iOS 16+ uses native UIHostingConfiguration with zero margins. The hosting root
is top-aligned; accepted fixedSize-based card content remains intact.

The following are possible owners to measure, NOT diagnosed causes:

- Native deceleration/bounds behavior, including adjusted-inset changes.
- Preferred-size invalidation and Flow Layout's own offset/content-size adjustment.
- A cell/frame change without actual scroll offset change.
- Hosted SwiftUI descendant/presentation movement within a stable contentView.
- Deferred diffable snapshot/reconfiguration and hosting-root replacement at idle.
- Top Cubers publication at drag/deceleration completion.

Source inspection finds an explicit offset reset only on the existing query-change
path. The presentation signature includes style, color scheme, language, icon
readiness, Top Cubers visibility and row revision. This does not establish which
path ran on the physical phone during the failure. No path is removed or bypassed
based only on that possibility.

## Proven Instrumentation Gaps

1. The previous `hostModel`/`hostPresented` fields described only `cell.contentView`,
   not its descendants. On some UIKit paths that contentView is itself the hosting
   root, and pure SwiftUI Text can render without any descendant UIViews. Stable
   root bounds do not prove stable hosted content or rendered glyphs. The new
   capture includes the actual hierarchy AND existing SwiftUI layout anchors;
   neither alone is claimed to measure every compositor-rendered pixel.
2. Preferred-size/invalidation records were behind the physical TEST FIXTURE flag;
   a normal device capture enabled only by the owner-timing flag lacked them.
3. Detailed trace JSON was exposed through the accessibility value, impractical
   for manual physical export. The current user report contains no such trace.
4. The previous sampler could collect both display-link and didScroll owner
   snapshots per frame; walking the enlarged hierarchy twice is unnecessary
   diagnostic overhead.

## DEBUG-Only Changes

- Owner sampling now includes a bounded structural subtree under contentView,
  with actual object identities, model/presentation rectangles and bounds,
  transforms, animation keys, and an explicit flag when presentation projection
  cannot be represented. The old contentView fields remain for compatibility.
- Captures include scroll presentation bounds/surface, insets, native deceleration
  rate, tracking/drag/deceleration state, and native predicted target offset from
  `scrollViewWillEndDragging`. The target pointer is READ ONLY.
- A bounded timeline records actual preferred-size results, invalidation context
  adjustments, reuse/root replacement, queued updates, snapshot/reconfiguration
  start/completion, query-reset execution, and publication/deceleration boundaries.
  The existing production values and lifecycle are not changed.
- Hierarchy owner samples run from CADisplayLink, rather than also from every
  didScroll callback. Numeric offset samples still record native scroll callbacks.
- Settings > Development > Competition Scroll Diagnostics enables capture without
  launch arguments or a test-fixture Browser. It retains the last FOUR completed
  gestures in memory and uses the existing system Share sheet to export JSON.
  Each export has a unique filename; successive files do not overwrite each other.
- Physical manual recording does not serialize large accessibility JSON or write
  files during scrolling. Explicit Share performs export after recording is off.
  Data/sample counts and duration are bounded; capped traces expose `truncated`.

No overlay, replacement interaction owner, runtime private-API call, scroll
compensation, delay, custom animation, cache/fetch policy, or production state
transition is added. Read-only UIKit type names describe hierarchy, not behavior
switches. Diagnostic capture is off by default and unavailable in Release.

Files: `CompetitionScrollOwnerDiagnostics.swift`, `CompetitionLongListAcceptance.swift`,
DEBUG hooks in `CompetitionTabView.swift`, `CompetitionScrollDiagnosticsView.swift`,
one DEBUG Development link in `SettingsTabView.swift`, and focused diagnostics tests.

## Verification

- `diagnostics-final-tests.log`: both focused hosted-hierarchy/layout-anchor and
  bounded four-capture/export tests PASSED on iOS 26.5 simulator. The initial
  fixture failed because pure Text need not create descendant UIViews and native
  adjusted insets make zero an invalid assumed initial offset. The revised test
  waits for an explicit SwiftUI anchor and compares the actual before/after offset.
  An intermediate async test compile failed for a missing `await` on diffable
  apply; that test-only error was corrected.
- `manual-capture-pipeline.log`: the additional real display-link/post-idle manual
  archive path PASSED with the runtime recording preference, WITHOUT the test
  launch flag. It retains multiple owner frames, completes idle coverage, leaves
  offset unchanged, and does not serialize the large accessibility JSON.
- `git diff --check` passed. Frozen Filter, disclosure, native Detail Back,
  separator and project-file hashes match the pre-follow-up snapshot.

The earlier goal's one generic iOS Debug build has already been used; NO additional
generic build is authorized or run here.
No physical XCTest handshake retry, installation, or device interaction is attempted.
These instrumentation checks cannot establish a physical scrolling fix.

## Smallest Useful Physical Evidence

Use a current DEBUG device build. Keep the same list/data and Top Cubers setting
that reproduced the issue. For EACH appearance separately (List, then Glass):

1. Set the appearance, then open Settings > Development > Competition Scroll
   Diagnostics. With recording OFF, tap Clear Captures, then enable recording.
2. Return to Competitions. Perform the usual ordinary flick that reproduces the
   pullback; do not tap Show More/Less or change filters/refresh during the gesture.
3. Wait at least one second AFTER scrolling stops so post-idle frames are included.
4. Return to diagnostics, disable recording, then Share Captured Scrolls. Retain
   the resulting JSON. Repeat for the other appearance; filenames are unique and
   each trace records its style. One clearly reproducing gesture per mode suffices.

If practical, screen-record the same gesture. A video is supporting evidence if
rendered text moves while all observed model/presentation anchors stay fixed; that
case cannot be labeled a layout/offset bug from view geometry alone.

## Interpretation Gate

Compare frame-by-frame within native min/max bounds, not just final offsets.
Correlate offset changes with native target/insets and invalidation adjustments;
correlate stable-offset cell changes with size and snapshot events; correlate
stable-cell content movement with actual hosted descendant/presentation state.
Treat unsupported transforms, truncated capture tails, and missing event coverage
as unknowns. Only a matching physical timeline can justify the next production
correction. The physical issue remains UNRESOLVED.
