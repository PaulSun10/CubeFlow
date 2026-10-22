# Smart Cube Navigation and TNoodle Release Audit

Date: 2026-10-22. Scope: actual iPhone card navigation, TNoodle packaging,
privacy evidence, limited WCA follow-up and unsigned Release verification.

## 1. Executive Summary

- Proven by source and mounted negative control: the discovery NavigationStack
  adopted the custom presenter's hidden navigation owner. An isolated hosting
  test did not reproduce that hierarchy and was insufficient evidence.
- Corrected discovery-only ownership with a card-sized native navigation
  controller. Actual Timer and Settings presentation tests show one visible
  bar, native large/inline/large transitions and same-card connection changes.
- The original X overlay, surface and motion are unchanged. The title retains
  the existing 22 pt inset. No global navigation appearance was changed.
- Latest user correction: no saved devices means no My Devices section or
  empty-state sentence. Saved offline rows and Other Devices/refresh remain.
- The copied TNoodle image now has a real framework bundle, matching install
  name and explicit framework loading path. Vendor code was not rebuilt.
- Distribution is NOT cleared: the Release-only compile failure detailed below,
  SDK API purposes/declarations, exact binary
  licensing/provenance, signed device loading and Apple-side validation remain
  outstanding. User-confirmed Developer/App Store Connect setup is not a gap.
- SceneKit animation is physically accepted by the user and frozen. Guidance
  long inverse/recovery accumulation is explicitly deferred and unchanged.

Evidence labels below distinguish source, automated tests, user observation,
inference and external acceptance. No physical device was accessed this pass.

## 2. Why the Previous Title Test Missed the Defect

The previous isolated test hosted SmartCubeManagementCard directly in a window.
Production instead presents through CompetitionNativePresentation and its
CompetitionResultsNavigationController, which hides the bar for its root.
The nested SwiftUI navigation container reused that hidden owner rather than
installing an independently visible card bar.

The mounted negative control logged, for both Timer and Settings:
`CompetitionResultsNavigationController:hidden=true:title=Smart Cube`.
There was no visible card navigation bar. The negative run failed as expected;
later timeout/teardown failures in that run are not separate production findings.
This is a reproduced source-level explanation consistent with the user's
physical missing-title report, not a claim of new iPhone acceptance.

## 3. Actual Presentation Hierarchy

Timer -> its existing Smart Cube management action ->
CompetitionNativePresentation -> CompetitionResultsNavigationController
(hidden root bar) -> hosted SmartCubeManagementCard -> discovery or management.

Settings -> ConnectedDevicesView -> SmartCubeLabView -> its existing managed
device selection/presenter -> the same presentation/controller/card chain.
Disconnect changes the card's content to discovery; reconnection changes it
back to management without another presentation.

The correction places SmartCubeDiscoveryNavigationHost only in the embedded
picker branch. Its local UINavigationController owns a UIHostingController
whose root is the original discovery List. The outer presenter's bar stays
hidden. Standalone picker navigation and the shared result presenter are not
rewritten. Timer/Settings DEBUG entry seams invoke the existing actions.

## 4. Native Title Correction and Mounted Tests

The local host sets the localized navigation-item title, native always-large
mode, prefersLargeTitles, transparent host backgrounds and existing directional
insets. UIKit owns scrolling collapse/restore. Environment values are forwarded
to the hosted list. No fake title, custom title animation, private API, global
appearance change or second sheet is introduced. APIs are iOS 15 compatible.

SmartCubePresentedNavigationTests mount TimerTabView and SettingsTabView in a
real window, then use the production presenter. Settings destinations are
pushed programmatically into its real native navigation owner; this is not a
physical tap-through of the Settings NavigationLinks. Synthetic sessions drive
the existing connection state. No BLE hardware is involved.

Assertions cover visible title ink inside the card, 22 pt leading ink position,
one visible navigation bar, large/inline/large geometry, disconnect discovery,
reconnect management, unchanged presentation identity, no nested presentation
and unchanged underlying navigation stack. Native scroll offsets are used by
tests only, not production. The test runtime is iOS 26.5 Simulator, not the
user's physical iOS 27.2 beta environment.

## 5. Card Design, X and Latest Empty-State Correction

The original top-trailing close overlay through competitionResultCardShadow
was extracted from the baseline and compared byte-for-byte: identical. Its
12 pt padding, original close component and all enclosing surface/motion
modifiers remain. Device-name/battery typography, cube sizing, reset/disconnect/
forget controls, connected HUD and Many Connected/One Active are not redesigned.

