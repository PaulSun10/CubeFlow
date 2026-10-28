#!/bin/sh
set -eu

# The simulator bridge deliberately does not load the device Graal image.
[ "${PLATFORM_NAME:-}" = iphoneos ] || exit 0

SOURCE="${PROJECT_DIR:?}/Vendor/TNoodleLibNative.xcframework/ios-arm64/lib-scrambles.dylib"
CONFIG="${PROJECT_DIR}/Config/TNoodleRuntime"
APP="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:?}"
FRAMEWORK="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH:?}/TNoodleRuntime.framework"
BINARY="${FRAMEWORK}/TNoodleRuntime"
INSTALL_NAME='@rpath/TNoodleRuntime.framework/TNoodleRuntime'

[ -f "$SOURCE" ] || { echo "error: Missing TNoodle device runtime: $SOURCE" >&2; exit 1; }
[ "$(xcrun lipo -archs "$SOURCE")" = arm64 ] || { echo 'error: TNoodle device architecture requires review.' >&2; exit 1; }
[ ! -L "$FRAMEWORK" ] || { echo 'error: Refusing a symlinked TNoodle output framework.' >&2; exit 1; }

# Only this generated product is replaced, never the vendor source or caches.
mkdir -p "$FRAMEWORK"
find "$FRAMEWORK" -depth -mindepth 1 -delete
cp "$SOURCE" "$BINARY"
chmod 755 "$BINARY"
cp "$CONFIG/Info.plist" "$FRAMEWORK/Info.plist"
/usr/bin/plutil -lint "$FRAMEWORK/Info.plist"
if /usr/bin/codesign -d "$BINARY" >/dev/null 2>&1; then
    /usr/bin/codesign --remove-signature "$BINARY"
fi
xcrun install_name_tool -id "$INSTALL_NAME" "$BINARY"
[ "$(xcrun otool -D "$BINARY" | tail -n 1)" = "$INSTALL_NAME" ] || exit 1

if [ -f "$CONFIG/PrivacyInfo.xcprivacy" ]; then
    /usr/bin/plutil -lint "$CONFIG/PrivacyInfo.xcprivacy"
    # Syntax and known reason codes are not evidence that the purposes match.
    /usr/bin/python3 - "$CONFIG/PrivacyInfo.xcprivacy" <<'PY'
import plistlib
import sys

reasons = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1", "8FFB.1", "3D61.1"},
}

def require(condition, message):
    if not condition:
        sys.exit("error: TNoodle privacy manifest: " + message)

with open(sys.argv[1], "rb") as source:
    manifest = plistlib.load(source)
require(type(manifest) is dict, "root must be a dictionary")
require(set(manifest) <= {
    "NSPrivacyTracking", "NSPrivacyTrackingDomains",
    "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes",
}, "unexpected root keys")
if "NSPrivacyTracking" in manifest:
    require(type(manifest["NSPrivacyTracking"]) is bool, "tracking must be a boolean")
if "NSPrivacyTrackingDomains" in manifest:
    domains = manifest["NSPrivacyTrackingDomains"]
    require(type(domains) is list and all(type(domain) is str and domain for domain in domains),
            "tracking domains must be an array of nonempty strings")
    require(not domains or manifest.get("NSPrivacyTracking") is True,
            "tracking domains require tracking=true")
if "NSPrivacyCollectedDataTypes" in manifest:
    # No SDK collection schema/purpose has been reviewed in this integration.
    require(manifest["NSPrivacyCollectedDataTypes"] == [],
            "nonempty collection declarations require a separate reviewed validator")
entries = manifest.get("NSPrivacyAccessedAPITypes")
require(type(entries) is list and bool(entries), "required-reason entries must be a nonempty array")
seen = set()
for entry in entries:
    require(type(entry) is dict and set(entry) == {
        "NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons",
    }, "each API entry must contain only category and reasons")
    category = entry["NSPrivacyAccessedAPIType"]
    require(type(category) is str and category in reasons, "unreviewed API category")
    require(category not in seen, "duplicate API category")
    seen.add(category)
    codes = entry["NSPrivacyAccessedAPITypeReasons"]
    require(type(codes) is list and bool(codes)
            and all(type(code) is str and code in reasons[category] for code in codes),
            "empty or unrecognized reasons for " + category)
    require(len(set(codes)) == len(codes), "duplicate reason codes")
require(seen == set(reasons), "known native API categories are missing; exemptions require review")
print("note: TNoodle manifest structure checked; API purposes are NOT approved by this check.")
PY
    cp "$CONFIG/PrivacyInfo.xcprivacy" "$FRAMEWORK/PrivacyInfo.xcprivacy"
fi

# Keep this gate even when a structurally valid manifest is supplied. The current
# native purposes have no established approved reasons; file presence cannot clear it.
echo 'warning: TNoodle privacy review unresolved: stat/fstat/lstat (system timezone/file metadata), fstatvfs (Direct I/O alignment), mach_absolute_time (runtime clock/possible random seeding).'
echo 'warning: TNoodle External TestFlight privacy clearance remains pending; see docs/tnoodle-privacy-assessment-oct23.md. This is a CubeFlow evidence gate, not an Apple validation result.'

# Remove only obsolete copies in the generated app during incremental migration.
for legacy in "$APP/lib-scrambles.dylib" "$APP/Frameworks/lib-scrambles.dylib"; do
    if [ -f "$legacy" ]; then /bin/unlink "$legacy"; fi
done

if [ "${CODE_SIGNING_ALLOWED:-NO}" != NO ]; then
    [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] || { echo 'error: TNoodle framework signing identity is missing.' >&2; exit 1; }
    /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$FRAMEWORK"
    /usr/bin/codesign --verify --strict "$FRAMEWORK"
fi
