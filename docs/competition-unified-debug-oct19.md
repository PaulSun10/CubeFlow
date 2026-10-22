# Unified DEBUG Mode, Capture Workflows, and Solve Ink Alignment

## Implemented

Settings > Development now has **Debug Mode**. Fresh DEBUG installs default to
OFF; the preference persists as `cubeFlowDebugMode`. The previous Top Cubers
bounds and Smart Cube debug-mode choices migrate once if the new key is absent;
the legacy keys and separate switches are removed. Ordinary app preferences,
protocol decoding, native scrolling and presentation state are not migrated.

When ON, the original Top Cubers chip/section outlines and size labels are reused
in both List and Glass. Settings exposes Filter Capture, Separator Capture,
Scroll Capture, and the existing Marketing Preview entry. Calendar's layout
debugger and Smart Cube Lab diagnostic controls also follow the master gate.
The bounds remain layout-neutral, noninteractive and accessibility-hidden.

Enabling Debug Mode does NOT start Filter, Separator, Scroll, or Smart Cube
protocol recording. Filter/Separator require Start; Scroll retains its explicit
Record Scroll Owners switch. Smart Cube's Protocol Debug/Verbose Packets and
packet capture remain explicit actions, not a second master mode. Optional
Smart Cube lifecycle traces require Protocol Debug; connection-prelude collection
requires both the master and that explicit opt-in. For pre-connection WeiPo
investigation, enable Protocol Debug before disconnecting/reconnecting. Its
existing prelude parser, buffer limits and packet decoder are unchanged.

OFF stops Filter (saving its bounded final history), stops Separator, disables
Scroll recording and immediately finalizes retained scroll-owner evidence,
stops existing Smart Cube packet captures without issuing a final Facelets/BLE
request, and disables optional protocol/timer traces. Window/touch observers and
first-visible display-link observation detach. Saved evidence is not cleared.
The master mode itself never installs, connects, reconnects, resets or commands a
physical device.

All controls/stores/instrumentation are compile-time DEBUG-only. Public view
helpers reduce to `self` outside DEBUG. Release was checked with targeted
non-DEBUG SIL emission, not a full Release project build.

## Intentionally Independent Development Infrastructure

Automated competition data/route fixtures, fixture-only scroll accessibility
traces, XCTest row-measurement hooks, compiler diagnostics, symbols, and Xcode
build infrastructure remain available to tests. These are not alternate in-app
Filter/Separator recording modes. The old Filter/Separator launch arguments no
longer activate capture. Normal in-app row-measurement accumulation is disabled;
the existing measurement hook remains available inside the XCTest host.

No decoder, timer readiness, connection policy, native scroll physics, Filter
presentation state machine, Result Card transition or Back behavior was changed.

## Manual Filter Workflow (No Xcode Required)

1. Settings > Development > Debug Mode ON > Filter Capture.
2. Start Capture. Navigate to Explore > Competitions.
3. Open Filter, close it, and immediately reopen. Repeat briefly. Include one
   slower reopen as a comparison if useful. Do not change unrelated selections.
4. Return to Settings > Filter Capture, then Stop Capture.
5. Share the saved capture using the native share sheet.

The same shared store survives tab changes and hosting reconstruction. Existing
passive cross-window touch observation, native target paths, touch/delivery
clocks, action/intent/binding generations, native presentation, first-visible
surface, and actual dismissal-completion events feed one 512-event ring. No
serialization or file writes occur in passive touch callbacks. Persistence is
performed only by explicit Stop (including master OFF), capture/edit/export
operations, not every event. Dropped-event count and stop reason are exported.

Observers never recognize, prevent, delay or cancel a gesture. Coverage remains
limited to app-owned scene windows; missing touch evidence cannot prove OS
suppression. The first visible surface is an observable UIKit measurement, not
proof of subjective visibility.

## Manual Separator Workflow

1. Debug Mode ON > Separator Capture > Start Capture.
2. Open the problematic competitor's All Results card. Stop scrolling and let
   its existing animations settle. Use Light Mode for the reported discrepancy.
3. If a compositor-accurate image is needed, take an original system screenshot
   now, without moving the viewport. Then tap **Capture Visible Table**, the
   DEBUG-only overlay below the card.
4. Review shows a cropped, aspect-fit card image. Tap a problematic line; the
   nearest recorded visible separator within 14 review points is highlighted.
   Multiple lines can be selected. Tap again to deselect, or use Undo/Clear
   Selection. The accessible line-label buttons operate the same selection.