SmartCubeDiscoverySections now emits My Devices only when saved rows exist.
The removed empty-state text is not replaced. Offline saved identities still
appear when nothing is active. Other Devices remains present even if empty,
with its original refresh button and connection eligibility. The mounted test
checks empty -> saved offline -> forget final saved identity without remounting.

Actual new screenshots were inspected visually, not only OCR:

- `build/smart-cube-navigation-release-oct22/discovery-images/B4480661-835A-4C69-82E7-36DCB84C72EA.png`:
  actual Settings-disconnect card, native inset title, unchanged X, no empty section.
- `build/smart-cube-navigation-release-oct22/discovery-images/B2A1A3D5-0593-41F0-8381-E13DE8D33AB3.png`:
  actual Timer discovery capture, covered by the same mounted assertions.
- `build/smart-cube-navigation-release-oct22/discovery-images/manifest.json`
  maps the inline, restored, saved/offline and empty-state attachments.

## 6. Frozen TNoodle Binary

Source: `Vendor/TNoodleLibNative.xcframework/ios-arm64/lib-scrambles.dylib`.
Size 37,867,808 bytes; SHA-256
`35ca5611930688d63e6e43b9e2a5d49d6c9dec08ca54a98a136645ce454b4103`;
UUID `D2D6B149-54E0-319A-BAFA-6A8A55C0AA73`; arm64 MH_DYLIB;
minimum iOS 11, recorded SDK 16.2; original ad-hoc signature.
Original identity: `@rpath/lib-scrambles.dylib`. Dependencies are system images.
The original vendor XCFramework and image remain byte-identical.

The old build phase copied a bare dylib to the app root. An XCFramework
directory around the vendor artifact does not fix the final app structure.
Apple's [bundle placement rules](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle)
distinguish supported embedded frameworks from unsupported third-party
standalone iOS dylibs. The Xcode Swift-system-library exception is not TNoodle.

## 7. Feasibility and Framework Packaging

