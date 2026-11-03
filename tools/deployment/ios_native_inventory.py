#!/usr/bin/env python3
"""Inventory the built app's platform and embedded SDK privacy manifests."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess


def main():
    root = Path('build/ios/iphoneos/Runner.app')
    info = plistlib.loads((root / 'Info.plist').read_bytes())
    keys = ['CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion',
            'MinimumOSVersion', 'UIDeviceFamily', 'DTXcode', 'DTXcodeBuild',
            'DTSDKName', 'DTPlatformName', 'DTPlatformVersion']
    manifests = []
    for path in sorted(root.rglob('PrivacyInfo.xcprivacy')):
        data = path.read_bytes()
        manifests.append({'path': str(path.relative_to(root)),
                          'sha256': hashlib.sha256(data).hexdigest(),
                          'manifest': plistlib.loads(data)})
    if not manifests:
        raise RuntimeError('Built app contains no privacy manifests')
    executable = root / info['CFBundleExecutable']
    result = {'scope': 'Built unsigned iPhone app; inventory only, not Apple privacy/signature approval.',
              'bundle': {key: info.get(key) for key in keys},
              'architectures': subprocess.check_output(['lipo', '-archs', str(executable)], text=True).strip(),
              'privacy_manifests': manifests}
    output = Path('build/native-evidence/iphoneos-inventory.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(f'Inventoried {len(manifests)} embedded privacy manifests; {result["architectures"]}.')


if __name__ == '__main__':
    main()
