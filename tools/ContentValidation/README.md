# Depth Pass Validation

Run from the repository root. These tools do not require a backend or physical BLE connection. Generated/reference content is distinct from optimized community algorithms.

## Focused Correction Follow-Up

The earlier correction snapshot was 49 sets / 8970 appearances, including PBL
parity, EP parity, OBL and CSP. Its unordered CSP model is superseded below.
See `docs/1.0-depth-correction.md` and bundled source/license notices.

```sh
node tools/ContentValidation/validate-library.cjs
node tools/ContentValidation/validate-csp.cjs
ruby tools/ContentValidation/validate-localization.rb
```

CSP now enumerates 170 ordered physical presentations / 340 parity contexts and
validates 5100 arbitrary labelled states, checking that computed reference
parity selects even cubeshape and the opposite solution leaves odd cubeshape.
`node tools/ContentValidation/validate-square-one-presentations.cjs` independently
enumerates circular physical tilings, compares the actual legacy CS universe,
executes the bundled packed model as a separate setup oracle, and verifies the
visible label/state/reference chain. Full diagnostics are saved in
`docs/square-one-presentation-audit.json`. Frozen legacy artwork hashes and
measured geometry are in `square-one-legacy-artwork.json`; regenerate only with
`audit-square-one-legacy-artwork.py` (Pillow), never by replacing those assets.
`complete-csp-orientations.cjs` is now a read-only compatibility entry to the
validator; it must not recreate the superseded nested Normal/Inverted groups.
Generation is independent and intentional: `generate-csp.cjs`, `generate-obl.cjs`,
`generate-pbl-parity.cjs`, `generate-ep-parity.cjs`, then
`generate-case-relationships.cjs`. These commands write bundled JSON; do not run
them as read-only validators. The inherited parity seed is not newly licensed.

Current raster totals: 232 renders, 396 NxN stroke measurements, 72 FTO geometry
checks. The additional legacy-puzzle checks require a fresh module cache per
render, matching WKWebView document reload. All Thick cases are unclipped;
26 existing Thin cases touch boundaries and are recorded without changing the
frozen default geometry. This is not a claim that every legacy Thin renderer
has no clipping. Use the same real-browser HTML fixture workflow below.

Native correction suites are `DepthCorrectionTests`, `DepthPassTests`, and
`TimerPolishTests`; do not substitute a broad suite or physical BLE tests.

## Library And Localization

```sh
node tools/ContentValidation/validate-library.cjs
ruby tools/ContentValidation/validate-localization.rb
git diff --check
```

Library validation covers 45 sets / 7,586 entries, unique IDs/metadata, Square-1 setup legality, 967 PBL exact inverse returns and 16 FTO setup/solution returns. The four known legacy Square-1 baseline exceptions are reported explicitly; a new exception fails. This does not mathematically verify every legacy algorithm on every puzzle. Localization checks 19 catalogs, syntax, duplicate keys, six added keys and the confirmation placeholder.

## Independent FTO Oracle

Use an external temporary installation of `cubing@0.63.8`; do not vendor its implementation into the app. For example, install with `npm install --prefix /tmp/cubeflow-fto-oracle cubing@0.63.8`, then:

```sh
node tools/ContentValidation/check-fto-independent.mjs \
  /tmp/cubeflow-fto-oracle/node_modules/cubing/dist/lib/cubing/puzzles/index.js
```

It compares 98 full 72-sticker states against independent puzzle geometry/KPuzzle. Default mode verifies the bundled 18 deterministic fixtures without writing. Explicit `--write-fixtures` regenerates them after intentional reference review. This is an independent state-model check, not a claim that two copies of the same solver validate one another.

## Browser Raster And Compositing

```sh
node tools/ContentValidation/render-diagram-fixtures.cjs /tmp/cubeflow-diagrams.html
```

Open that HTML in a browser, then inspect `JSON.parse(document.getElementById('result').textContent)`. An `error` field fails validation. Expected totals: 79 rasters; 158 light/dark compositions; 198 resolvable NxN outer/internal stroke measurements; 72 equal-area, uniquely indexed, nonoverlapping FTO triangles. Small 52-point widths are checked for clipping; exact stroke-width measurements use 160/320-point widths to avoid subpixel-cell aliasing. The Canvas shim follows WKWebView's fitted backing size/DPR and one-time context scale.

The page also displays all 16 FTO references in a real CSS-constrained image grid. Its `images` object contains PNG data URLs for reproducible assets; regeneration must be intentional. Headless Chrome may be used with a new temporary `--user-data-dir`, `--dump-dom` and/or `--screenshot`. Do not use or terminate the user's normal browser/profile. This check is not a substitute for device WKWebView/SwiftUI compositing acceptance.

## Intentional Content Regeneration

```sh
node tools/ContentValidation/generate-reference-content.cjs /path/to/pinned/PBL-Manager/init.json
```

This **writes** the PBL/FTO JSON files. PBL source commit: `18cf975e5e22c474be8788eab4e4cb469cf90c1b`. FTO engine revision: `30ef16c7db1d2758fe359786ee140a0f321b94e9`. Retain their MIT notices; inspect changed cases and rerun every validator. FTO generated solutions are mathematically valid references, not a deterministic optimizer output or a curated method set.

## Native Focused Tests

```sh
xcodebuild test -project CubeFlow.xcodeproj -scheme CubeFlow -configuration Debug \
  -destination 'platform=iOS Simulator,id=<available simulator ID>' \
  -derivedDataPath build/codex-phase46-closeout-tests \
  -only-testing:CubeFlowTests/SolveManagementCloseoutTests \
  -only-testing:CubeFlowTests/TimerPolishTests \
  -only-testing:CubeFlowTests/DepthPassTests \
  -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO
```

Use one final unsigned generic iOS Debug build for closeout, not repeated generic builds during fixture development. Keep physical/manual verification separate: Data selection edges and Move confirmation; PB lifecycle/Reduce Motion; Square-1 recognition and layouts; FTO notation/colors/cold-start/refresh/persistence/export on a device.
