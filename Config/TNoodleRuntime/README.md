# TNoodle Runtime Packaging

`Scripts/package-tnoodle-framework.sh` wraps the existing device image in
`CubeFlow.app/Frameworks/TNoodleRuntime.framework`. The original XCFramework
and its binary are not modified. The framework version is the packaging
revision, not a claim about the TNoodle or Graal version.

Only the copied Mach-O identity and obsolete ad-hoc signature are adjusted.
The Graal native image, algorithms, exports and loaded section bytes must
remain unchanged. Device builds sign the framework with Xcode's configured
identity when signing is enabled; unsigned verification does not sign it.
Simulator builds retain the existing unavailable-native-runtime behavior.

## Open Privacy Gate

No SDK PrivacyInfo.xcprivacy is supplied here because the purposes of the
Graal required-reason API calls have not been established. Do not copy the
app manifest here or insert empty/speculative API declarations.

After a verified runtime/vendor audit, place the accurately approved SDK
manifest at `Config/TNoodleRuntime/PrivacyInfo.xcprivacy`. The packaging
script validates its plist and embeds it at the framework root before
signing. Plist validity is not privacy-compliance approval.

Before distribution, complete that audit, SDK licensing/provenance review,
signed physical runtime validation and Apple-side archive validation.
