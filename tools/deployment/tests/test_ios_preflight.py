import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zlib


SCRIPT = Path(__file__).resolve().parents[1] / "ios_preflight.py"
spec = importlib.util.spec_from_file_location("ios_preflight", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copytree(module.ROOT / "ios/Runner", self.root / "ios/Runner")
        shutil.copytree(module.ROOT / "ios/Runner.xcodeproj", self.root / "ios/Runner.xcodeproj")

    def edit_info(self, change):
        path = self.root / "ios/Runner/Info.plist"
        info = plistlib.loads(path.read_bytes())
        change(info)
        path.write_bytes(plistlib.dumps(info))

    def checks(self):
        return dict(module.source_checks(self.root))

    def test_real_source_passes_without_changes(self):
        before = {str(path): path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        self.assertTrue(all(self.checks().values()))
        after = {str(path): path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        self.assertEqual(before, after)

    def test_missing_or_blank_purpose_is_blocked(self):
        self.edit_info(lambda info: info.update(NSCameraUsageDescription=" "))
        self.assertFalse(self.checks()["Permission purpose strings"])

    def test_nonexistent_live_feature_is_not_promised(self):
        self.edit_info(lambda info: info.update(NSCameraUsageDescription="Шууд дамжуулалт"))
        self.assertFalse(self.checks()["Permission purpose strings"])

    def test_http_exceptions_are_not_silently_allowed(self):
        for value in ({"NSAllowsArbitraryLoads": True},
                      {"NSAllowsArbitraryLoadsForMedia": True},
                      {"NSExceptionDomains": {"example.test": {}}}):
            with self.subTest(value=value):
                self.edit_info(lambda info: info.update(NSAppTransportSecurity=value))
                self.assertFalse(self.checks()["HTTPS protection (no ATS exceptions)"])

    def test_callback_requires_scheme_and_disabled_flutter_handler(self):
        self.edit_info(lambda info: info.update(FlutterDeepLinkingEnabled=True))
        self.assertFalse(self.checks()["Native auth callback"])
        self.edit_info(lambda info: info.update(FlutterDeepLinkingEnabled=False, CFBundleURLTypes=[]))
        self.assertFalse(self.checks()["Native auth callback"])

    def test_missing_apple_entitlement_is_blocked(self):
        (self.root / "ios/Runner/Runner.entitlements").write_bytes(plistlib.dumps({}))
        self.assertFalse(self.checks()["Apple entitlement (not provisioning proof)"])

    def test_release_bundle_or_entitlement_drift_is_blocked(self):
        path = self.root / "ios/Runner.xcodeproj/project.pbxproj"
        original = path.read_text()
        for old, new in (
                (f"PRODUCT_BUNDLE_IDENTIFIER = {module.BUNDLE_ID};",
                 "PRODUCT_BUNDLE_IDENTIFIER = com.example.wrong;"),
                ("CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;", "")):
            with self.subTest(changed=old):
                path.write_text(original.replace(old, new, 1))
                self.assertFalse(self.checks()["Runner bundle ID / entitlement in all configurations"])

    def test_deployment_target_rejects_old_missing_and_unresolved_values(self):
        path = self.root / "ios/Runner.xcodeproj/project.pbxproj"
        original = path.read_text()
        for value in ("12.0", "$(CUSTOM_IOS_VERSION)", "invalid"):
            with self.subTest(value=value):
                path.write_text(original.replace("IPHONEOS_DEPLOYMENT_TARGET = 13.0;",
                                                 f"IPHONEOS_DEPLOYMENT_TARGET = {value};", 1))
                self.assertFalse(self.checks()["Runner minimum deployment target iOS 13+"])
        path.write_text(original.replace("IPHONEOS_DEPLOYMENT_TARGET = 13.0;", ""))
        self.assertFalse(self.checks()["Runner minimum deployment target iOS 13+"])

    def test_target_override_can_raise_inherited_old_project_version(self):
        path = self.root / "ios/Runner.xcodeproj/project.pbxproj"
        source = path.read_text().replace("IPHONEOS_DEPLOYMENT_TARGET = 13.0;",
                                         "IPHONEOS_DEPLOYMENT_TARGET = 12.0;")
        source = source.replace("INFOPLIST_FILE = Runner/Info.plist;",
                                "INFOPLIST_FILE = Runner/Info.plist;\n"
                                "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.0;")
        path.write_text(source)
        self.assertTrue(self.checks()["Runner minimum deployment target iOS 13+"])

    def test_target_override_cannot_lower_one_configuration(self):
        path = self.root / "ios/Runner.xcodeproj/project.pbxproj"
        source = path.read_text().replace("INFOPLIST_FILE = Runner/Info.plist;",
                                         "INFOPLIST_FILE = Runner/Info.plist;\n"
                                         "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 12.0;", 1)
        path.write_text(source)
        self.assertFalse(self.checks()["Runner minimum deployment target iOS 13+"])

    def test_runner_configuration_reference_cannot_point_to_tests_or_missing_list(self):
        path = self.root / "ios/Runner.xcodeproj/project.pbxproj"
        original = path.read_text()
        for target in ("331C8087294A63A400263BE5", "000000000000000000000000"):
            with self.subTest(target=target):
                path.write_text(original.replace(
                    "buildConfigurationList = 97C147051CF9000F007C117D",
                    "buildConfigurationList = " + target, 1))
                self.assertFalse(self.checks()["Runner minimum deployment target iOS 13+"])

    def test_conditional_old_deployment_target_is_blocked(self):
        path = self.root / "ios/Runner.xcodeproj/project.pbxproj"
        source = path.read_text().replace("INFOPLIST_FILE = Runner/Info.plist;",
                                         "INFOPLIST_FILE = Runner/Info.plist;\n"
                                         '\t\t\t\t"IPHONEOS_DEPLOYMENT_TARGET[sdk=iphoneos*]" = 12.0;', 1)
        path.write_text(source)
        self.assertFalse(self.checks()["Runner minimum deployment target iOS 13+"])

    def test_combined_sdk_arch_conditions_cannot_hide_old_or_unknown_target(self):
        path = self.root / "ios/Runner.xcodeproj/project.pbxproj"
        original = path.read_text()
        for value in ("12.0", '"$(UNRESOLVED_TARGET)"'):
            with self.subTest(value=value):
                source = original.replace(
                    "INFOPLIST_FILE = Runner/Info.plist;",
                    "INFOPLIST_FILE = Runner/Info.plist;\n"
                    '\t\t\t\t"IPHONEOS_DEPLOYMENT_TARGET[sdk=iphoneos*][arch=arm64]" = '
                    + value + ";", 1)
                path.write_text(source)
                self.assertFalse(self.checks()["Runner minimum deployment target iOS 13+"])

    def test_icon_with_valid_png_but_wrong_catalog_dimensions_is_blocked(self):
        directory = self.root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
        path = directory / "Contents.json"
        data = json.loads(path.read_text())
        # The referenced image exists and is a valid opaque PNG, but is not
        # the dimensions advertised by this catalog entry.
        data["images"][0]["filename"] = "Icon-App-1024x1024@1x.png"
        path.write_text(json.dumps(data))
        self.assertFalse(self.checks()["App icon catalog / opaque 1024px PNG"])

    def test_non_marketing_icon_requires_complete_crc_checked_png(self):
        directory = self.root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
        catalog = json.loads((directory / "Contents.json").read_text())
        entry = next(item for item in catalog["images"] if item["idiom"] != "ios-marketing")
        path = directory / entry["filename"]
        original = path.read_bytes()
        damaged = bytearray(original)
        damaged[-5] ^= 1
        for data in (original[:33], original[:-12], bytes(damaged), original + b"trailing"):
            with self.subTest(length=len(data)):
                path.write_bytes(data)
                self.assertFalse(self.checks()["App icon catalog / opaque 1024px PNG"])

    def test_invalid_icon_size_and_scale_are_reported_without_raising(self):
        path = self.root / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"
        original = path.read_text()
        for field, value in (("size", None), ("size", "bad"), ("size", "0x0"),
                             ("size", "20.2x20.2"), ("scale", "4x")):
            with self.subTest(field=field, value=value):
                data = json.loads(original)
                data["images"][0][field] = value
                path.write_text(json.dumps(data))
                self.assertFalse(self.checks()["App icon catalog / opaque 1024px PNG"])

    def test_required_api_manifest_missing_or_unsupported_reason_is_blocked(self):
        path = self.root / "ios/Runner/PrivacyInfo.xcprivacy"
        original = plistlib.loads(path.read_bytes())
        for value in ({}, {"NSPrivacyAccessedAPITypes": []},
                      {"NSPrivacyAccessedAPITypes": "invalid"},
                      {"NSPrivacyAccessedAPITypes": ["invalid"]}):
            path.write_bytes(plistlib.dumps(value))
            self.assertFalse(self.checks()["App required-reason privacy API declarations"])
        original["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"] = ["DDA9.1"]
        path.write_bytes(plistlib.dumps(original))
        self.assertFalse(self.checks()["App required-reason privacy API declarations"])
        path.unlink()
        self.assertFalse(self.checks()["App required-reason privacy API declarations"])

    def test_manifest_only_on_disk_is_not_treated_as_bundled(self):
        path = self.root / "ios/Runner.xcodeproj/project.pbxproj"
        source = path.read_text()
        # Remove just the Runner Copy Bundle Resources entry, preserving the
        # file reference, build-file object and on-disk manifest.
        source = source.replace(
            "\t\t\t\tC02F9C162FABC00100000001 /* PrivacyInfo.xcprivacy in Resources */,\n", "")
        path.write_text(source)
        self.assertTrue(self.checks()["App required-reason privacy API declarations"])
        self.assertFalse(self.checks()["Privacy manifest in Runner resources"])

    def test_missing_and_malformed_plist_are_reported_not_raised(self):
        path = self.root / "ios/Runner/Info.plist"
        for value in (b"broken plist", b'<?xml version="1.0"?><plist><dict>'):
            path.write_bytes(value)
            self.assertFalse(all(self.checks().values()))
        path.unlink()
        self.assertFalse(all(self.checks().values()))

    def test_icon_transparency_corruption_and_truncation_are_blocked(self):
        path = self.root / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
        original = path.read_bytes()
        for data in (original[:25], b"not a png", original + b"trailing"):
            with self.subTest(length=len(data)):
                path.write_bytes(data)
                self.assertFalse(self.checks()["App icon catalog / opaque 1024px PNG"])
        kind = b"tRNS"
        payload = b"\0" * 6
        transparency = struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
        path.write_bytes(original[:33] + transparency + original[33:])
        self.assertFalse(self.checks()["App icon catalog / opaque 1024px PNG"])

    def test_missing_icon_reference_and_catalog_path_escape_are_blocked(self):
        path = self.root / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"
        data = json.loads(path.read_text())
        for filename in ("missing.png", "../outside.png"):
            data["images"][0]["filename"] = filename
            path.write_text(json.dumps(data))
            self.assertFalse(self.checks()["App icon catalog / opaque 1024px PNG"])


class ToolchainTests(unittest.TestCase):
    def checks(self, overrides=None):
        answers = {
            ("xcodebuild", "-version"): "Xcode 26.3\nBuild version 17C123",
            ("xcrun", "--sdk", "iphoneos", "--show-sdk-version"): "26.2",
            ("xcodebuild", "-checkFirstLaunchStatus"): "",
            ("pod", "--version"): "1.17.0",
            ("flutter", "--version", "--machine"): json.dumps({"frameworkVersion": "3.44.0"}),
        }
        answers.update(overrides or {})
        calls = []

        def run(command):
            calls.append(command)
            return answers[tuple(command)]

        results = dict(module.toolchain_checks(run=run, system="Darwin"))
        self.assertFalse(any("sudo" in call or "-license" in call or "-runFirstLaunch" in call for call in calls))
        return results

    def test_supported_toolchain_and_check_only_first_launch_pass(self):
        self.assertTrue(all(self.checks().values()))

    def test_command_line_tools_old_and_explicit_prerelease_xcode_are_blocked(self):
        for response in (None, "", "Xcode 16.4\nBuild version 16F6", "Xcode 27 beta 2"):
            with self.subTest(response=response):
                results = self.checks({("xcodebuild", "-version"): response})
                self.assertFalse(results["Full Xcode 26+"])
                self.assertNotIn("iPhoneOS SDK 26+", results)

    def test_old_missing_or_malformed_sdk_is_blocked(self):
        for sdk in (None, "18.5", "26oops"):
            self.assertFalse(self.checks({("xcrun", "--sdk", "iphoneos", "--show-sdk-version"): sdk})["iPhoneOS SDK 26+"])

    def test_license_or_components_missing_is_blocked_without_accepting(self):
        results = self.checks({("xcodebuild", "-checkFirstLaunchStatus"): None})
        self.assertFalse(results["Xcode license / first launch (check only)"])

    def test_missing_pods_or_wrong_flutter_is_blocked(self):
        self.assertFalse(self.checks({("pod", "--version"): None})["CocoaPods"])
        for value in (None, "invalid", "null", "[]", '{"frameworkVersion":"3.43.0"}'):
            self.assertFalse(self.checks({("flutter", "--version", "--machine"): value})["Flutter 3.44.0"])

    def test_non_mac_host_never_probes_tools(self):
        def forbidden(_):
            self.fail("Do not execute Apple commands on non-macOS")
        self.assertEqual(module.toolchain_checks(run=forbidden, system="Linux"), [("macOS host", False)])

    def test_command_failure_timeout_and_missing_binary_are_safe(self):
        for error in (FileNotFoundError(), subprocess.TimeoutExpired("fixture", 60)):
            with patch.object(module.subprocess, "run", side_effect=error):
                self.assertIsNone(module.command_output(["fixture"]))

    def test_build_wrapper_rejects_backend_and_signing_overrides_before_tools(self):
        script = module.ROOT / "tools/deployment/build_ios.sh"
        for option in ("--dart-define=BACKEND_URL=https://example.test", "--codesign", "--debug", "--simulator"):
            result = subprocess.run(["sh", str(script), option], capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 2)
            self.assertIn("Only --no-pub is allowed", result.stderr)


if __name__ == "__main__":
    unittest.main()
