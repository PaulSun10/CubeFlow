# TNoodle Privacy Manifest Assessment

Date: 2026-10-23. Scope: the existing TNoodle privacy warning only.
Includes the focused implementation follow-up. No OAuth, runtime, algorithm,
signing, or licensing changes. The existing source inventory's packager hash
was mechanically refreshed; no source archives or provenance claims changed.

## Decision

**NEEDS EXTERNAL VERIFICATION.** The warning originates in a CubeFlow-specific
evidence gate (classification B); the remaining privacy-purpose decision is
classification D. No Apple rejection has been reproduced. This is not evidence
that every XCFramework needs a manifest, nor evidence that this binary is clear
for distribution. Keep the warning and do not supply invented reasons. The
follow-up fixes a real gate weakness: supplying a plist can no longer silently
clear the purpose-review warning.

OAuth migration can proceed independently when its backend is ready. That does
not clear the TNoodle privacy review for an External TestFlight upload.

## Warning and Packaging

- Originally, `Scripts/package-tnoodle-framework.sh:35` printed the warning
  only when `Config/TNoodleRuntime/PrivacyInfo.xcprivacy` was absent. Supplying
  any lintable plist, even an empty dictionary, skipped the warning without
  establishing valid purposes. The follow-up now rejects invalid structure
  and retains a precise purpose-review warning even if a manifest is supplied.
  Ordinary builds without a manifest remain possible; this warning is not a
  nonzero-exit release approval command or an Apple validation result.
- `CubeFlow.xcodeproj/project.pbxproj:248-260` invokes that script in the
  `Sign TNoodle Runtime` phase. Apple did not originate the quoted message.
- Neither the arm64 device slice nor x86_64 simulator slice in
  `Vendor/TNoodleLibNative.xcframework` contains a privacy manifest.
- The device image is an arm64 Mach-O dynamic library, not a static archive.
  Its SHA-256 remains
  `35ca5611930688d63e6e43b9e2a5d49d6c9dec08ca54a98a136645ce454b4103`.
- The script copies it into
  `CubeFlow.app/Frameworks/TNoodleRuntime.framework/TNoodleRuntime`, updates the
  copied install name, and conditionally signs that framework. The bridge uses
  `dlopen` on the bundled framework executable. Simulator builds skip it.
- An audited future manifest at the configuration path above is already copied
  to the framework root before signing. No placement correction is needed.
  The app's separate manifest is at `CubeFlow.app/PrivacyInfo.xcprivacy`.

## Apple Requirements Rechecked

1. Apple's [listed SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/)
   cover the named SDKs, all versions, and SDKs repackaging them; binary listed
   SDKs also have signature requirements. TNoodle, GraalVM, Gluon and OpenJDK
   are not named. The inspected integration provides no evidence of a
   repackaged listed SDK. This is not a complete static-component attestation.
