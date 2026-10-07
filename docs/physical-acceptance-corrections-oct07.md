# Physical Acceptance Corrections, 2026-10-07

## Status

Shrink and detail appearance corrections implemented; physical retesting remains
necessary. CSP practical Odd/Even mapping is NOT corrected or accepted. No CSP
catalog entries, IDs, probabilities, progress keys, or production conventions
were changed. The missing counting-frame/formula comparison is explicit below.

## Timer Shrink

The fitter measured against an upstream height derived from a controls-height
preference. The final root mask instead clips against the positioned Timer
anchor. Shrink, unlike Scroll, did not clamp its proposed height again using
the actual positioned scramble origin. A correctly measured Text could therefore
fit its local proposal yet extend outside the root's allowed region. Inherited
scramble-change animation also allowed fitting/layout updates to interpolate.

The new Shrink-only viewport uses the actual named-coordinate origin and the
same Timer anchor minus the unchanged 12-point gap. The root anchor is converted
into that named space before passing it down. Text measurement explicitly uses
the final available width and unconstrained intrinsic vertical size. Fitting
transactions are nonanimated. The minimum font is unchanged, not lowered again.

The regression exercises a stale 450-point proposal, final positioned safe edge,
accessory-width reduction, both vertical-position endpoints, and 6/100/240/500
move texts. Final intrinsic Text bounds remain above the real safe edge, without
a ScrollView. Short text retains its maximum size where the region permits it.
Existing overestimated-font feedback tests also pass.

This confirms the layout-path defect and correction, not physical iPhone
acceptance. Retest the previously failing long 7x7 with the same Timer position,
font, and device settings. Scroll implementation, font sizes, hard root mask,
and 12-point gap are untouched.

## Scramble Detail

Historical source: f521d99663632c904ce216796489171b447944b0,
`Expand timer customization and scramble sharing`. The established Timer
presentation used fullScreenCover; diagram presentation used the shared
zoomViewerPresentation full-screen modal transition. Both are restored.
That outer modal transition is not an inner image zoom interaction.

The historical viewer's NavigationStack/NavigationView fallback, 24-point stack
spacing, 20/16-point horizontal/vertical padding, font settings, centered
selectable notation, Close/Share toolbar and share choices are preserved.
Its inner ZoomableContentImage is replaced by a normal scaledToFit Image.
The existing copy/save/share context actions remain; opensDetail=false prevents
the displayed image from opening a second viewer. Multi-blind is unchanged.

The confirmed appearance bug was using the export composite as the on-screen
image. Timer export configuration bakes in its background and color scheme;
changing the surrounding app appearance cannot recolor that bitmap. Viewing
now uses the existing transparent diagram renderer directly, over adaptive
systemBackground. Copy/save/share still use the historical export renderer and
configuration. Focused tests verify a transparent diagram corner, white/black
background samples in Light/Dark, and absence of an inner pinch recognizer.

Historical fidelity limitation: no content Divider exists in that revision,
and searching committed ScrambleDiagramView history for Divider finds none.
No guessed separator was added and historical spacing is retained. The exact
missing separator cannot be claimed restored without identifying the accepted
reference (a screenshot or revision, including whether it is the native
navigation-bar separator). Native navigation presentation is restored.

## CSP Physical Anchor Investigation

Actual entry: `csp_010101110111_010101110111_1`, Shield/Shield Odd.

Displayed setup:

```text
(-5,-4) / (-3,-3) / (-5,-4) / (-4,2) / (-2,4) / (-4,-4) /
```

State reached by legal replay from solved:

```text
top    = [15,15,3,3,0,12,1,1,2,14,13,13]
bottom = [11,11,7,7,4,8,5,5,6,10,9,9]
middle = unflipped
shape  = 010101110111 | 010101110111
```

Independent piece order: top then bottom, first sector of each piece from
sector zero; corners indexed (id-1)/2, edges indexed id/2. This calculation does
NOT compare to the generated reference.

```text
corners = [7,1,0,6,5,3,2,4] : even
edges   = [0,6,1,7,2,4,3,5] : even
combined fixed-order sign   : even
```

