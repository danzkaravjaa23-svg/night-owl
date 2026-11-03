#!/usr/bin/env python3
"""Read-only source/toolchain checks, not App Store submission approval."""

import argparse
import json
from pathlib import Path
import platform
import plistlib
import re
import struct
import subprocess
import sys
from xml.parsers.expat import ExpatError
import zlib


ROOT = Path(__file__).resolve().parents[2]
FLUTTER_VERSION = "3.44.0"
BUNDLE_ID = "com.nightowl.ub.nightOwlUb"
MINIMUM_IOS_DEPLOYMENT_TARGET = (13, 0)


def png_dimensions(path, *, opaque_marketing=False):
    """Read dimensions after complete chunk/CRC checks; no image decoder."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    offset = 8
    dimensions = None
    pixels = False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        end = offset + length + 12
        if end > len(data):
            return None
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:end - 4]
        crc = struct.unpack(">I", data[end - 4:end])[0]
        if zlib.crc32(kind + payload) != crc or (opaque_marketing and kind == b"tRNS"):
            return None
        if kind == b"IHDR":
            if dimensions or offset != 8 or length != 13:
                return None
            width, height, depth, color, _, _, _ = struct.unpack(">IIBBBBB", payload)
            if not width or not height:
                return None
            if opaque_marketing and (width, height, depth, color) != (1024, 1024, 8, 2):
                return None
            dimensions = (width, height)
        if kind == b"IEND":
            return dimensions if pixels and length == 0 and end == len(data) else None
        if kind == b"IDAT" and length:
            pixels = True
        offset = end
    return None


def opaque_marketing_png(path):
    return png_dimensions(path, opaque_marketing=True) == (1024, 1024)


def source_checks(root):
    results = []

    def check(name, action):
        try:
            ok = bool(action())
        except (OSError, ValueError, TypeError, KeyError, AttributeError,
                plistlib.InvalidFileException, ExpatError, struct.error):
            ok = False
        results.append((name, ok))

    def plist(name):
        with (root / "ios/Runner" / name).open("rb") as source:
            return plistlib.load(source)

    def permissions():
        info = plist("Info.plist")
        for key in ("NSCameraUsageDescription", "NSPhotoLibraryUsageDescription",
                    "NSLocationWhenInUseUsageDescription"):
            value = info.get(key)
            if not isinstance(value, str) or not value.strip():
                return False
            if "шууд дамжуул" in value.lower():
                return False
        return True

    def transport():
        ats = plist("Info.plist").get("NSAppTransportSecurity", {})
        return not any(ats.get(key) for key in (
            "NSAllowsArbitraryLoads", "NSAllowsArbitraryLoadsInWebContent",
            "NSAllowsArbitraryLoadsForMedia")) and not ats.get("NSExceptionDomains")

    def callback():
        info = plist("Info.plist")
        schemes = [scheme for item in info.get("CFBundleURLTypes", [])
                   for scheme in item.get("CFBundleURLSchemes", [])]
        return "com.nightowl.ub" in schemes and info.get("FlutterDeepLinkingEnabled") is False

    def project_text():
        return (root / "ios/Runner.xcodeproj/project.pbxproj").read_text()

    def runner_configurations():
        # Build-configuration objects have nested buildSettings dictionaries.
        # Match their outer indentation, then restrict checks to Runner's plist.
        blocks = re.findall(r"^\t\t[0-9A-F]{24} /\*[^\n]*\*/ = \{(.*?)^\t\t\};",
                            project_text(), re.MULTILINE | re.DOTALL)
        runner = [block for block in blocks if "isa = XCBuildConfiguration;" in block
                  and re.search(r'INFOPLIST_FILE = "?Runner/Info\.plist"?;', block)]
        if len(runner) != 3:
            return False
        names = []
        for block in runner:
            name = re.search(r"^\t\t\tname = (\w+);", block, re.MULTILINE)
            if not name or not re.search(
                    rf'PRODUCT_BUNDLE_IDENTIFIER = "?{re.escape(BUNDLE_ID)}"?;', block):
                return False
            if not re.search(r'CODE_SIGN_ENTITLEMENTS = "?Runner/Runner\.entitlements"?;', block):
                return False
            names.append(name[1])
        return set(names) == {"Debug", "Profile", "Release"}

    def minimum_deployment_target():
        # Runner currently inherits its deployment target from PBXProject.
        # Resolve the configuration lists, rather than accepting one matching
        # 13.0 string elsewhere or rejecting a valid target-level override.
        text = project_text()
        objects = dict(re.findall(
            r"^\t\t([0-9A-F]{24}) /\*[^\n]*\*/ = \{(.*?)^\t\t\};",
            text, re.MULTILINE | re.DOTALL))

        def configurations(owner):
            owners = [block for block in objects.values()
                      if f"isa = {owner};" in block
                      and (owner == "PBXProject" or re.search(
                          r'^\t\t\tname = Runner;', block, re.MULTILINE))]
            if len(owners) != 1:
                return {}
            ref = re.search(r'buildConfigurationList = ([0-9A-F]{24})\b', owners[0])
            config_list = objects.get(ref[1], "") if ref else ""
            if "isa = XCConfigurationList;" not in config_list:
                return {}
            members = re.search(r'buildConfigurations = \((.*?)\);',
                                config_list, re.DOTALL)
            if not members:
                return {}
            result = {}
            for ref in re.findall(r'([0-9A-F]{24}) /\*', members[1]):
                block = objects.get(ref, "")
                name = re.search(r'^\t\t\tname = (\w+);', block, re.MULTILINE)
                if not name or name[1] in result or "isa = XCBuildConfiguration;" not in block:
                    return {}
                if owner == "PBXNativeTarget" and not re.search(
                        r'INFOPLIST_FILE = "?Runner/Info\.plist"?;', block):
                    return {}
                result[name[1]] = block
            return result

        project = configurations("PBXProject")
        runner = configurations("PBXNativeTarget")
        if set(project) != {"Debug", "Profile", "Release"} or set(runner) != set(project):
            return False

        def targets(block):
            return dict(re.findall(
                r'^\s*"?IPHONEOS_DEPLOYMENT_TARGET((?:\[[^\]\n]+\])*)"?\s*=\s*"?([^";\n]+)"?;',
                block, re.MULTILINE))

        for name in runner:
            target_settings = targets(runner[name])
            project_settings = targets(project[name])
            if '' in target_settings:
                effective = target_settings
            else:
                effective = {**project_settings, **target_settings}
            if '' not in effective:
                return False
            for raw in effective.values():
                value = raw.strip()
                if not re.fullmatch(r'\d+(?:\.\d+){0,2}', value):
                    return False
                version = tuple(int(part) for part in value.split('.'))
                if (version + (0, 0))[:2] < MINIMUM_IOS_DEPLOYMENT_TARGET:
                    return False
        return True

    def privacy_reasons():
        entries = plist("PrivacyInfo.xcprivacy").get("NSPrivacyAccessedAPITypes")
        if not isinstance(entries, list):
            return False
        reasons = {entry["NSPrivacyAccessedAPIType"]: entry["NSPrivacyAccessedAPITypeReasons"]
                   for entry in entries}
        return len(reasons) == len(entries) and reasons == {
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
        }

    def privacy_resource():
        project = project_text()
        file_ref = re.search(
            r"^\t\t([0-9A-F]{24}) /\* PrivacyInfo\.xcprivacy \*/ = "
            r"\{isa = PBXFileReference;[^\n]*path = PrivacyInfo\.xcprivacy;", project,
            re.MULTILINE)
        if not file_ref:
            return False
        build_ref = re.search(
            r"^\t\t([0-9A-F]{24}) /\* PrivacyInfo\.xcprivacy in Resources \*/ = "
            rf"\{{isa = PBXBuildFile; fileRef = {file_ref[1]} ", project, re.MULTILINE)
        if not build_ref:
            return False
        runner = re.search(
            r"^\t\t[0-9A-F]{24} /\* Runner \*/ = \{\n\t\t\tisa = PBXNativeTarget;"
            r"(.*?)^\t\t\};", project, re.MULTILINE | re.DOTALL)
        if not runner:
            return False
        resource = re.search(r"([0-9A-F]{24}) /\* Resources \*/", runner[1])
        if not resource:
            return False
        phase = re.search(
            rf"^\t\t{resource[1]} /\* Resources \*/ = \{{(.*?)^\t\t\}};",
            project, re.MULTILINE | re.DOTALL)
        return bool(phase and re.search(rf"\b{build_ref[1]}\b", phase[1]))

    def icons():
        directory = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
        catalog = json.loads((directory / "Contents.json").read_text())
        images = catalog["images"]
        for entry in images:
            path = (directory / entry["filename"]).resolve()
            if path.parent != directory.resolve() or not path.is_file():
                return False
            size, scale = entry["size"], entry["scale"]
            if (not re.fullmatch(r"\d+(?:\.\d+)?x\d+(?:\.\d+)?", size)
                    or not re.fullmatch(r"[1-3]x", scale)):
                return False
            expected = tuple(float(value) * int(scale[0]) for value in size.split("x"))
            if any(value <= 0 or not value.is_integer() for value in expected):
                return False
            if png_dimensions(path) != tuple(int(value) for value in expected):
                return False
        marketing = [entry for entry in images if entry.get("idiom") == "ios-marketing"
                     and entry.get("size") == "1024x1024" and entry.get("scale") == "1x"]
        return len(marketing) == 1 and opaque_marketing_png(directory / marketing[0]["filename"])

    check("Permission purpose strings", permissions)
    check("HTTPS protection (no ATS exceptions)", transport)
    check("Native auth callback", callback)
    check("Apple entitlement (not provisioning proof)",
          lambda: plist("Runner.entitlements").get("com.apple.developer.applesignin") == ["Default"])
    check("Runner bundle ID / entitlement in all configurations", runner_configurations)
    check("Runner minimum deployment target iOS 13+", minimum_deployment_target)
    check("App required-reason privacy API declarations", privacy_reasons)
    check("Privacy manifest in Runner resources", privacy_resource)
    check("App icon catalog / opaque 1024px PNG", icons)
    return results


def command_output(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=60, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def toolchain_checks(run=command_output, system=None):
    if (system or platform.system()) != "Darwin":
        return [("macOS host", False)]
    results = []
    xcode = run(["xcodebuild", "-version"])
    version = re.search(r"^Xcode (\d+)(?:\.\d+)*$", xcode or "", re.MULTILINE)
    supported = bool(version and int(version[1]) >= 26 and not re.search(r"beta|RC", xcode, re.I))
    results.append(("Full Xcode 26+", supported))
    if supported:
        sdk = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"])
        results.append(("iPhoneOS SDK 26+", bool(
            sdk and re.fullmatch(r"\d+(?:\.\d+)*", sdk) and int(sdk.split(".")[0]) >= 26)))
        results.append(("Xcode license / first launch (check only)",
                        run(["xcodebuild", "-checkFirstLaunchStatus"]) is not None))
    pod = run(["pod", "--version"])
    results.append(("CocoaPods", bool(pod and re.fullmatch(r"\d+(?:\.\d+)+", pod))))
    try:
        flutter = json.loads(run(["flutter", "--version", "--machine"]) or "null")
        pinned = isinstance(flutter, dict) and flutter.get("frameworkVersion") == FLUTTER_VERSION
    except (ValueError, TypeError):
        pinned = False
    results.append((f"Flutter {FLUTTER_VERSION}", pinned))
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true", help="Skip local toolchain checks")
    args = parser.parse_args(argv)
    results = source_checks(ROOT)
    if not args.source_only:
        results += toolchain_checks()
    for name, ok in results:
        print(f"{'PASS' if ok else 'BLOCK'}: {name}")
    print("Scope: source" + (" only" if args.source_only else " + local toolchain"))
    print("Not verified: native compile, signing, device tests, backend deletion, privacy declarations, store review.")
    return 0 if all(ok for _, ok in results) else 1


if __name__ == "__main__":
    sys.exit(main())