2. Independently, [Required Reason API rules](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
   require accurate reasons for covered API use, including SDK code. An SDK
   cannot rely on the host app's declaration. Each dynamic library's containing
   bundle must report its covered API use. This rule is not limited to listed
   SDKs. Apple states undeclared required-reason use is not accepted by App
   Store Connect from May 1, 2024; this is relevant to uploads, not just public
   App Store release.
3. Apple's [placement instructions](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
   put an iOS framework manifest at its bundle root. Static libraries need a
   resource-bearing distribution arrangement; dynamic loading is not an
   exemption. Merely using the XCFramework format creates no blanket mandate.
4. The current [API and reason definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
   were checked using Apple's documentation JSON (the Markdown rendition omits
   its category/reason tables). They list fstat/lstat/stat, mach_absolute_time,
   and fstatvfs in the relevant categories. Reading a different field is not
   enough to assert an exemption or choose an unrelated reason.

## Behavior and Supported Limits

The bridge passes a puzzle index and receives a scramble string. The recovered
native entry point generates scrambles locally. Its POM disables HTTP/HTTPS
URL protocols. No collection, analytics, identifier transmission, or tracking
behavior was found in that integration and inspected source. This does not
prove that every native-image runtime path is inert. Linking CoreLocation or
other system frameworks alone does not demonstrate collection or tracking.
The image also imports sysctl; that symbol alone establishes neither
fingerprinting nor a reason declaration. No runtime observation was performed.

Existing disassembly/source attribution was rechecked against the unchanged
binary and recovered sources, without repeating source recovery:

| Category | Evidence | Why no declaration was added |
| --- | --- | --- |
| FileTimestamp | stat/fstat/lstat call sites; lstat at 0x5ca11c inspects /etc/localtime; other matched paths inspect file type or size. | C617.1 permits app/app-group/CloudKit container metadata, not this system path. Timestamp-field consumption is not established at these sites, and remaining caller/path scopes are incomplete. |
| DiskSpace | fstatvfs at 0x5ce2f8 matches NIO direct-I/O setup, reading f_frsize for alignment. | E174.1 concerns checking space before writing or deleting under low-space conditions with user-observable behavior. Alignment is not that purpose; no category exemption is assumed. |
| SystemBootTime | mach_absolute_time-backed System.nanoTime implementation exists. Puzzle creates Random; the examined JDK Random constructor uses nanoTime for seeding. | This supports a possible seed use, not proof of the compiled caller's execution phase. 35F9.1 covers elapsed measurements/timer calculations, not arbitrary random seeding. Other approved reasons do not establish coverage either. |

The app manifest declares UserDefaults CA92.1, FileTimestamp C617.1 and
SystemBootTime 35F9.1/3D61.1, with tracking false and no tracking domains. It
has no DiskSpace declaration. Matching category names neither validate the
SDK's purposes nor substitute for its own manifest. App declarations were
not changed or independently re-audited in this task.

Pinned implementation references:
[TNoodle wrapper and Puzzle source](https://github.com/CubeLabsNZ/tnoodle-lib-native-v1/tree/e50c528feb8220b99eb66575a748e88391300f1f/scrambles/src/main/java/org/worldcubeassociation/tnoodle/scrambles),
[Graal Darwin substitution](https://github.com/gluonhq/graal/blob/08e1c57bc6b6de932b0faed2f49b21a1a54a39fe/substratevm/src/com.oracle.svm.core.posix/src/com/oracle/svm/core/posix/darwin/DarwinSubstitutions.java),
[JDK Random behavioral reference](https://github.com/openjdk/jdk17u/blob/jdk-17.0.3-ga/src/java.base/share/classes/java/util/Random.java).
The JDK reference is a behavior match, not an assertion of exact linked SDK
identity. Local detailed call-site evidence: `docs/tnoodle-native-evidence-oct22.json`.
The previous direct-branch analysis left indirect calls unresolved; it does
not prove the relevant functions unreachable.

## Focused Follow-up: Call Paths and Implementation

The current official Apple category/reason definitions were rechecked. No
applicable exception or approved purpose was established for the problematic
uses below. Not consuming the timestamp/free-space fields does not, without
Apple guidance, establish an exception for these listed API calls. The SDK
wrapper reason 0A2A.1 is not established either: CubeFlow requests a scramble,
not a wrapper-provided file-timestamp operation, and the runtime uses the
metadata for its own timezone/file operations.

- **Timezone metadata:** Graal `TimeZoneSubstitutions.java` resets the cached
  default timezone and substitutes `getSystemTimeZoneID` with
  `LibCHelper.SVM_FindJavaTZmd`. The pinned `libchelper/src/timeZone.c` POSIX
  branch calls JDK `findJavaTZ_md(NULL)`. The examined JDK reference falls
  back from an absent/empty `TZ` to `getPlatformTimeZoneID`, then lstat of
  `/etc/localtime`, symlink handling and file-content matching. This explains
  the matched native call sites, but does not prove that CubeFlow requests
  the default timezone on every run. The exact compiled Java callers remain
  unresolved. UnixFileSystem `getBooleanAttributes0 -> statMode -> stat`
  separately checks existence/type; NIO `size0 -> fstat` checks file size.
- **Direct I/O:** the JDK behavioral reference follows
  `FileChannelImpl(direct=true) -> FileDispatcherImpl.setDirectIO -> setDirect0
  -> fcntl(F_NOCACHE) -> fstatvfs -> f_frsize`. The conditional direct-I/O
  constructor path does not establish that CubeFlow exercises it. CubeFlow's
  exposed native entry passes a puzzle index, not a file-channel option. The
  retained native function is confirmed; its runtime callers are not.
- **Clock/seed:** `Main.puzzles -> Puzzle` constructs `java.util.Random`;
  the examined JDK default constructor uses `System.nanoTime`. In addition,
  pinned Graal `RandomAccessors.initialize` explicitly initializes a runtime
  seeder for SplittableRandom/ThreadLocalRandom with
  `mix64(currentTimeMillis) ^ mix64(nanoTime)` when secure seeding is disabled.
  Darwin's nanoTime substitution uses `mach_absolute_time`. This is stronger
  source evidence of non-timer seed purposes in the runtime, not proof that
  both Java chains execute in this particular compiled image. Potential
  elapsed-time callers do not justify the separate seed use.

Additional primary implementation references:
[Graal timezone bridge](https://github.com/gluonhq/graal/blob/08e1c57bc6b6de932b0faed2f49b21a1a54a39fe/substratevm/src/com.oracle.svm.native.libchelper/src/timeZone.c),
[Graal runtime seed initialization](https://github.com/gluonhq/graal/blob/08e1c57bc6b6de932b0faed2f49b21a1a54a39fe/substratevm/src/com.oracle.svm.core/src/com/oracle/svm/core/jdk/RandomAccessors.java),
[JDK conditional direct-I/O caller](https://github.com/openjdk/jdk17u/blob/jdk-17.0.3-ga/src/java.base/share/classes/sun/nio/ch/FileChannelImpl.java).

No safe local elimination is established. Removing imports, patching the
stripped binary, globally interposing libc/clock functions, or setting global
TZ would risk other callers or change runtime behavior without proving the
issue removed. Changing Swift/Objective-C code does not remove these retained
native implementations. A narrowly scoped source-level runtime fix could be
considered after call-site/approved-purpose clarification; no binary patch or
SDK rebuild was performed.

Implemented in the existing packager, using Xcode's `/usr/bin/python3` and
only its standard library when a candidate SDK manifest is present:

- Reject non-dictionary/empty manifests, missing native API categories,
  malformed entries, duplicate categories/reasons, unknown or cross-category
  reason codes, unexpected root keys and malformed tracking fields. Nonempty
  collection declarations require a separately reviewed validation path.
  These are conservative local review checks, not a full Apple schema or
  proof that any listed code matches TNoodle's behavior.
- Preserve optional manifest copying to the framework root before signing.
- Always emit the unresolved API/purpose details and explicitly identify the
  warning as CubeFlow's evidence gate, not Apple's validation. A syntactically
  valid file cannot turn the review into approval. Once actual purposes or
  exclusions are established, this explicit gate needs a reviewed update;
  simply adding a file intentionally cannot clear it.
- No production SDK manifest was created. Any manifests containing valid
  example code/category pairs in the tests are temporary fixtures, never
  declarations for the shipped runtime.

## Minimum Remaining Verification

The minimum external policy question is: for the three native uses described
above (system-timezone/type/size metadata, direct-I/O alignment, and monotonic
random seeding), does Apple require a declaration even when timestamp/free-
capacity values are unused, and if so which approved reason applies? No
matching reason or exemption was found in the published rules. Request an
approved reason if required rather than substituting C617.1/E174.1/35F9.1.
Neither Apple nor the vendor was contacted in this pass.

1. Obtain call-site/caller/phase and sanitized path-class evidence for the
   current device image during cold initialization, thread attachment and
   generation for supported puzzle paths. Use builder reachability/symbol
   evidence where available; a short trace with no hits cannot prove non-use.
   No device session was started in this task.
2. For reachable uses without a matching approved reason, obtain Apple's
   guidance using its [reason request channel](https://developer.apple.com/contact/request/privacy-manifest-reason/).
   Ask specifically about file-type/size access to system timezone files,
   fstatvfs block alignment, and nanoTime random seeding. Do not label them
   ordinary timer or free-space checks. If a purpose cannot be approved, a
   separately scoped runtime change may be needed; a rebuild is not assumed
   necessary before that determination.
3. Only then add accurate SDK declarations, inspect the signed archive and
   run Apple-side validation/processing. Acceptance alone would not establish
   that the declared purposes truthfully match behavior.

## Verification

- Initial read-only pass: 6 packaging tests passed.
- Implementation follow-up: `python3 Scripts/test_tnoodle_packaging.py`:
  **9 tests passed**, including 12 invalid-structure subcases and a malformed
  plist, optional manifest placement with the purpose warning retained, and
  removal of a previous declaration on incremental repackaging. Executes the real
  packager on temporary products without executing the device library or
  signing it. Checks Debug/Release packaging labels, loaded-section/ABI/vendor
  preservation, repeated packaging, simulator exclusion and failure guards.
- `plutil -lint`: app privacy manifest, runtime Info.plist and XCFramework
  Info.plist all passed. This is structure validation, not purpose approval.
- Both vendor slices inspected: arm64 device and x86_64 simulator Mach-O
  dynamic libraries. Neither has a manifest; the simulator bridge intentionally
  does not embed or execute its native image. Device SHA-256 remains the value
  recorded above; simulator SHA-256 remains
  `35ae8911823a2bb91db8aad58019d61bce9553465390caa2489219cb3f883290`.
  The packager tests preserve loaded native sections, exports, dependencies and
  minimum-platform commands, so no executable/ABI change was introduced. This
  is static preservation, not new physical loading/scramble acceptance.
- Existing local Release product inspected read-only at
  `build/competition-navigation-loading/DerivedData/Build/Products/Release-iphoneos/CubeFlow.app`:
  app manifest present; framework manifest absent. This is a pre-existing
  product, not a new archive or Apple validation result.
- No app build, TNoodle rebuild, upload, distribution validation, physical
  runtime execution, OAuth modification, commit or push was performed.
- Follow-up files changed: `Scripts/package-tnoodle-framework.sh`,
  `Scripts/test_tnoodle_packaging.py`, this assessment, and only the packager's
  SHA-256 field in `ThirdPartySources/TNoodle/source-manifest.json`. Prior dirty
  changes are preserved. App privacy declarations and vendor binaries remain
  unchanged. The unresolved warning is more specific, not suppressed.
