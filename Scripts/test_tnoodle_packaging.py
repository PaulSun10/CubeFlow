"""Exercise the real packager without signing or executing the device image."""
import hashlib
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Vendor/TNoodleLibNative.xcframework/ios-arm64/lib-scrambles.dylib"
SCRIPT = ROOT / "Scripts/package-tnoodle-framework.sh"


def sections(binary):
    data = binary.read_bytes()
    header = struct.unpack_from("<8I", data)
    assert header[0] == 0xFEEDFACF and header[3] == 6
    offset, result = 32, {}
    for _ in range(header[4]):
        command, size = struct.unpack_from("<II", data, offset)
        if command == 0x19:
            segment = struct.unpack_from("<II16sQQQQiiII", data, offset)
            for i in range(segment[9]):
                section = struct.unpack_from("<16s16sQQIIIIIIII", data, offset + 72 + i * 80)
                name, owner, address, length, start = section[:5]
                if start:
                    assert start + length <= len(data)
                    result[(owner, name)] = (address, length, hashlib.sha256(data[start:start + length]).hexdigest())
        elif command in (0x25, 0x32):
            result["platform"] = data[offset:offset + size]
        offset += size
    return result


class TNoodlePackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="CubeFlow framework test ")
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name) / "Build Output"
        self.output.mkdir()
        self.env = dict(os.environ, PROJECT_DIR=str(ROOT), TARGET_BUILD_DIR=str(self.output),
                        WRAPPER_NAME="CubeFlow.app", FRAMEWORKS_FOLDER_PATH="CubeFlow.app/Frameworks",
                        PLATFORM_NAME="iphoneos", CODE_SIGNING_ALLOWED="NO")
        self.framework = self.output / "CubeFlow.app/Frameworks/TNoodleRuntime.framework"
        self.binary = self.framework / "TNoodleRuntime"
        self.original_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()

    def package(self, **changes):
        return subprocess.run(["/bin/sh", str(SCRIPT)], env=dict(self.env, **changes),
                              text=True, capture_output=True)

    def test_debug_and_release_preserve_native_sections_abi_and_vendor(self):
        original_sections = sections(SOURCE)
        original_exports = subprocess.check_output(["xcrun", "nm", "-gU", str(SOURCE)])
        original_dependencies = subprocess.check_output(["xcrun", "otool", "-L", str(SOURCE)]).splitlines()[2:]
        for configuration in ("Debug", "Release"):
            with self.subTest(configuration=configuration):
                result = self.package(CONFIGURATION=configuration)
                self.assertEqual(result.returncode, 0, result.stderr)
                metadata = plistlib.loads((self.framework / "Info.plist").read_bytes())
                self.assertEqual(metadata["CFBundleExecutable"], self.binary.name)
                self.assertEqual(metadata["CFBundlePackageType"], "FMWK")
                self.assertEqual(metadata["MinimumOSVersion"], "15.0")
                self.assertEqual(metadata["CFBundleSupportedPlatforms"], ["iPhoneOS"])
                self.assertEqual(subprocess.check_output(["xcrun", "otool", "-D", str(self.binary)]).splitlines()[-1],
                                 b"@rpath/TNoodleRuntime.framework/TNoodleRuntime")
                self.assertEqual(subprocess.check_output(["xcrun", "lipo", "-archs", str(self.binary)]).strip(), b"arm64")
                self.assertEqual(sections(self.binary), original_sections)
                self.assertEqual(subprocess.check_output(["xcrun", "nm", "-gU", str(self.binary)]), original_exports)
                self.assertEqual(subprocess.check_output(["xcrun", "otool", "-L", str(self.binary)]).splitlines()[2:], original_dependencies)
                self.assertEqual(hashlib.sha256(SOURCE.read_bytes()).hexdigest(), self.original_hash)
                self.assertNotEqual(subprocess.run(["codesign", "-d", str(self.framework)], capture_output=True).returncode, 0)
                self.assertFalse((self.framework / "PrivacyInfo.xcprivacy").exists(), "Do not invent a vendor manifest")

    def test_repeated_packaging_removes_only_obsolete_app_copies(self):
        app = self.output / "CubeFlow.app"
        (app / "Frameworks").mkdir(parents=True)
        for file in (app / "lib-scrambles.dylib", app / "Frameworks/lib-scrambles.dylib", app / "unrelated.txt"):
            file.write_text("fixture")
        for _ in range(2):
            result = self.package()
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((app / "lib-scrambles.dylib").exists())
        self.assertFalse((app / "Frameworks/lib-scrambles.dylib").exists())
        self.assertEqual((app / "unrelated.txt").read_text(), "fixture")
        self.assertEqual(len(list(app.rglob("TNoodleRuntime"))), 1)

    def test_simulator_does_not_embed_device_image(self):
        result = self.package(PLATFORM_NAME="iphonesimulator")
        self.assertEqual(result.returncode, 0)
        self.assertFalse(self.framework.exists())

    def test_missing_vendor_image_fails_without_substituting_generator(self):
        result = self.package(PROJECT_DIR=self.temporary.name)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing TNoodle device runtime", result.stderr)
        self.assertFalse(self.framework.exists())

    def test_signing_enabled_requires_configured_identity_without_signing_here(self):
        result = self.package(CODE_SIGNING_ALLOWED="YES", EXPANDED_CODE_SIGN_IDENTITY="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("signing identity is missing", result.stderr)

    def test_refuses_output_framework_symlink(self):
        self.framework.parent.mkdir(parents=True)
        protected = Path(self.temporary.name) / "protected"
        protected.mkdir()
        (protected / "sentinel").write_text("keep")
        self.framework.symlink_to(protected, target_is_directory=True)
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((protected / "sentinel").read_text(), "keep")


if __name__ == "__main__":
    unittest.main(verbosity=2)
