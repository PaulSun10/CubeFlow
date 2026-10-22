# TNoodle Native Source Inventory and Delivery

Evidence date: 2026-10-23. **Partial source delivery; binary distribution remains
blocked pending the specific runtime/build-source gaps below.** This is neither
a complete GPL Corresponding Source offer nor a claim that linking an upstream
URL alone satisfies the license. No native rebuild was performed.

## Binary Identity and Source Revision

| Item | Verified value |
| --- | --- |
| Repository input | `Vendor/TNoodleLibNative.xcframework/ios-arm64/lib-scrambles.dylib` |
| Input SHA-256 | `35ca5611930688d63e6e43b9e2a5d49d6c9dec08ca54a98a136645ce454b4103` |
| Input size | 37,867,808 bytes |
| Image | arm64 Mach-O dylib, UUID `D2D6B149-54E0-319A-BAFA-6A8A55C0AA73` |
| Upstream release | [CubeLabsNZ/tnoodle-lib-native-v1 v1.0](https://github.com/CubeLabsNZ/tnoodle-lib-native-v1/releases/tag/v1.0), 2023-02-24 |
| Source revision | `e50c528feb8220b99eb66575a748e88391300f1f` |
| Release asset | `TNoodleLibNative.xcframework.tar.zst`, `ios-arm64/lib-scrambles.dylib` |
| Original release image SHA-256 | `8072a49418150b0516ed829a03820544dd6b5568d840754c2a9e1f7f56db7fff` |
| Embedded module versions | `scrambler-min2phase`, `scrambler-threephase`, `scrambler-sq12phase`, `lib-svglite`: `0.18.1` |
| Runtime metadata | GraalVM `22.1.0.1 Java 17 CE`, Java `17.0.3`, `IOS_AARCH64` |

The prior release comparison removed the local ad-hoc signature on an **analysis
copy**, then found only offsets `0x6c1/0x6c2` different: `__LINKEDIT.vmsize` was
147456 instead of 49152. Normalizing that field produced the original release
hash. Loaded sections and exports matched. This establishes release lineage,
not the original signer's identity or a byte-reproducible source build. The
vendor input remains untouched. The recorded hash was rechecked for this migration.

## Included Source and Notices

The repository now contains the complete upstream **project source archive** for
that revision, not merely a URL:

`ThirdPartySources/TNoodle/tnoodle-lib-native-v1-e50c528feb8220b99eb66575a748e88391300f1f.zip`

- Origin: [GitHub source ZIP at the pinned commit](https://api.github.com/repos/CubeLabsNZ/tnoodle-lib-native-v1/zipball/e50c528feb8220b99eb66575a748e88391300f1f).
- SHA-256: `30354467a70845c1b97c201c2f90aa9dc2ed5cadadb602c677d7bfed83712eef`.
- Archive comment identifies the full revision; root is
  `CubeLabsNZ-tnoodle-lib-native-v1-e50c528/`.
- The existing research ZIP was byte-compared against a fresh download from this
  URL. Only this verified source ZIP was retained from the ignored research
  directory; no signed apps, provisioning profiles, disassembly, release dylibs
  or generated native build output were copied.
- It contains the root/module Maven POMs, Gradle build definitions/wrapper,
  puzzle code, SVG support, three solver modules, upstream LICENSE, source
  headers and resources. The Gradle bootstrap JAR is retained as supplied by
  upstream; it is not a generated CubeFlow app binary. The adjacent
  `Gradle-Wrapper-Apache-2.0.txt` preserves the Apache license for that bootstrap.
  Its precise version is not authenticated: the JAR hash differs from Gradle's
  published 7.5.1 wrapper hash despite the properties requesting Gradle 7.5.1.
- The native C-entry-point wrapper `class Main` is in
  `scrambles/src/main/java/org/worldcubeassociation/tnoodle/scrambles/PuzzleRegistry.java`.
  It is **not** a missing standalone `Main.java`. It exports
  `tnoodle_lib_scramble` and `tnoodle_lib_draw_scramble`.

Verify and extract from repository root:

```sh
shasum -a 256 -c ThirdPartySources/TNoodle/SHA256SUMS
unzip ThirdPartySources/TNoodle/tnoodle-lib-native-v1-e50c528feb8220b99eb66575a748e88391300f1f.zip -d /path/to/source-workspace
```

`CubeFlow/Resources/ThirdPartyNotices/TNoodle-GPL-3.0.txt`,
`TNoodle-native-provenance.txt`, `Graal-SubstrateVM-GPL-2-Classpath.txt` and
`Graal-SDK-UPL-1.0.txt` remain intact. Retain all source-file copyright/license
notices in any source delivery, including WCA and individual solver authors.

## Build Definitions Recovered, Not a Validated Rebuild Recipe

The pinned archive's root POM includes `scrambles`, `svglite`, `min2phase`,
`threephase`, and `sq12phase`. The native `scrambles/pom.xml` sets:

- Java source/target 17, Maven compiler plugin `3.8.1`.
- GluonFX Maven plugin `1.0.16`; main class
  `org.worldcubeassociation.tnoodle.scrambles.Main`.
- `library-support` dependency `22.0.0.2`, scope `provided` (a declaration,
  not proof that this exact version is the linked runtime).
- Target profiles `ios`, `ios-sim`, `android`; default target `host`.
- Native-image arguments, exactly as declared:

```text
-g
-H:+LIROptStackMoveOptimizer
-H:+LIROptRedundantMoveElimination
-H:+LIROptControlFlowOptimizer
-H:+LIROptConstantLoadOptimization
-H:+LIROptNullCheckOptimizer
-H:+LIROptLSRAEliminateSpillMoves
-H:+LIROptLSRAOptimizeSpillPosition
-H:DashboardDump=fortune
-H:+DashboardAll
-H:+DashboardPointsTo
-H:+DashboardPretty
-H:ServiceLoaderFeatureExcludeServices=sun.security.ssl.Debug,sun.security.ssl.SSLLogger
-H:-UseServiceLoaderFeature
-H:DisableURLProtocols=http,https
```

Declared linker arguments:

```text
--sysroot=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk
-flto
-Wl,-dead_strip
-Wl,-x
```

These are the project's arguments, not a complete captured native-image command:
Gluon/Substrate add target configuration and arguments. No original invocation,
environment overrides or build log was recovered. In particular, the original
shared-library target/options and any externally supplied reachability settings
must be recovered rather than invented as a supposedly validated shell command.

The archive's README documents Gradle tasks for Java artifacts, **not** a verified
iOS native shared-library recipe. Its wrapper requests Gradle `7.5.1`. Plugin
`1.0.16` depends on Substrate `0.0.56`; the inspected default static Java SDK is
`18-ea+prep18-8`, overridable through `gluonfx.javaStaticSdkVersion`. That default
must not be equated to the authenticated original input. Host Java `17.0.3` does
not identify the linked static JDK's version or patches.

Build-tool source references (not included here as extra app dependencies):

- [GluonFX Maven plugin 1.0.16 source artifact](https://repo.maven.apache.org/maven2/com/gluonhq/gluonfx-maven-plugin/1.0.16/gluonfx-maven-plugin-1.0.16-sources.jar).
- [Substrate 0.0.56 source artifact](https://repo.maven.apache.org/maven2/com/gluonhq/substrate/0.0.56/substrate-0.0.56-sources.jar).
- [Gluon Graal release family](https://github.com/gluonhq/graal/releases/tag/gluon-22.1.0.1-Final),
  [source revision](https://github.com/gluonhq/graal/tree/08e1c57bc6b6de932b0faed2f49b21a1a54a39fe).

## CubeFlow Packaging and Local Changes

Included integration source remains in `CubeFlow/Views/Shared/TNoodleNativeBridge.h`,
`TNoodleNativeBridge.m`, and `TNoodleScrambler.swift`. No Java/native algorithm or
memory-management change is made by this licensing pass.

The existing `Scripts/package-tnoodle-framework.sh`,
`Config/TNoodleRuntime/Info.plist`, `Config/TNoodleRuntime/README.md`, and Xcode
project contain the app packaging instructions. The script is a **packager**, not
a Java/Graal compiler. It copies the device image into
`CubeFlow.app/Frameworks/TNoodleRuntime.framework/TNoodleRuntime`, removes an
obsolete ad-hoc signature on that copy, adjusts the Mach-O install identity to
`@rpath/TNoodleRuntime.framework/TNoodleRuntime`, and uses Xcode signing only when
enabled. The original vendor image and native loaded code stay unchanged.
Simulator behavior and signing configuration are unchanged. The script is not
executed in this task.

## Runtime Inventory Still Required

Inspected Graal SubstrateVM/OpenJDK sources use GPLv2 with Classpath Exception;
Graal SDK uses UPL 1.0. These notices do not authenticate every static library
in the device image. JavaCPP `1.5.2`, LLVM `9.0` and jcodings
`1.0.56-SNAPSHOT` resources occur in the image; distinguish metadata/build-only
tools from actually linked redistributed code before assigning obligations.

Outstanding concrete materials:

1. Actual Java static SDK archive identity/checksum and matching source/patches
   for the runtime portions linked into this native image.
2. Original native shared-library build invocation, necessary configuration and
   external/generated-input provenance needed to regenerate the program; recover
   any build-specific wrapper/tool changes not already in the supplied source.
3. A linked-runtime/dependency inventory with the applicable copyright/license
   notices and corresponding source for covered incorporated portions.
4. A maintained recipient-facing delivery arrangement for that complete set,
   alongside the binary, with clear instructions and availability appropriate
   to the distribution method. This partial archive is not a promise that the
   missing materials are already obtainable from CubeFlow.

The absence of a byte-identical rebuild is **not** by itself the blocker. The
blockers are missing identification/source for linked covered runtime portions
and necessary build materials. This does not assert an obligation to redistribute
every general-purpose compiler or Apple's SDK, nor demand special TNoodle
permission where ordinary license compliance would suffice.

## Recipient Access and Distribution Decision

Recipients of this repository snapshot can obtain the verified TNoodle Java
project source directly from the included ZIP without depending on GitHub's
future availability. They can also inspect CubeFlow's bridge and packaging source
in this tree. The remaining runtime/build materials are **not yet supplied as a
complete set**. Retain this limitation when redistributing any source inventory.

Before publishing the existing binary (including a GitHub push that contains it),
close the four gaps above and provide the corresponding materials by a suitable
GPL delivery method. If the original inputs cannot be recovered, a separately
authorized source rebuild with known inputs may establish a new distributable
baseline; no rebuild or replacement is authorized or performed here.

See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and
[licensing-release-gate.md](licensing-release-gate.md). This document does not
clear Apple distribution terms, privacy requirements, or signed runtime acceptance;
those are outside this licensing migration.
