# TNoodle Native Source Inventory and Delivery

Evidence date: 2026-10-23. **Verdict: INCOMPLETE.** Four pinned project/tool/runtime
source archives are now included; binary distribution remains blocked pending
the specific runtime/build-source gaps below. This is neither
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
  URL during the migration. This follow-up adds only the three verified source
  archives below, not signed apps, provisioning profiles, disassembly, release
  dylibs or generated native build output.
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
python3 Scripts/verify_tnoodle_source_delivery.py
unzip ThirdPartySources/TNoodle/tnoodle-lib-native-v1-e50c528feb8220b99eb66575a748e88391300f1f.zip -d /path/to/source-workspace
```

The Python verifier uses Python 3.11+ and only its standard library. It does not
load the native library, download files, compile, sign, or extract archives.
An integrity pass is **not** a completeness pass: `--require-complete` exits 2
while the documented delivery gaps remain. A hash/path failure exits 1.

### Additional Included Source Archives

All paths in this table are under `ThirdPartySources/TNoodle/`; filenames pin
the full source commit, not a moving branch. Existing TNoodle source is not duplicated.

| Archive | Revision / version | SHA-256 | Scope |
| --- | --- | --- | --- |
| `gluon-graal-08e1c57bc6b6de932b0faed2f49b21a1a54a39fe.tar.gz` | `08e1c57bc6b6de932b0faed2f49b21a1a54a39fe`, Gluon 22.1.0.1 release family | `8f5ab43e9c73fffccda59fc59821f71748f01d8bdfd8e48459a16ea44f4395fe` | SubstrateVM, SDK, native helpers, build suites, release workflow and original third-party notices; complete source archive, not a compiler installation |
| `substrate-cb0447fc6d448f31fc28945ffbf3c2c7845d8ca5.tar.gz` | `cb0447fc6d448f31fc28945ffbf3c2c7845d8ca5`, 0.0.56 | `ed3a33489bbcca8cf71671b14cf88b924a8176702c0b5f8dd58f818977babe69` | Build dispatcher/targets, native iOS support, JNI/reflection configuration, Gradle definitions and licenses |
| `gluonfx-maven-plugin-54f979b8f8ad7bd962f283f4e9c2e4c9f45641d5.tar.gz` | `54f979b8f8ad7bd962f283f4e9c2e4c9f45641d5`, 1.0.16 | `9a8d2f5e24a848eb3e88a561406e13219ef2e0514703882da85dda94398f2c5a` | Maven goals and property/classpath handling, POM and BSD notice |

The three archives' **13,591 / 235 / 28 file blobs**, respectively, were hashed
using Git's blob format and matched against the complete, non-truncated official
Git trees at those commits, with no missing or differing blobs. Substrate's 48
and GluonFX's 15 Java files additionally match their official Maven Central source
JARs byte-for-byte. The earlier local JARs match fresh Central downloads. Complete
repository archives are included instead of duplicating the JARs: source JARs omit
native/resource/build files needed to understand the target pipeline.

[`source-manifest.json`](../ThirdPartySources/TNoodle/source-manifest.json) records
archive origin URLs, revisions, SHA-256, source/license member hashes, binary
metadata addresses, dependency classifications, protected integration-file hashes
and open gaps. Original licenses, headers and `THIRD_PARTY_LICENSE.txt` remain
inside the unmodified archives. These supersets include tests, tools and other
targets; their presence is not evidence that all their code is in the iOS image.

The Xcode project integration-file digest was refreshed on 2026-10-28 for
CubeFlow 0.15.0 build metadata. This does not change the archived sources,
the native image, its provenance claims or the INCOMPLETE delivery verdict.

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

These are the project's arguments, not a complete captured native-image command.
The recovered Substrate `AbstractTargetConfiguration` adds `-H:+SharedLibrary`,
other base flags, target flags, reflection/JNI/resource configuration and native
link inputs. `IosTargetConfiguration` provides the iOS 11 minimum, arm64/sysroot,
framework list, `-llibchelper`, `-lffi`, `-ldarwin`, and a shared-library branch
adding `-shared -undefined dynamic_lookup`. Its Java static library list and
search paths are now source-available rather than undocumented assumptions.

**Do not substitute `mvn gluonfx:sharedlib` as a verified complete recipe.** In
1.0.16 that goal invokes `nativeSharedLibrary()`, sets shared-library state and
calls `DarwinTargetConfiguration.createSharedLib()`, which adjusts the install
identity of an existing output. It does not itself perform native compile/link.
`gluonfx:build` invokes compile and link, but does not establish the original
shared-library override sequence. The final binary is a dylib; how the original
builder selected/configured all stages remains unverified. No guessed build
script, override, patch or successful-rebuild claim is supplied.

The archive's README documents Gradle tasks for Java artifacts, **not** a verified
iOS native shared-library recipe. Its wrapper requests Gradle `7.5.1`. Plugin
`1.0.16` depends on Substrate `0.0.56`; the inspected default static Java SDK is
`18-ea+prep18-8`, overridable through `gluonfx.javaStaticSdkVersion`. That default
must not be equated to the authenticated original input. Host Java `17.0.3` does
not identify the linked static JDK's version or patches.

Official source artifact/release references, in addition to the included archives:

- [GluonFX Maven plugin 1.0.16 source artifact](https://repo.maven.apache.org/maven2/com/gluonhq/gluonfx-maven-plugin/1.0.16/gluonfx-maven-plugin-1.0.16-sources.jar).
- [Substrate 0.0.56 source artifact](https://repo.maven.apache.org/maven2/com/gluonhq/substrate/0.0.56/substrate-0.0.56-sources.jar).
- [Gluon Graal release family](https://github.com/gluonhq/graal/releases/tag/gluon-22.1.0.1-Final),
  [source revision](https://github.com/gluonhq/graal/tree/08e1c57bc6b6de932b0faed2f49b21a1a54a39fe).

The included Graal release workflow names `jvmci-22.1-b06`; that official Labs
OpenJDK 17 tag resolves to
[`05e32d91e144823314b0eda9560de949ef6d40ae`](https://github.com/graalvm/labs-openjdk-17/tree/05e32d91e144823314b0eda9560de949ef6d40ae),
merging `jdk-17.0.3-ga`. This is an externally available, pinned **reference**, not
an authenticated replacement for the missing iOS static SDK source. The workflow's
Darwin JDK selection uses `mx fetch-jdk` with `mx` from `master`; the tag alone does
not authenticate the original host's exact selection, either. No large unverified
JDK source tree or full compiler installation was added merely to appear complete.

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

### Direct Binary Observations

The image has 78 defined/exported symbols and no DWARF sections; local Java/native
symbols were stripped. This prevents an exact retained-method/object-file census
from ordinary symbol names. POM resources and heap class names do not substitute
for that census.

Mapped C-string data at exported SVM symbol addresses confirms:

```text
VM.Target.StaticLibraries=liblibchelper.a|libdarwin.a|libjvm.a
VM.Target.Libraries=z|pthread|-framework Foundation|dl
VM.Target.Platform=org.graalvm.nativeimage.Platform$IOS_AARCH64
VM.Target.LibC=com.oracle.svm.core.c.libc.NoLibC
```

The verifier rechecks these strings through Mach-O segment address-to-file-offset
mapping, not a loose text search. The static list is Graal's list, **not** a complete
list of subsequent native linker inputs. Recovered Graal code maps those three
names to `com.oracle.svm.native.libchelper`, `com.oracle.svm.native.darwin`, and
`com.oracle.svm.native.jvm.posix` (including `JvmFuncs.c`). This establishes source
families, not the exact cross-compiled archive's patches or build configuration.

At `0x4000`, CPU initialization writes the ARM FP/ASIMD feature bytes and uses the
distinct `determineCpuFeaures` diagnostic string from Substrate's `native/ios/dummy.c`.
Its three empty JDK17 JNI functions occur at `0x4048`, `0x404c`, `0x4050`, each a
single ARM64 `ret`. This supports actual incorporation of that native support
source, rather than classifying all of Substrate as build-only. GluonFX's Maven
implementation itself is only established as a build dependency.

`LC_LOAD_DYLIB` lists the external system libz/libSystem/libc++ and Apple frameworks;
the full ordered list is in the manifest and verifier. This is not evidence that
all their APIs execute, nor a reason to redistribute Apple's SDK. Native JDK/JNI
code and JVM exports are incorporated, but exact static SDK inputs remain unknown.

JavaCPP `1.5.2`, LLVM `9.0` and jcodings `1.0.56-SNAPSHOT` resource text is present.
Graal's complete `THIRD_PARTY_LICENSE.txt` and suite dependency definitions have
now been recovered, including JavaCPP/LLVM notices. This does not prove that an
LLVM compiler or every metadata dependency is retained executable runtime code.

### License Scope of Recovered Sources

Graal SubstrateVM uses GPLv2 with Classpath Exception; SDK uses UPL 1.0. Do not
confuse **Gluon Substrate** (the separate build/native-support project) with
**SubstrateVM**. In Gluon Substrate 0.0.56, `dummy.c` explicitly grants GPLv3-or-later
and attributes Copyright (c) 2022, Gluon; inspected Java files also grant GPLv3-or-later.
Its root LICENSE is GPLv2 and published POM has an inconsistent GPLv2/LGPL URL
label. Both original root and per-file texts are preserved, not rewritten to one
project-wide SPDX claim. GluonFX uses BSD-3-Clause with its own retained notices.
No new blanket GPL grant is placed over any archive.

### Recovery Attempts and Remaining Gaps

The resolver's real default candidate URLs were checked. The static SDK at
`staticjdk/staticjdk-ios-arm64-gvm-18-ea+prep18-8.zip` is accessible and contains
30 `.a` files, but no source, license, revision or build record. The official
`gluonhq/mobile` repository's exact `prep18-8` tag is absent (HTTP 404); its existing
prep18-2/3/4 tags must not be substituted. The correct CLIB default URL is
`clibs/ios-arm64-ea+27.zip`, derived from `Triplet.getClibsVersion()`, **not**
`ios-arm64-27.zip`. The accessible candidate contains four binary libraries
(`liblibchelper.a`, `libdarwin.a`, `libjvm.a`, `libffi.a`) and no source. Hashes and
full URLs are in the manifest. Those small candidate packages remain only in ignored
research, not the delivery set; neither is authenticated as the original input.
No original `.gluon` or `.m2` input cache was available locally. No local materials
were deleted and no compiler installation was downloaded.

Outstanding concrete materials:

1. **G1, static JDK:** actual input identity and matching source/platform patches
   for incorporated JDK code. Expected exact version remains unknown. Obtain the
   builder's SDK identity and supplier source record; Java 17.0.3 is not that record.
2. **G2, cross CLIBs:** authenticate actual iOS helper/JVM library source/patch/build
   mapping; determine whether `libffi` code survived linking. The default candidate
   and matching Graal source family do not establish all original platform inputs.
3. **G3, build recipe:** supply sufficient actual shared-library stage configuration,
   overrides/reachability inputs and any modified-tool source. Stock POMs, target
   implementation and wrapper are now provided; missing original logs alone are
   not the criterion, and a speculative replacement recipe is not acceptable.
4. **G4, inventory/delivery:** settle retained native/archive-member and resource
   provenance with a builder link/reachability inventory, complete applicable notices
   and covered source, then make the complete set obtainable beside the binary.

The manifest records each missing component, expected-version limit, inclusion
evidence, recovery attempts, why it matters, and a concrete supplier/builder action.
These are source-delivery gaps, not App Store-specific objections.

The absence of a byte-identical rebuild is **not** by itself the blocker. The
blockers are missing identification/source for linked covered runtime portions
and necessary build materials. This does not assert an obligation to redistribute
every general-purpose compiler or Apple's SDK, nor demand special TNoodle
permission where ordinary license compliance would suffice.

## Recipient Access and Distribution Decision

Recipients of this repository snapshot can obtain the TNoodle project, matching
Graal source family, pinned native support and build-tool source directly from
the four included archives without depending on GitHub's future availability.
Origin URLs and revision/member checksums are recorded for each archive. Extract
each `.tar.gz` with `tar -xzf <archive> -C <source-workspace>`; each has a separate
commit-named root. They can also inspect CubeFlow's unchanged bridge and packaging
source in this tree. This is usable source access, but it does **not** yet provide
authenticated source for every covered part of the exact binary. Do not advertise
the static integrity check as a complete Corresponding Source certification.

Before publishing the existing binary (including a GitHub push that contains it),
close the four gaps above and provide the corresponding materials by a suitable
GPL delivery method. If the original inputs cannot be recovered, a separately
authorized source rebuild with known inputs may establish a new distributable
baseline; no rebuild or replacement is authorized or performed here.

See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and
[licensing-release-gate.md](licensing-release-gate.md). This document does not
clear Apple distribution terms, privacy requirements, or signed runtime acceptance;
those are outside this licensing migration.

## Focused Static Verification Results

The 2026-10-23 follow-up verified all four archive checksums, required source/license
member hashes, repository integration hashes, and the mapped binary metadata/load
list. The static verifier passed; `--require-complete` correctly returned 2 for
INCOMPLETE. Four negative checks rejected an unsafe path, incorrect archive hash,
incorrect license-member hash and incorrect SVM metadata without editing artifacts.
Local documentation links and manifest paths were checked. Screening the 13,854
files in the three newly included upstream archives found no private-key markers,
listed signing-package paths or scanned credential patterns; this is a focused
screen, not an exhaustive guarantee about all possible secrets.

Root LICENSE, application source, existing bridge/packager/configuration, all
vendor files and original source ZIP remain unchanged. The provenance text only
receives an appended follow-up; existing upstream notice content is preserved.
`git diff --check` passes. No Xcode/native-image build, application test suite,
device run, signing, commit, push or deletion of local build materials is performed.
