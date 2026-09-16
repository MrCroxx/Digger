#!/usr/bin/env python3
"""Verify the finished image and the app users will copy from it."""
import re
import shutil
import sys
import tempfile
from pathlib import Path

from create_macos_dmg import detach_image, read_plist, run
from smoke_macos import verify_app


def verify_dmg(image, name='Digger'):
    run('/usr/bin/hdiutil', 'verify', str(image))
    mount = Path(tempfile.mkdtemp(prefix='digger-dmg-verify-'))
    may_be_attached = False
    device = None
    try:
        may_be_attached = True
        attached = read_plist(run, 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(image))
        device = next((e['dev-entry'] for e in attached['system-entities']
                       if re.fullmatch(r'/dev/disk\d+', e.get('dev-entry', ''))), None)
        if not device:
            raise RuntimeError('Cannot identify the attached DMG device')
        app = mount / f'{name}.app'
        assert (mount / 'Applications').is_symlink()
        assert (mount / 'Applications').readlink() == Path('/Applications')
        assert (mount / '.VolumeIcon.icns').read_bytes() == (app / 'Contents/Resources/AppIcon.icns').read_bytes()
        assert run('/usr/bin/xcrun', 'GetFileInfo', '-aC', str(mount), capture=True).strip() == b'1'
        verify_app(app)
        run('/usr/bin/lipo', '-archs', str(app / 'Contents/MacOS' / name))
        print('DMG verified: standalone app, volume icon, and Applications shortcut are present.')
    finally:
        if device:
            detach_image(device)
            may_be_attached = False
        if may_be_attached:
            print(f'DMG may still be attached; preserving {mount}', file=sys.stderr)
        else:
            shutil.rmtree(mount)


if __name__ == '__main__':
    verify_dmg(Path(sys.argv[1]).resolve(), sys.argv[2] if len(sys.argv) > 2 else 'Digger')
