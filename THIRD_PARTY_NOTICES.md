# Third-Party Notices and Provenance

Evidence reviewed: 2026-10-23. This inventory separates verified licenses from
unresolved provenance. It is not a declaration that all bundled materials are
cleared for distribution. The first-party GPL-3.0-only grant in [NOTICE.md](NOTICE.md)
does not replace any third-party license or supply missing permissions.

Paths below are relative to this repository. Bundled notice texts are in
`CubeFlow/Resources/ThirdPartyNotices/`. Existing notice texts and vendor source
headers have been preserved. Source archives retain their upstream notices.

## TNoodle-lib Native

- **Component:** existing `Vendor/TNoodleLibNative.xcframework/ios-arm64/lib-scrambles.dylib`.
- **Source:** [CubeLabsNZ native fork](https://github.com/CubeLabsNZ/tnoodle-lib-native-v1/tree/e50c528feb8220b99eb66575a748e88391300f1f),
  release `v1.0`, revision `e50c528feb8220b99eb66575a748e88391300f1f`.
  This is the native fork of [WCA TNoodle-lib](https://github.com/thewca/tnoodle-lib),
  not the AGPL web/server TNoodle project formerly linked in About.
- **License/attribution:** GPLv3, as declared in the fork's module POMs and LICENSE.
  WCA Software Team; source files also retain individual authors' notices,
  including Chen Shuang's solver notices. Do not replace them with Paul Sun's
  copyright. No separate native-wrapper copyright owner is invented here.
- **Versions:** embedded `scrambler-min2phase`, `scrambler-threephase`,
  `scrambler-sq12phase`, and `lib-svglite` POMs identify `0.18.1`.
- **Modifications:** existing vendor image differs from the upstream release by
  local ad-hoc signing/link-edit metadata, not loaded code. CubeFlow's existing
  packaging script changes only a copied image's install identity/signature;
  native algorithms and wrapper are not modified by this migration.
- **License text:** `TNoodle-GPL-3.0.txt`; upstream LICENSE is also in the included
  source ZIP. Its original formatting is retained independently of root LICENSE.
- **Source:** pinned upstream source ZIP is now supplied in `ThirdPartySources/TNoodle/`.
  This supplies the wrapper, puzzles, module source and build definitions, **not**
  a complete source delivery for every linked runtime portion. The focused follow-up
  also supplies pinned Graal, Gluon Substrate and GluonFX source archives, checksums
  and a machine-readable inventory. Exact binary
  hashes, native-image flags, dependencies and remaining gaps:
  [TNOODLE-SOURCE.md](docs/TNOODLE-SOURCE.md).

## GraalVM, SubstrateVM and OpenJDK Runtime Portions

- **Evidence:** native metadata identifies GraalVM `22.1.0.1 Java 17 CE`, Java
  `17.0.3`, `IOS_AARCH64`. The matching Gluon source tag resolves to
  [`08e1c57bc6b6de932b0faed2f49b21a1a54a39fe`](https://github.com/gluonhq/graal/tree/08e1c57bc6b6de932b0faed2f49b21a1a54a39fe).
- **License:** inspected SubstrateVM/OpenJDK runtime source uses GPLv2 with
  Classpath Exception. Individual files identify Oracle and/or affiliates and
  other contributors; retain their own years and notices, rather than assigning
  one blanket copyright to all runtime material.
- **Local text:** `Graal-SubstrateVM-GPL-2-Classpath.txt` (existing text retained).
- **Recovered source:** complete Gluon Graal archive at the pinned revision is
  included in `ThirdPartySources/TNoodle/`, with its original SubstrateVM/SDK
  licenses and `THIRD_PARTY_LICENSE.txt`. All 13,591 source blobs matched the
  complete official Git tree. This is the matching release source family, not
  authentication of any unrecorded builder patches or static-JDK inputs.
- **Limit:** the actual linked Java static SDK and its exact patches are not
  authenticated by the Graal host Java version. No runtime source modification
  by CubeFlow is identified; the builder's complete modifications are unknown.
  A source tag URL alone is not a complete corresponding-source arrangement.

### Graal SDK

- Same pinned [Gluon source family](https://github.com/gluonhq/graal/tree/08e1c57bc6b6de932b0faed2f49b21a1a54a39fe/sdk),
  UPL 1.0; preserve Oracle/affiliate and other source-file notices.
- Local text: `Graal-SDK-UPL-1.0.txt`. No separate CubeFlow SDK modifications.
- Applicability to every linked runtime file still requires the exact SDK
  inventory; UPL is not substituted for GPLv2+Classpath files.

### Other Embedded Metadata / Build Tools

The native image contains Maven resources for shaded JavaCPP `1.5.2`, LLVM `9.0`
and jcodings `1.0.56-SNAPSHOT` (the latter declares MIT in metadata). Resource
presence is not proof that every class is linked executable runtime code or that
a whole compiler is redistributed. Exact linked portions, authors/notices and
source delivery remain to be inventoried. No blanket license is assigned here.

The native build pins GluonFX Maven plugin `1.0.16`, whose POM depends on Gluon
Substrate `0.0.56`. Full fixed-revision source archives for both are now included;
they additionally match all 15 / 48 Java files in the official Maven source JARs.
They are not additional app frameworks. GluonFX is established as a build tool;
Substrate also supplies native iOS support actually present in this image.
Inclusion of the upstream
Gradle wrapper JAR in the source ZIP preserves a required build bootstrap, not a
new CubeFlow runtime dependency. Its source is [Gradle](https://github.com/gradle/gradle)
(Apache-2.0); `gradle-wrapper.properties` inside the unchanged ZIP requests Gradle
`7.5.1`. Apache license text is included as
`ThirdPartySources/TNoodle/Gradle-Wrapper-Apache-2.0.txt`. The archived bootstrap
JAR SHA-256 is `778e7f46bd67eaea2de5bcbdbb40878c6614656014ba59a72ce8648eaf43a925`;
it does not match Gradle's published 7.5.1 wrapper checksum. Its precise wrapper
revision is therefore not established by the requested distribution version.

### Gluon Substrate Native Support and GluonFX

These are distinct from Graal **SubstrateVM**. Source archive origins, license
member hashes, version limits and verification commands are in
[TNOODLE-SOURCE.md](docs/TNOODLE-SOURCE.md) and
[`source-manifest.json`](ThirdPartySources/TNoodle/source-manifest.json).

- **Gluon Substrate 0.0.56:** revision
  `cb0447fc6d448f31fc28945ffbf3c2c7845d8ca5`; all 235 upstream blobs verified.
  `src/main/resources/native/ios/dummy.c` grants GPLv3-or-later,
  Copyright (c) 2022, Gluon. Its ARM feature initialization and three empty
  JDK17 JNI functions correspond to code/exports in the shipped image. Inspected
  Java build files also grant GPLv3-or-later with their own years. The root
  LICENSE is GPLv2 and the POM's license name/URL is inconsistent; retain all
  original texts and use the actual file notices rather than flattening them
  into a new blanket grant. The complete archive includes native support,
  reflection/JNI configs, Gradle build definitions and `external-licenses.md`.
- **GluonFX 1.0.16:** revision
  `54f979b8f8ad7bd962f283f4e9c2e4c9f45641d5`; all 28 upstream blobs verified.
  BSD-3-Clause, Copyright (c) 2019, Gluon in root LICENSE, with later years in
  individual files preserved. No evidence that Maven plugin implementation
  code executes in the app. Its sharedlib/compile/link implementations are
  included as build source, not a reconstructed successful build script.
- No local modifications to these upstream archives. Whether the original
  native builder used unrecorded target/tool patches remains unverified.

## min2phaseCXX

- **Local:** `CubeFlow/Vendor/min2phaseCXX/` and CubeFlow's Objective-C++ bridge.
- **Upstream:** [lilborgo/min2phaseCXX](https://github.com/lilborgo/min2phaseCXX).
  Exact imported upstream revision is not recorded; do not invent a release.
- **Attribution/license:** source headers say `min2phaseCXX Copyright (C) 2022
  Borgo Federico`. The bundled README contains both a GPLv3-or-later grant
  (`Copyright (C) 2023 Shuang Chen`) and MIT grant (`Copyright (c) 2023 Chen Shuang`).
  Preserve both original notices; the project's GPL-3.0-only choice does not
  change these third-party alternatives or establish ownership of every ported file.
- **Local text/source:** `CubeFlow/Vendor/min2phaseCXX/README.md`, its source headers
  and full vendored source; root GPL supplies version 3 terms, not a removal of
  the upstream later-version option.
- **Local changes:** cancellation/interruption support in `src/Search.cpp` and
  `src/Search.h`, and CubeFlow bridge integration. No solver change in this migration.

## SwiftConfettiView

- **Source:** [ugurethemaydin/SwiftConfettiView](https://github.com/ugurethemaydin/SwiftConfettiView/tree/7b0d18301b9135ea62274d470e050fe032dace91),
  revision `7b0d18301b9135ea62274d470e050fe032dace91`.
- **License:** MIT; Copyright (c) 2019 Uğur Ethem AYDIN.
- **Local:** `CubeFlow/Views/Shared/ThirdParty/SwiftConfettiView.swift`, four original particle
  assets in `CubeFlow/Resources/SwiftConfettiView/`.
- **Notices:** `SwiftConfettiView-LICENSE.txt`, `SwiftConfettiView-source.txt`.
- **Modifications/source:** vendored UIKit emitter includes namespaced resource
  loading, iOS guard, cancellation and birth-stop/drain lifecycle adaptations.
  Full adapted source and assets remain in this tree. Default Rain remains the
  product behavior; nothing is relicensed or functionally changed here.

## PBL-Manager

- **Source:** [charlieharris0n/PBL-Manager](https://github.com/charlieharris0n/PBL-Manager/tree/18cf975e5e22c474be8788eab4e4cb469cf90c1b),
  revision `18cf975e5e22c474be8788eab4e4cb469cf90c1b`, `public/assets/data/init.json`.
- **License:** MIT; Copyright (c) 2020 Charlie Harrison.
- **Text:** `PBL-Manager-MIT.txt`. Imported setup/taxonomy data and CubeFlow's
  generated references are described in `SquareOne-generated-references.txt`
  and [the content audit](docs/1.0-content-audit.md).
- **Local changes:** normalized recognition/setup data and generated inverse-setup
  references, not copied curated speed algorithms. Permitted non-parity setups
  do not license the separate historical parity seed.

## Chen Shuang Standalone FTO Engine

- **Source:** [MIT FTO gist](https://gist.github.com/cs0x7f/1579492aa43c794d529057386c489702/30ef16c7db1d2758fe359786ee140a0f321b94e9),
  revision `30ef16c7db1d2758fe359786ee140a0f321b94e9`.
- **License:** MIT; Copyright (c) 2024 Chen Shuang.
- **Text/source:** inline in `CubeFlow/Resources/DrawScramble/fto_engine.js` and
  `Chen-Shuang-FTO-MIT.txt`.
- **Local changes:** CommonJS/notation adapters after the retained core source;
  independent CubeFlow FTO diagram adapter. This standalone permission is not
  derived from csTimer's parent GPL license.

## Cubing Icons Font

- **Owner-identified origin:** [cubing/icons](https://github.com/cubing/icons).
  Its [license at reviewed revision](https://github.com/cubing/icons/blob/5f9b4bb2e78acd3fe4322fc0c0ddba54ea3c0636/LICENSE)
  `5f9b4bb2e78acd3fe4322fc0c0ddba54ea3c0636` is MIT, Copyright (c) 2015
  Devin Corr-Robinett. It covers that upstream project's icons/fonts.
- **Notice correction:** upstream permission/copyright text is now retained as
  `Cubing-Icons-MIT.txt` without changing font bytes or glyph metrics.
- **Local artifact:** `CubeFlow/Resources/CompetitionIcons/event-icon.ttf`, SHA-256
  `5877b7ebf3b4c33f69448c8605d0a82b1bcc29f1e159dc122853a4e3ae6bb39b`.
  Its name table says `event-icon`, `Version 1.0`; this is not an authenticated
  Cubing Icons release number. It has 38 glyphs.
- **Remaining uncertainty:** upstream `v1.1.3` / npm `2.0.2` fonts are identical
  to each other but not this font (22 glyphs, different cmap/outlines/metrics).
  No exact import revision or transformation record was found. The owner supplied
  the origin; MIT permission is verified there, but coverage of every local glyph
  and any additional contributions is not independently established by that alone.
  Do not assert a byte match, an exact release, or permission from unknown contributors.
  Recover the font's source/derivation record to close this provenance gap.

## DrawScramble / csTimer-Derived JavaScript

- **Local evidence:** `DrawScramble/mathlib.js` explicitly says
  `FROM CSTIMER, MAY BE MODIFIED BY THE SCRAMBLER TEAM`. Initial inherited files
  are in Git's foundation revision `49a6967e`; no exact external import revision
  or complete intermediate DrawScramble package notice was found.
- **Upstream evidence:** [csTimer](https://github.com/cs0x7f/cstimer/tree/2547d82e32a347dd1b1c6943e8d03389d03eb64c)
  contains corresponding math routines; its [GPLv3 LICENSE](https://github.com/cs0x7f/cstimer/blob/2547d82e32a347dd1b1c6943e8d03389d03eb64c/LICENSE)
  is preserved as `csTimer-GPL-3.0.txt`. This supplies license text, not proof that
  this current revision was the imported one. Attribution: csTimer project and
  contributors; exact original file-level authors/years remain to be recovered.
- **Local source/modifications:** complete shipped JS is present in
  `CubeFlow/Resources/DrawScramble/`; raster fitting, Square-1 integration and
  the separate MIT FTO engine are documented in Git. `raster_geometry.js` and
  the FTO diagram adapter are independent CubeFlow contributions.
- **Unresolved:** mapping of inherited `main.js`, `mathlib.js` and legacy
  `cubes/{nnn,clk,megaminx,pyraminx,skewb,squareone}.js` to their actual upstream
  versions, authors, intermediate modifications and permissions. Merely adding
  GPL text does not clear unidentified intermediate code. No conflicting license
  is proven; no blanket MIT/GPL relabeling of those files is performed.
- `require('canvas')` does not itself prove node-canvas is bundled; the app has
  its own JavaScript canvas bridge. No new Node dependency is added here.

## Historical Algorithm JSON, PNG and Square-1 Seed

- Current `CubeFlow/Resources/Algs/` contains 51 JSON files and 6,789 PNGs.
  Sources are mixed; many JSON entries identify SpeedCubeDB. These counts do
  not mean every image is copied or has the same author/license.
- `Scripts/generate_scdb_seed.rb`, `generate_scdb_group_preview_seed.rb`,
  `generate_pll_seed.rb` and `render_scdb_jcube.swift` record extraction/rendering
  workflows. The latter uses SpeedCubeDB's `ijsm.js` in a WebKit renderer;
  generating a PNG does not by itself establish rights in the renderer/artwork.
- `Resources/Algs/sq1parity.json`, case `adj_parity`, identifies SpeedCubeDB.
  Its use in derived PBL/EP references is recorded in
  `SquareOne-generated-references.txt`. Permission for this seed remains unverified.
- Independent CubeFlow OBL/CSP enumeration, mathematical reference solutions and
  generated diagrams remain separate from curated external collections. A legal
  mathematical move sequence is not a license to copy a website's artwork or
  curated collection. Research links are not redistribution grants.
- **Status:** material unresolved redistribution rights, not a proven finding
  of unauthorized distribution and not an assertion of GPL compatibility.
  Existing resources remain unchanged. Obtain a per-family source/license record
  or permission covering the actual included data/images/seed. If replacement is
  needed, it requires separate authorization; this migration does not remove assets.

## Classification and Publication Status

1. **Verified permissions/notices:** pinned TNoodle Java source (runtime source
   delivery still incomplete), SwiftConfettiView, PBL-Manager, standalone FTO;
   min2phaseCXX retains its actual source/README license notices.
2. **Notice gaps corrected, provenance not automatically cleared:** MIT Cubing
   Icons notice, csTimer GPL text, central attribution and TNoodle source inventory.
3. **Unresolved material provenance/source delivery:** font derivation, historical
   algorithm images/data/seed, intermediate DrawScramble source and linked native
   runtime inventory. These remain public-distribution gates.
4. **Confirmed incompatible/unauthorized resource:** none established by this
   pass. Unknown permission must not be reported as either approval or infringement.

This is the identified vendored-resource inventory, not an exhaustive SBOM or an
Apple distribution-terms clearance. See [the release gate](docs/licensing-release-gate.md)
for concrete next actions and the conditional push decision.