5. If the programmatic snapshot differs from the physical display, use **Import
   Original iOS Screenshot**. Select the unchanged-viewport screenshot taken in
   step 3. The importer retains only the corresponding card crop, not unrelated
   screen/background content. Same-orientation/aspect validation rejects images
   that cannot be mapped safely. The user must ensure the viewport is unchanged;
   aspect validation cannot detect a different scroll position or old content.
6. Share exports the image(s), metadata and selected identities together. Done
   retains selections. Stop the Separator session in Settings when finished.

The overlay is outside production table layout; it does not participate in row
size, card size, scroll ownership, clipping, shadows or accepted animations.
Capture sessions and controls disappear on master OFF. Saved reviews remain
available after re-enabling the mode and after app relaunch.

## Identity and Geometry

The existing Canvas sibling probe supplies model/presentation coordinates,
window/screen/native scales, layout origin and unchanged paint formula result,
ancestor transforms, clipping/rasterization/opacity and active animation keys.
Only line positions inside both the visible owner clip and card crop become
selectable. Partially visible rows do not invent an off-clip visible boundary.

Production row context supplies event ID, table-local separator index, and the
actual preceding/following round IDs and names. Competition identity is carried
through the DEBUG environment into the original native Result Card. The header
boundary is explicitly distinguished from round-to-round boundaries. Where a
source identity is absent it remains unknown; there is no name lookup, record
inference or invented round. Selection exports stable capture-local IDs and the
corresponding identity dictionaries, not typed coordinates.

Geometry and the UIKit `drawHierarchy` image are gathered in one user action on
the main thread. They are NOT an atomic sample of the final compositor frame.
The sibling marker cannot inspect SwiftUI's private Canvas texture filtering or
clipping. Unsupported presentation projection is marked rather than guessed.
Imported original system screenshots are the authoritative pixel evidence;
the saved region is a lossless crop, not a rescaled illustration. Active
animation or a changed viewport limits the evidence and must not be treated as
proof of settled separator rasterization.

## Storage and Share

Filter and Separator each retain at most four saved captures in the app's
Application Support/DebugCaptures directory. New sessions are refused at
capacity, rather than silently evicting saved evidence. A 64 MiB admission guard
bounds persisted input; fixed one-per-capture ZIP exports add bounded duplicate
storage (not an unlimited export history). Capture files are excluded from
backup. There is no upload or background telemetry.

Each ZIP contains `metadata.json`, `snapshot.png` for a Separator capture, and
`system-screenshot.png` when attached. JSON includes capture ID, OS, timestamps,
context, raw geometry, selectable lines and selected separator IDs/identities.
The existing SystemShareSheet presents a local coordinated ZIP representation;
Foundation's `forUploading` option creates the local archive, not a network
upload. Re-sharing updates the same capture's export, not a new unbounded file.
Clear Captures removes that kind's saved evidence and its app-owned ZIP copies.
Files already copied elsewhere by the user are not modified.

Existing Scroll Capture keeps its accepted last-four in-memory retention model.
Master OFF does not clear it. Its Share action now reuses one temporary JSON
filename instead of creating an unlimited UUID-named export history. Scroll
recording does not resume automatically on process restart. Saved Filter and
Separator evidence does persist across restart; unsaved active recordings do not.

## Exact All Results Correction

The first-only Results header, its font, measured width and cell position are
unchanged. Existing summary columns, result formatting, typography, 36-point
rows, badges, table shadows, horizontal owners and no-bounce behavior remain.

For each nonempty first solve, let A be its regular-14-point text advance, I its
CoreText glyph-ink minimum X, H the medium-14-point header advance, and J the
header ink minimum X. Only the first value cell's unused width changes by:

`delta = A - I - H + J`

Right-aligned text then begins at the header's visible ink edge. Later cells
retain their original widths and move by exactly the same delta. The original
6-point per-side padding is unchanged. A positive maximum delta reserves the
necessary measured tail extent, preventing clipping for unusually long values;
there is no arbitrary negative offset or content-offset manipulation. Empty
attempt slots remain empty and retain their semantic column positions.

## Files Changed in This Pass

