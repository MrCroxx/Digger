#!/usr/bin/env python3
"""Validate and launch a relocated app without preferences, permissions, or API calls."""
import os
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path


def verify_app(app):
    with tempfile.TemporaryDirectory(prefix='digger moved app ') as temporary:
        moved = Path(temporary) / app.name
        subprocess.run(['/usr/bin/ditto', str(app), str(moved)], check=True)
        with (moved / 'Contents/Info.plist').open('rb') as file:
            info = plistlib.load(file)
        resources = moved / 'Contents/Resources'
        icon_name = info['CFBundleIconFile']
        assert Path(icon_name).name == icon_name
        icon = (resources / (icon_name if icon_name.endswith('.icns') else icon_name + '.icns')).read_bytes()
        assert icon[:4] == b'icns' and int.from_bytes(icon[4:8], 'big') == len(icon), 'Invalid app icon'
        executable = moved / 'Contents/MacOS' / info['CFBundleExecutable']
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(moved)], check=True)
        libraries = subprocess.check_output(['/usr/bin/otool', '-L', str(executable)], text=True)
        for line in libraries.splitlines()[1:]:
            dependency = line.strip().split(' (', 1)[0]
            assert dependency.startswith(('/usr/lib/', '/System/Library/', '@')), dependency
        subprocess.run([str(executable), '--smoke-test'], cwd=temporary,
                       env=dict(os.environ, PATH='/usr/bin:/bin'), check=True, timeout=30)
        print('Relocated app, bundled resources, signature, and startup passed.')


if __name__ == '__main__':
    verify_app(Path(sys.argv[1]).resolve())
