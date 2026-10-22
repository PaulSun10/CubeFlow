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
    cp "$CONFIG/PrivacyInfo.xcprivacy" "$FRAMEWORK/PrivacyInfo.xcprivacy"
else
    echo 'warning: TNoodle SDK privacy purposes/manifest remain unverified; distribution is not cleared.'
fi

# Remove only obsolete copies in the generated app during incremental migration.
for legacy in "$APP/lib-scrambles.dylib" "$APP/Frameworks/lib-scrambles.dylib"; do
    if [ -f "$legacy" ]; then /bin/unlink "$legacy"; fi
done

if [ "${CODE_SIGNING_ALLOWED:-NO}" != NO ]; then
    [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] || { echo 'error: TNoodle framework signing identity is missing.' >&2; exit 1; }
    /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$FRAMEWORK"
    /usr/bin/codesign --verify --strict "$FRAMEWORK"
fi