- CubeFlow/Views/iPhone/CompetitionDebugStore.swift (new)
- CubeFlow/Views/iPhone/CompetitionDebugCaptureView.swift (new)
- CubeFlow/Views/iPhone/CompetitionSeparatorCapture.swift (new)
- CubeFlow/Views/iPhone/CompetitionUIDiagnostics.swift
- CubeFlow/Views/iPhone/CompetitionFilterPresentation.swift
- CubeFlow/Views/iPhone/CompetitionResultsStyle.swift
- CubeFlow/Views/iPhone/CompetitionTabView.swift
- CubeFlow/Views/iPhone/SettingsTabView.swift
- CubeFlow/Views/iPhone/IPhoneContentView.swift
- CubeFlow/Views/iPhone/CompetitionCalendarImportSheet.swift
- CubeFlow/Views/iPhone/CompetitionScrollDiagnosticsView.swift
- CubeFlow/Views/iPhone/CompetitionScrollOwnerDiagnostics.swift
- CubeFlow/Views/iPhone/CompetitionLongListAcceptance.swift
- CubeFlow/Views/iPhone/SmartCubeLabView.swift
- CubeFlow/Views/iPhone/TimerTabView.swift (DEBUG trace gate only)
- CubeFlow/Views/Shared/SmartCubeBluetoothManager.swift (DEBUG opt-in/stop only)
- CubeFlow/Views/Shared/SmartCubePeripheralSession.swift (DEBUG prelude gate only)
- CubeFlow/Views/Shared/SmartCubeDiagnostics.swift (optional diagnostic collection only)
- CubeFlowTests/CompetitionUnifiedDebugTests.swift (new)
- CubeFlowUITests/CompetitionUnifiedDebugAcceptanceTests.swift (new)
- CubeFlowTests/CompetitionAllResultsTableTests.swift
- CubeFlowTests/CompetitionProfileDiagnosticsTests.swift
- CubeFlowTests/CompetitionScrollRetentionTests.swift
- CubeFlowTests/CompetitionScrollOwnerDiagnosticsTests.swift
- CubeFlowUITests/CompetitionTopCuberProfileAcceptanceTests.swift
- docs/competition-unified-debug-oct19.md

Unrelated pre-existing dirty files remain untouched. No project file, simulator
runtime, cache, physical-device state or unrelated data was deleted.

## Verification

Evidence is in `build/unified-debug-oct19/`.

- 30 distinct focused unit/native-host tests passed in verified-final.xcresult:
  8 unified diagnostics, 7 All Results, 7 existing profile/bounds diagnostics,
  2 scroll-owner, 3 scroll-retention and 3 Filter presentation regressions.
- 3 distinct UI checks passed: real Settings master persistence; real Filter
  capture across tab navigation plus OFF hiding tools; real published four-round
  All Results capture, real round-label selection/Undo and native share sheet.
  The latest Separator UI check was repeated after final geometry filtering.
- The final explicit-recording opt-in correction was rechecked with all 8 unified
  diagnostics tests passing in explicit-recording-gate.xcresult.
- Rendered 3x screenshots verify English/Simplified/Traditional first-solve ink
  alignment within one render pixel, unchanged header allocation, and unchanged
  adjacent solve widths/padding. Screenshots were visually inspected.
- Actual coordinated ZIP extraction was checked: metadata plus both PNG files,
  with three real round boundaries and two selected IDs. The machine-readable
  inspection is bundle-validation.json. There is no orphaned image/JSON pairing.
- Native card test verifies outer competition ID and actual round IDs reach the
  visible Canvas probes. Master OFF test immediately finalizes a real collection
  owner's retained measurements without waiting for another idle callback.
- Release-exclusion SIL emission contains no DEBUG store, capture UI, passive
  observer or separator runtime classes; only the no-op public view helpers.
- Filter and native Result Card source match their starting production source
  after stripping DEBUG blocks. Original Top Cubers sizing, chip, Profile wrapper
  and result statistic components are byte-for-byte unchanged.
- The single final unsigned generic iOS Debug build passed (CODE_SIGNING_ALLOWED=NO,
  generic/platform=iOS), recorded in final-generic-debug.log.
- git diff --check passed. Explicit touched added/untracked-file whitespace checks
  also passed; the audit is recorded in whitespace-audit.txt.

Earlier implementation/test-fixture iterations are retained in the same evidence
folder. Final results above refer to corrected current behavior, not those
intermediate failures.

## Physical Acceptance Still Required

No physical Apple device was accessed, installed, launched, logged or debugged.
All automated execution was simulator-only; the generic build is unsigned.

Run the two in-app workflows above on the iPhone 17 Pro / iOS 27.2 beta. Confirm
that saved counts and Share work, marked lines match the actual suspect lines,
and imported original screenshot pixels preserve the observed discrepancy.
Also check the first solve beneath Results on a real display and confirm all
previously accepted Browser, Top Cubers and Result Card interactions remain.

**Filter rapid-reopen latency and stationary separator thickness/darkness remain
unresolved physical issues. This pass provides evidence collection, not a guessed
production fix for either root cause.** No commit or push was performed.