The existing image has sufficient load-command padding. Stock Apple
codesign/remove-signature and install_name_tool operations can adjust the
copied image's identity without recompilation. Apple's
[code-structure guidance](https://developer.apple.com/documentation/xcode/embedding-nonstandard-code-structures-in-a-bundle)
and [DTS library identification guidance](https://developer.apple.com/forums/thread/736719)
support this metadata workflow; final signing must follow the adjustment.
No unsupported opcode patch or new Graal native image was introduced.

The generated product is:
`CubeFlow.app/Frameworks/TNoodleRuntime.framework/{TNoodleRuntime,Info.plist}`.
Its LC_ID_DYLIB is `@rpath/TNoodleRuntime.framework/TNoodleRuntime`.
Info.plist defines executable/name, unique bundle identifier, FMWK type,
iPhoneOS platform and minimum 15.0. Version 1.0/build 1 describe the wrapper,
not an invented TNoodle/Graal upstream version. Headers/modules are not needed
for this runtime-only dlsym consumer. The vendor XCFramework is not republished
as a new distributable XCFramework.

The script runs only for iphoneos, copies rather than edits the vendor image,
removes the copied old ad-hoc signature, changes its ID and optionally embeds
an accurately audited SDK manifest. It replaces only its own generated output,
refuses a symlinked output and removes only obsolete bare runtime copies from
the generated app. Existing signing, app versions and deployment settings stay.
Paths use the repository's actual `Scripts` casing and handle spaces.

## 8. Loading, ABI and Signing

The production bridge resolves the framework via NSBundle executable metadata
and explicitly dlopens that absolute URL. Legacy bare-dylib fallback loading
is removed. Missing framework/load failures remain explicit, not substituted
scrambles. Existing exported functions, dispatch-once initialization, thread
attachment/detachment, synchronization and scramble/prefetch behavior remain.

Automated packaging tests compare all file-backed loaded section contents,
addresses and lengths, exported symbols/addresses, architecture, dependencies
and platform/minimum load command against the vendor image. These are unchanged;
identity/signature metadata is intentionally different. This establishes static
ABI preservation, not execution equivalence or physical loader acceptance.

When Xcode signing is enabled, the script requires its configured identity,
signs the completed framework bundle and verifies it before outer app signing.
This pass deliberately uses CODE_SIGNING_ALLOWED=NO; that signing branch and
physical loading were not executed. See Apple's [framework embedding note](https://developer.apple.com/library/archive/technotes/tn2435/_index.html).
Simulator keeps its unavailable TNoodle bridge, without embedding the device
image. Existing device-only 3x3 unavailability and Swift 4x4-fast generation in
Simulator are both explicitly tested, not replaced by a new fallback.

## 9. Required Reason API Evidence

Prior disassembly found actual import call sites for stat/fstat/lstat/fstatvfs,
and the image references mach_absolute_time. These implicate FileTimestamp,
DiskSpace and SystemBootTime for review; imports alone do not prove execution
or a permitted purpose. Representative unslid call sites include lstat
0x5ca11c, fstat 0x5ca270, stat 0x5ca704 and fstatvfs 0x5ce2f8.

This pass adds a read-only conservative ARM64 direct-branch reachability
analysis from graal_create_isolate, graal_attach_thread and tnoodle_lib_scramble.
Its final walks were not truncated (962,477 / 792,799 / 901,849 instructions).
No modeled direct path to the target import stubs was found. Crucially,
2,345 / 2,132 / 2,272 indirect sites remain unresolved, including native-image
dispatch. This does NOT establish that the APIs are unreachable or unused.
The stripped internal symbols cannot attribute their Java/runtime purposes.

Evidence: `build/smart-cube-navigation-release-oct22/tnoodle-reachability.py`
and `.json`, plus the prior historical audit's call-site artifact. Disk-space,
timestamp and uptime execution during initialization or generation remain
unproven. No speculative E174.1 or other reason was assigned.

## 10. Privacy Manifest and Authorized Trace Plan

The app manifest is unchanged: UserDefaults CA92.1, FileTimestamp C617.1,
SystemBootTime 35F9.1/3D61.1. Prior app-source auditing remains the basis for
these app-owned declarations; it is not evidence of Graal's purposes.
No source-level disk-capacity behavior justifies extending it in this pass.
Apple requires [accurate API reasons](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api),
including the relevant SDK's use. TNoodle/Graal absence from the current
[specifically listed SDKs](https://developer.apple.com/support/third-party-SDK-requirements/)
does not waive those obligations.

There is intentionally no invented/empty TNoodle SDK manifest. After purposes
are established, put the accurate file at
`Config/TNoodleRuntime/PrivacyInfo.xcprivacy`; the packager validates and embeds
it at the framework root before signing, per Apple's
[manifest placement guidance](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk).
Until then it emits an explicit distribution-not-cleared warning.

Next separately authorized trace: cold-launch a signed Debug app stopped
before prewarm, record dlopen/isolate and individual scramble phases, obtain
the runtime slide, then break on the known module-relative call sites.
Inspect caller image/backtrace and sanitized path class, not personal paths.
Trace init and a small representative 333/444/Square-1/Megaminx set separately.
Use short module-filtered clock tracing rather than a noisy global uptime
breakpoint. Record counts and phase; absence in a few calls is not universal
nonuse. No such trace was run here. Request the exact Graal/JDK/native-image
flags, entry sources, symbol map and vendor purpose audit in parallel.
Runtime call evidence alone still does not establish an approved purpose.

## 11. Dependency Provenance and Licensing Gate

Existing packaged notices cover SwiftConfettiView MIT, PBL-Manager MIT,
Chen-Shuang FTO MIT and generated Square-1 references. No matching TNoodle/Graal
binary license/provenance/source-offer chain was found in those notices.
The official [TNoodle-lib upstream license](https://github.com/thewca/tnoodle-lib/blob/master/LICENSE)
is GPLv3. That is an actionable provenance question, not proof of the unknown
binary's exact applicable licensing or an App Store legal conclusion.
Embedded scrambler-min2phase 0.18.1 metadata is not the full image provenance.
Obtain the exact source/build/dependency license chain and required permission/
redistribution review. Merely adding an attribution would not resolve it.

## 12. Limited WCA Follow-Up

The unauthenticated [deployment metadata](https://www.worldcubeassociation.org/.well-known/oauth-authorization-server)
was saved and matches the previous snapshot. It advertises authorization_code,
refresh_token and secret_basic/secret_post authentication, but not `none` or
PKCE methods. Missing advertisement is not proof of rejection or enforcement.
No new authoritative deployment fact removes the existing provider dependency.
The prior pinned WCA/Doorkeeper source investigation is not repeated here.

Questions prepared for WCA Software Team, NOT sent:

1. Is S256 enforced on deployed authorization/code exchange, including wrong,
   missing-verifier and downgrade rejection?
2. How is a non-confidential native client registered, and can it exchange
   authorization codes and refresh tokens without a secret?
3. What exact custom-scheme/claimed-HTTPS redirects and matching rules apply?
4. Can the existing client convert, or is a new registration required? What
   happens to existing grants, refresh rotation/reuse, revocation and old apps?

Conditional options remain native public S256, or backend-assisted confidential
exchange if WCA cannot support that. Neither is selected or implemented. A
backend requires separate authorization and the existing ICP gate. Existing
embedded-secret and attempt-state/callback-hardening risks remain security
release gates; no credential values, OAuth flow, redirect, registration,
Keychain/session state or backend deployment were changed.

## 13. Release Configuration Audit

Repository facts: bundle com.paulsun.cubeflow, marketing 0.10.0, build 1,
app minimum iOS 15.0, existing automatic-signing/team settings retained.
The test target's newer minimum does not raise the app minimum. Release uses
whole-module compilation and excludes DEBUG. The runtime search path includes
@executable_path/Frameworks. No new entitlement or signing capability was added.

Bluetooth Always description and bluetooth-central background mode exist.
Calendar, local-network/Bonjour, location and photo-add descriptions are present.
No new permission-consuming feature is added; no arbitrary ATS exception or
new AlarmKit/Live Activity capability is invented. UILaunchScreen is configured.
Icon source references and compiled product metadata are checked below.
No App Store Connect configuration claim is made beyond the user's confirmation.
Current beta-toolchain upload eligibility still needs Apple-side validation.

## 14. Focused Tests and Build

Artifacts root: `build/smart-cube-navigation-release-oct22/`.

- `real-presentation-negative`: reproduced hidden production owner; expected
  failure, not part of a passing total.
- `real-presentation-fixed`: 7 XCTest passed (actual paths plus device polish).
- `focused-verified`: 58 XCTest, one incorrect new Simulator fixture assertion
  failed; all other 57 and 17 Swift Testing tests passed. The fixture had
  incorrectly expected device-only 3x3 generation on Simulator. Only that test
  expectation was corrected; production generation was not changed.
- `framework-tests-final`: all 3 framework tests then passed.
- `discovery-final`: all 6 affected mounted/discovery tests passed, including
  the added empty/saved/forgotten test and both actual presentation paths.
- `packaging-tests-final`: 6 Python tests passed, exercising real Debug/Release
  packaging, ABI/section preservation, simulator exclusion, obsolete output
  removal, invalid input, missing identity and symlink rejection.
- Distinct final coverage across these focused runs: 59 XCTest + 17 Swift
  Testing + 6 packaging tests = 82. Reruns are not counted as extra tests.
- Regression coverage retains management identity, offline discovery, connected
  HUD, Guidance lifecycle/latest targets, animation ordering and Timer scramble
  lifecycle/prefetch. No unrelated broad suite was run.
- Simulator logs include QoS inversion/WebKit diagnostics; not a zero-warning
  or physical acceptance claim.
- ONE unsigned generic iOS Release build FAILED, exit 65, on a pre-existing
  Competition DEBUG-guard/import defect. Details are in the final validation
  addendum below. No second generic build was run.
- Source plist/localization validation and shell syntax checks passed.

## 15. Exact Task-Owned Files

Existing at this pass's dirty baseline, modified:

- `CubeFlow/Views/iPhone/SmartCubeManagementCard.swift`: discovery native owner,
  environment forwarding and DEBUG entry probe; original X block retained.
- `CubeFlow/Views/iPhone/SmartCubeLabView.swift`: embedded host/list branch and
  DEBUG Settings entry seam; standalone flow/reset/scan behavior preserved.
- `CubeFlow/Views/iPhone/TimerTabView.swift`: DEBUG actual-action entry seam only.
- `CubeFlow/Views/iPhone/SmartCubeDiscoverySections.swift`: omit empty saved section.
- `CubeFlowTests/SmartCubeDiscoveryListTests.swift`: mounted saved-section lifecycle.
- `CubeFlow/Views/Shared/TNoodleNativeBridge.h`: shared framework resolver declaration.
- `CubeFlow/Views/Shared/TNoodleNativeBridge.m`: resolver and explicit device path.
- `CubeFlow.xcodeproj/project.pbxproj`: only TNoodle packaging phase integration.

New in this pass:

- `CubeFlowTests/SmartCubePresentedNavigationTests.swift`.
- `CubeFlowTests/TNoodleFrameworkTests.swift`.
- `Config/TNoodleRuntime/Info.plist`.
- `Config/TNoodleRuntime/README.md`.
- `Scripts/package-tnoodle-framework.sh`.
- `Scripts/test_tnoodle_packaging.py`.
- This report; uncommitted diagnostic/test/build artifacts under
  `build/smart-cube-navigation-release-oct22/`.

No animation/Guidance/solver, unrelated competition/Explore, vendor binary,
app privacy, permissions, signing identity or version changes were made.

## 16. Remaining Physical Acceptance

1. On the user's iOS 27.2 beta iPhone, open discovery from Timer and Settings.
   Verify inset localized large title, original X, native collapse and restore.
2. Verify empty saved state contains only Other Devices/refresh; save a cube,
   disconnect and confirm its passive row remains. Forget the last saved cube
   and confirm the entire My Devices section disappears.
3. Connect, disconnect and reconnect within the same card; verify management,
   single active identity, success HUD and unchanged underlying navigation.
4. After separate authorization, install a signed build and cold/warm exercise
   the actual TNoodle image across representative events, initialization and
   prefetch; verify no dyld/signing failure and preserve generated semantics.
5. Separately authorize the phase-specific privacy trace described above.

No physical actions are implied by these instructions. Previously accepted
animation remains accepted; Guidance recovery quality remains deferred.

## 17. First-TestFlight Gates

Confirmed unresolved: the Release compilation failure below, SDK
required-reason purposes/declarations and exact
native-image license/provenance clearance. Existing OAuth embedded-secret/
callback security migration remains outstanding and provider-dependent.
The bare-dylib output structure has been corrected, not waived.

Unverified: framework signing/load on physical iPhone, native title on iOS 27.2,
App Store archive validation/toolchain eligibility, account-side metadata and
privacy answers. An unsigned build cannot prove these. User-completed signing
and App Store Connect setup is NOT reported as missing.

Nonblocking deferred product work: Guidance inverse/recovery quality. No new
SceneKit animation defect was shown; that implementation remains frozen.

## 18. Next Actions

1. Separately approve the minimal existing Competition Release guard/import
   correction and a new validation build; the one-build budget is exhausted.
2. User physical UI acceptance, then separately authorized signed TNoodle load
   and targeted runtime-purpose trace.
3. Obtain exact vendor provenance/license and appropriate SDK privacy evidence;
   supply an accurate SDK manifest only after establishing permitted purposes.
4. Ask WCA the prepared deployment/registration questions; authorize a secure
   migration only after those answers, including existing-user token planning.
5. With distribution gates resolved, separately authorize signing/archive and
   Apple validation. This pass does not authorize archive, upload or TestFlight.

## Final Validation Addendum

The only generic build used configuration Release, generic/platform=iOS,
CODE_SIGNING_ALLOWED=NO and the existing DerivedData directory. Its log is
`build/smart-cube-navigation-release-oct22/final-generic-release.log`; exit 65.

Proven compile cause: `CompetitionDisclosureAcceptanceSurface.swift` imports
SwiftUI inside its initial `#if DEBUG`, but its `extension View` at line 373 is
outside that guard. In Release, View and the @ViewBuilder return type cannot
resolve. Downstream competitionDisclosureTitleProbe call sites then fail in
CompetitionExpandableTopCubers.swift and CompetitionTabView.swift. The file
matches this pass's baseline; it was not changed here. This is not evidence of
a defect in the new Smart Cube host or TNoodle image.

The minimal follow-up is to make the SwiftUI import available to the existing
Release no-op extension, retaining all DEBUG implementation guards. That
unrelated Competition source was deliberately not edited in this constrained
pass. No second generic build was run or disguised as a test build.

Compilation stopped before the TNoodle packaging phase. Therefore there is no
new complete Release app/framework whose signing, compiled icons, bundled
privacy or runtime exclusion can honestly be reported as verified. The real
packaging script's standalone Debug/Release tests passed, but do not substitute
for that integration build. Final Release symbol/DEBUG exclusion inspection
and generated-app manifest comparison remain blocked, not silently passed.

Static checks: all 13 image filenames referenced by the one AppIcon catalog
exist; Icon Composer assets reached the Release asset-compilation step.
Source Info.plist, project plist, wrapper plist, app manifest and English/
Simplified/Traditional Chinese Localizable.strings pass plutil. Shell syntax
and git diff --check pass. The original close-overlay comparison passes.
All 7,355 source/config/vendor/test hashes match immediately before versus
after the build. Against the dirty baseline, only the eight existing scoped
files listed above changed; no baseline file was removed. In particular the
animation, Guidance, solver and unrelated Competition code stayed unchanged.
No task-owned build/test process remains active. No commit, push, archive,
upload, signing change or physical-device action was performed.
