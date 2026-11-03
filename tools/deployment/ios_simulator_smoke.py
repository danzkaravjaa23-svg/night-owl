#!/usr/bin/env python3
"""Launch the actual simulator build and retain startup evidence (not Store art)."""
import json
from pathlib import Path
import re
import subprocess
import time


def run(*args, timeout=180):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT,
                                   timeout=timeout).strip()


def main():
    app = Path('build/ios/iphonesimulator/Runner.app').resolve()
    output = Path('build/native-evidence/startup')
    output.mkdir(parents=True, exist_ok=True)
    bundle = run('/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleIdentifier',
                 str(app / 'Info.plist'))
    inventory = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '-j'))
    devices = [d for runtime, values in inventory['devices'].items()
               if '.iOS-' in runtime for d in values if d.get('isAvailable')]
    selected = []
    for family, preferred in [('iPhone', ['iPhone 17', 'iPhone 16', 'iPhone 16 Pro']),
                              ('iPad', ['iPad Pro 13-inch (M5)', 'iPad Pro 13-inch (M4)'])]:
        candidates = [d for d in devices if d['name'].startswith(family)]
        if not candidates:
            raise RuntimeError(f'No available {family} simulator')
        device = next((d for name in preferred for d in candidates if d['name'] == name), candidates[0])
        selected.append((family, device))
    evidence = {'bundle': bundle, 'purpose': 'Native startup only; not an authenticated feature test or App Store screenshots.', 'devices': []}
    for family, device in selected:
        udid = device['udid']
        started_here = device['state'] != 'Booted'
        try:
            if started_here:
                run('xcrun', 'simctl', 'boot', udid)
            run('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=300)
            run('xcrun', 'simctl', 'status_bar', udid, 'override', '--time', '9:41',
                '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3',
                '--batteryState', 'charged', '--batteryLevel', '100')
            run('xcrun', 'simctl', 'install', udid, str(app))
            launch = run('xcrun', 'simctl', 'launch', '--terminate-running-process', udid, bundle)
            match = re.search(r':\s*(\d+)\s*$', launch)
            if not match:
                raise RuntimeError(f'No application PID returned: {launch}')
            time.sleep(12)
            processes = run('xcrun', 'simctl', 'spawn', udid, 'launchctl', 'list')
            alive = any(line.split() and line.split()[0] == match[1] and bundle in line
                        for line in processes.splitlines())
            if not alive:
                raise RuntimeError(f'{family} app exited during startup')
            run('xcrun', 'simctl', 'io', udid, 'screenshot', str(output / f'{family.lower()}-startup.png'))
            evidence['devices'].append({'name': device['name'], 'udid': udid,
                                        'launch': launch, 'alive_after_seconds': 12})
            (output / 'result.json').write_text(json.dumps(evidence, indent=2) + '\n')
        finally:
            if started_here:
                run('xcrun', 'simctl', 'shutdown', udid)
    print(json.dumps(evidence, indent=2))


if __name__ == '__main__':
    main()