This is genuinely the symmetric Shield/Shield presentation; layer-name swapping
does not explain it. The private reference has odd fixed-order sign, but is
declared Even by definition. The actual setup is 9 swaps/Odd relative to that
reference and Even in the fixed piece order. The first convention dependency
enters in generate-csp.cjs when the first retained/generated reference is treated
as Even without a community standard-form calibration.

Stored solution:

```text
/ (4,4) / (2,-4) / (4,-2) / (5,4) / (3,3) / (5,4)
```

It is legal and returns THIS setup exactly to solved, not merely cube shape.
It therefore is not proven to be an incorrect inverse mapping. It is also not
identified as the user's familiar/simple Odd route. That exact formula and
counting orientation are still required to test the reported physical failure.

`AlgCase.sliceCount` counts slash moves in valid stored solution notation,
taking the minimum across formulas; it is used by slice-count sorting. This
generated reference solution has 6 slices. That is not proof of a conventional
6-slicer case classification or an optimal/curated Shield/Shield Odd algorithm.
No literal current CSP detail label '6 slicer' was located in source.

### Independent Community Tool Check

[SpeedCubeDB CSP Trace](https://speedcubedb.com/SQ1/Trace) gives the exact Shield
setup `3 = Odd` at its default top=0/bot=0 positions. Pressing Top + once, with
the scramble unchanged, gives `2 = Even`. The known-good Shield/Scallop Even
setup gives `4 = Even` at defaults. These are the tool's six-component trace
totals, not claims that its counts equal the user's 8 and 10.

[Brandon Lin's CSP tutorial](https://brandonlin.com/cubing/csp.html) explicitly
requires reference alignment and notes that alignment changes odd/even solution
semantics. Consequently the fixed-order sign alone cannot safely determine
the intended community label. The private label is not universally disproven
by the fixed-order Even result; the public tool independently demonstrates why.

Needed clarification: the user's exact standard counting positions/orientation
and simple Shield/Shield Odd formula, or a screenshot of the reference/tool
configuration. Do not relabel or regenerate setups without that calibration.
No third-party algorithms, rendering code or collection data were imported.

### Dataset Audit and PASS Control

`audit-csp-counting-frame.cjs` independently records both type permutations and
fixed-order signs for all 340 contexts, verifies legal setup, actual ordered
presentation, native state, and exact solved result after the stored formula.
All 340 pass those executable checks. 156 private labels differ from fixed-order
sign; these are convention differences, NOT 156 proven mislabeled cases.
The complete findings are in csp-counting-frame-audit.json.

Shield/Scallop Even control, unchanged:

```text
setup: (-5,-4) / (-3,-3) / (-5,-4) / (-4,0) / (-4,-2) /
corners: [2,5,1,0,3,6,4,7] : even
edges:   [3,5,1,7,2,4,0,6] : even
```

Its stored formula is legal and solves its state exactly. This does not replace
the user's physical PASS control. The separate existing invariant validator
also passes 5,100 arbitrary labeled-state selected/opposite checks, but those
checks establish private-reference consistency, not community compatibility.

The audit still finds 170 ordered geometric presentations/340 private contexts;
no evidence here changes their geometric cardinality. Their community parity
semantics remain unvalidated. Stable IDs, progress, and legacy CS are untouched.

## Verification and Boundaries

- Six focused simulator tests pass: actual positioned Shrink, rendered fitting
  feedback, transparent/adaptive detail display, export actions, independent
  physical CSP fixtures, and frozen Scroll root-mask raster bounds.
- An initial Scroll test rerun failed only because its existing screenshot
  destination directory was absent; creating that temporary directory resolved
  it. No Scroll production code was changed to pass the test.
- CSP diagnostic audit: 340 legal setups/state/solution checks, 170 presentations.
- Existing CSP private-reference invariant: 5,100 checks pass (limited scope above).
- git diff --check passes.
- One final unsigned generic iOS Debug build is run after source verification;
  its result/log is reported in the task response.
- SHA256 comparison to start-of-turn source baseline identifies only
  TimerScrambleViewport.swift, TimerTabView.swift, ScrambleDiagramView.swift and
  AlgPresentationCloseoutTests.swift as modified existing files. Added files are
  this report, the CSP audit script and its JSON output.
- Probability, accepted Scroll, stroke scales, artwork, localization, learned
  state, Data, PB, FTO, BLE/timing and deployment target are unchanged.
- No commit, push, deployment, checkpoint or destructive operation.
