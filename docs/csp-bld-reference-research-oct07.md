# CSP BLD Reference Research, 2026-10-07

## Scope and Conclusion

Research only. No production CSP catalog, generation rule, reference, case ID,
label, formula, training interaction, progress key, or localization changed.
The 170 ordered presentations and 340 contexts remain intact.

The Japanese/user family is the appropriate target, not Brandon's concrete
references, solved indexing, Cale tracing, or SpeedCubeDB counting positions.
The counting mathematics is settled; the exact reference dataset is not.
Neither physical trace (Shield/Shield 8; Shield/Scallop 10) is independently
reproduced here. No reference was selected merely to obtain those numbers.

## Source Evidence and Recovery Limits

The [Japanese article](https://shellsquare.hatenablog.com/entry/2018/09/11/213224)
teaches reference-relative BLD, independently traces corners/edges, and warns
that an odd reference change exchanges route meanings. It specifies bottom
viewed through from above and yellow-up/orange-front setup orientation. The
user identifies this family with their teacher's material; the article alone
does not establish every teacher-specific permutation.

Both public article images were visually inspected. Its single Scallop/Scallop
reference row includes setup metadata. A research-only transcription:

```text
0,5/0,-3/3,0/3,0/-2,-5/-3,0/5,0/-3,-3/0,-3/-4,-2/
```

Legal replay in the existing sector model yields:

```text
top    [2,4,5,5,7,7,1,1,3,3,6,0]
bottom [14,8,13,13,15,15,9,9,11,11,10,12]
middle 0
shape  010101011111 | 010101011111
```

This demonstrates a non-image reconstruction path for a published row. It does
not independently calibrate that notation/color/view frame to the teacher's
Shield or Scallop templates. The article's unrelated worked total is not used
as a golden fixture for either physical anchor. No artwork or route collection
was imported.

The [Scribd mirror](https://www.scribd.com/document/393258453/Cube-Shape-Parity-CSP)
has substantial public text and reference diagrams. Notes describe an
inverted-color flip with `(x,y) -> (-y,-x)`, top-view bottom diagrams, and
shape-dependent orientation/parity changes. These are source claims, not a
validated universal transport. Flattened text loses diagram/row associations.
Normal viewer search identifies Shield on page 11; navigating there exposes
an unlock screen with blurred diagrams. Inspection stopped at that gate.
No gated download, asset enumeration, subscription, upload, or bypass occurred.
The mirror-to-dead-sheet identity and exact row correspondence remain unproven.

The [csTimer issue and comments](https://github.com/cs0x7f/cstimer/issues/20)
explicitly distinguish BLD/Cale, and explain that traditional 90 omit inverted
top/bottom duplicates while retaining them for practical training. The linked
public Java gist contains shape-index scrambler data, not a Japanese reference
permutation oracle. Its code was not imported. The historical discussion also
reports duplicate/missing shape indices later corrected: do not treat the first
index table as unquestioned coverage. A later alternative sheet is a different
reference provenance, not a substitute for the user's identified sheet.

Repository, CSP resource history, generators, geometry helpers, existing audit
and legacy-artwork inventory provide no independent Japanese piece references.
The current CSP resource has no committed history. The known dead Google Sheet
ID remains `1QEx3dcOZE5KTRwu80gEd6y1xqKrbC0MZ8GMUtZv0kns`.

## Exact Reference Model

For actual state A and an identically aligned reference R, enumerate each
corner/edge position separately. Define `p[i] = position in R of A[i]`.
Its cycles are exactly the requested piece-to-home-position tracing. Each
length-L cycle contributes L-1. The answer is the sum for corners plus edges,
modulo two. Reversing the permutation reverses cycles but preserves lengths.
Middle-layer flip is not itself a traced piece or an additional parity bit.

The diagnostic requires all 24 sectors, all 16 unique piece identities with
correct widths/contiguity, and identical aligned piece boundaries. Matching
shape names alone is insufficient. It does not silently rotate, reflect,
sort layers, infer colors, or choose a reference.

User-supplied cyclic orders are B-R-G-O for edges and GO-GR-BR-OB for corners.
They do not specify which edge/corner occupies a particular anchored slot.
Cycling four corner labels one phase preserves their cyclic order yet changes
the reference by a four-cycle: trace contribution 3, hence an odd change.
An independent edge phase can change the answer again. Corner-edge phase,
slot origin/direction, U/D identity allocation, and bottom-view transport
must therefore be known. Canonical color order alone is insufficient.

For 4+4 presentations, per-layer templates are plausible but partner-independent
placement is not proven. For 2+6 and 3+5 distributions, a pure U-colored upper
template and D-colored lower template cannot cover all pieces. Joint allocation
of U/D pieces and relative phase is required. Do not extrapolate a recoloring
rule from the pure 4+4 example to these cases.

## Dataset Size and Reconstructibility

Reliable baseline representation: an explicitly anchored, complete reference
for each of the 90 unordered shape-pair classes, with independently verified
transports to ordered presentations. This is an upper-bound representation,
not a claim that 90 manual image transcriptions are inevitable.
Until those transports are verified for this convention, the conservative
fallback is 170 explicit ordered references, not an assumed layer swap.

Potential compression, still unproven: ten four-corner layer templates could
cover the 55 unordered 4+4 pairs if partner independence is validated; the 35
mixed-count pairs need joint allocation information. The 29 distinct layer
geometries are not automatically 29 sufficient colored references. Further
mirror/base-template compression requires explicit mappings and parity checks.

Recovery priorities: source-associated setup metadata can reconstruct a state
mathematically; a licensed machine-readable sheet would preserve associations;
otherwise interpret only independently accessible reference diagrams and
validate anchors. No complete reference list or proven image-free construction
rule was recovered. Shield/Shield and Shield/Scallop still require their exact
external references, from source-associated setup data or accessible diagrams.
Two full references suffice for the current spot-check; two layer templates
would suffice only after confirming that their compositions match both pairs.

## Proven and Unproven Transforms

Proven mathematically: simultaneous bijective position reindexing of actual
and reference conjugates p and preserves cycle lengths/counts. Simultaneous
piece-identity renaming preserves p. This includes a consistently applied
layer exchange or reflection, when its complete position/identity map is
specified. It does not mean mirrors are the same recognition presentation.

Changing only the reference composes p with another permutation. Its sign
changes by that reference permutation's sign. Odd changes exchange classes;
even changes preserve class but can alter the exact trace total. Count changes
are not generally a constant additive offset. Pure global recoloring of the
reference alone must be tested as the induced 16-piece permutation, not assumed
neutral. Reflected geometry, slot alignment and mixed colors must stay explicit.

Not yet proven for the target dataset: a universal top/bottom template rule,
partner independence, the mirror/flip maps, their class changes, or that all
rows of the Scribd mirror are the exact Japanese/user references. No Brandon
Scallop placement or edge ordering is used to fill these gaps.

## 90, 170, 340

Independent enumeration yields 29 cyclic layer geometries:
2 corners: 5; 3: 10; 4: 10; 5: 3; 6: 1.

Unordered complete-cube pairs:
`5*1 + 10*3 + 10*11/2 = 5 + 30 + 55 = 90`.
Ordered pairs: `2*5 + 2*30 + 10*10 = 170`.
There are ten equal-layer fixed points and eighty two-element exchange orbits.
Burnside gives `(170 + 10)/2 = 90`; two reference-relative classes per ordered
pair give 340 contexts. Independent cyclic layer alignment is already removed;
reflection/chirality is not quotiented. Historical csTimer testimony agrees
with this top/bottom expansion. A row-by-row historic sheet crosswalk has not
been performed. Counts of algorithms such as 329 concern another counting layer
and are not established by this geometry calculation.

## Current Private Convention

`tools/ContentValidation/generate-csp.cjs:17` selects an old parity-zero state
under its actual ordered shape, or the first BFS candidate when none exists.
Line 18 calls that state `first`. Line 23 loops over `[0, first]` and the
opposite-sign state. Lines 35-39 count cycles relative to `first`; lines 47-48
store its top/bottom sectors and `cubeflow-piece-cycles-v1`.
Thus the retained/generated state is the zero-count Even reference by
construction, not by external BLD calibration. Retaining an old Even state
retains that convention, not evidence that it matches the teacher's reference.

The all-16-piece permutation in the generator preserves corner/edge blocks
because boundaries are aligned. Its total equals the sum of the separate
corner/edge counts. Legal replay plus inverse-setup solution validates an
internal state/solution pair, not its community-facing Even/Odd designation.

`SquareOneCSP.swift` consumes this reference; it is not the independent source
of a Japanese counting scheme. No production code in either path changed.

## Physical Anchors: Exact Private Traces, External Traces Unresolved

These use CubeFlow integer piece IDs, not a newly inferred color convention.

Shield/Shield actual:
`top [15,15,3,3,0,12,1,1,2,14,13,13]`,
`bottom [11,11,7,7,4,8,5,5,6,10,9,9]`.
Private reference:
`top [13,13,1,1,2,14,7,7,0,12,15,15]`,
`bottom [9,9,5,5,6,10,3,3,4,8,11,11]`.
Corner permutation `[3,6,1,0,7,2,5,4]` has piece cycles
`(15 13), (3 5 7 1), (11 9)` and count `1+3+1=5`.
Edge permutation `[2,3,0,1,6,7,4,5]` has piece cycles
`(0 2), (12 14), (4 6), (8 10)` and count `1+1+1+1=4`.
Private total 9 Odd, versus the user's external total 8 Even.

Shield/Scallop actual equals its private reference:
`top [5,5,6,10,11,11,3,3,1,1,2,14]`,
`bottom [7,7,13,13,9,9,4,8,0,12,15,15]`.
Both permutations are `[0,1,2,3,4,5,6,7]`. Corner piece cycles are
`(5),(11),(3),(1),(7),(13),(9),(15)`; edge cycles
`(6),(10),(2),(14),(4),(8),(0),(12)`.
Private total 0 Even, versus the user's external total 10 Even.

Assuming the supplied physical counts, the required external-to-private
reference change must be odd for Shield/Shield and even for Shield/Scallop.
Therefore a global label inversion cannot correct both. The exact external
maps and cycle decompositions remain unknown; the diagnostic records them
as null rather than fitting candidates to 8/10.

## Future Design Space, Not a Decision

Possible reference representations: explicit 90 reference states plus proven
transports; per-layer templates plus joint mixed-count allocations; or a
hybrid of validated base states and signed transforms. Preserve provenance,
frame definition, validation status and version independently of case IDs.

Possible recognition models: separate named BLD/Cale conventions over the same
authoritative state, or one selected learning convention with adapters. A
future reference-learning UI could show standard forms and cycles, but none
is implemented or selected here. CSP class and post-cubeshape parity remain
different concepts; route compatibility requires external calibration.

Migration alternatives: if only aligned reference sign changes, labels/class
associations may be remapped while legal setups/formulas remain intact. Exact
trace metadata must be recomputed. If frame/presentation/color allocation also
changes, explicit transport and potentially target/route rebinding is needed.
Regenerating setups is not inherently necessary. Case identity, learned-state
continuity and route meaning require a separate product decision and verified
crosswalk. This pass does not make that decision or migrate any context.

## Scramble Detail Separator

Deep inspection of `f521d99663632c904ce216796489171b447944b0` includes the
viewer, export composition and inner `ZoomableContentImage` scroll/image view.
The viewer has 24-point spacing, the image wrapper has clear backgrounds and
no border/separator drawing, and the old diagram-only export has a baked
background. That rectangular bitmap/container boundary could have produced
visual separation. Its identity with the user-observed separator is not
proven. Absence of a literal Divider does not prove absence of visual separation.

Minimal correction: one adaptive native Divider overlay at the diagram frame's
bottom, offset by half the existing 24-point gap (12 points). The overlay does
not participate in layout, hit testing or accessibility. It spans the existing
content width. Diagram and notation positions, sizing, 20/16-point padding,
background, modal/enlargement interaction, selection, toolbar, exports and
copy/save/share are unchanged. This restores the requested separation without
reintroducing the old baked background or claiming exact historical origin.

## Verification

Research: `node --test tools/ContentValidation/research/bld-reference.test.cjs`
passes eight tests. Includes exhaustive 40,320 permutations, independent
inversion sign, every cyclic/reversed starting order, identity/wrapped pieces,
separate cycles, invalid-input rejection, simultaneous transports, reference
phase ambiguity, cardinalities and explicitly unresolved external anchors.
These establish mathematics, not the Japanese references or physical acceptance.

Run `node tools/ContentValidation/research/bld-reference.cjs` for the report;
or supply a JSON file with `actual`, `reference`, and optional visit `options`.
Outputs positions, permutations, index/piece cycles, separate counts and total.
No production writes or external reference defaults exist.

App: three focused simulator tests pass: separator-in-existing-gap with unchanged
content dimensions in Light/Dark, transparent/adaptive Detail background, and
existing diagram/notation export. The initial new fixture incorrectly flipped
the bitmap Y-axis; a focused position probe identified row 104 instead of its
top-origin row 263. Removing that test-only flip resolved it without changing
the production separator or loosening the position assertion.
The position-probe runner then stalled while merging coverage after its
assertions finished and was terminated. The final three-test rerun completed
normally with `TEST SUCCEEDED`; no test runner was left running.

`git diff --check` passes. The production CSP resource SHA-256 is unchanged:
`eb95cddcd1668aa24931bd2138ebf4e133c0a24b0b6d19bfe224700a23501643`.
Starting-file hashes differ only for the separator source and its focused test
file. New files are this report and the isolated diagnostic/test pair.

Exactly one final unsigned generic iOS Debug build passed with deployment target
iOS 15.0 (`CODE_SIGNING_ALLOWED=NO`, generic/platform=iOS). No second generic
build ran. The only build warning was skipped AppIntents metadata extraction
because the app has no AppIntents.framework dependency.
Physical separator appearance still needs the user's device check. No commit
or push.
