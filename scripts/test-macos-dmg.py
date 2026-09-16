#!/usr/bin/env python3
"""Regression tests for busy/unmounted devices and safe packaging cleanup."""
import contextlib
import io
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from create_macos_dmg import create_dmg


class DmgTests(unittest.TestCase):
    def fixture(self, busy=0, disappear=False, icon_error=False, unknown=False, status=16):
        fixture = tempfile.TemporaryDirectory()
        self.addCleanup(fixture.cleanup)
        root = Path(fixture.name)
        icon = root / 'icon.icns'
        icon.write_bytes(b'icon')
        state = {'attached': False, 'detaches': [], 'delays': [], 'commands': []}
        entities = [{'dev-entry': '/dev/disk42'}, {'dev-entry': '/dev/disk42s1'}]

        def run(tool, *args, capture=False):
            state['commands'].append((tool, args))
            if tool == '/usr/bin/xcrun':
                self.assertEqual((state['mount'] / '.VolumeIcon.icns').read_bytes(), b'icon')
                if icon_error:
                    raise RuntimeError('SetFile failed')
                return
            if tool == '/usr/bin/swift':
                return
            self.assertEqual(tool, '/usr/bin/hdiutil')
            if args[0] == 'create':
                return
            if args[0] == 'attach':
                state['mount'] = Path(args[args.index('-mountpoint') + 1])
                self.addCleanup(lambda: shutil.rmtree(state['mount'].parent, ignore_errors=True))
                state['attached'] = True
                return plistlib.dumps({'system-entities': [] if unknown else entities})
            if args[0] == 'detach':
                self.assertEqual(args[1], '/dev/disk42')
                state['detaches'].append(args)
                if len(state['detaches']) <= busy:
                    # The mountpoint can disappear even when the disk device remains attached.
                    shutil.rmtree(state['mount'], ignore_errors=True)
                    if disappear:
                        state['attached'] = False
                    raise subprocess.CalledProcessError(status, args)
                state['attached'] = False
                return
            if args[0] == 'info':
                return plistlib.dumps({'images': [{'system-entities': entities}] if state['attached'] else []})
            if args[0] == 'convert':
                self.assertFalse(state['attached'])
                return
            self.fail(args)

        def build():
            with contextlib.redirect_stderr(io.StringIO()):
                create_dmg(root, root / 'Digger.dmg', icon, 'Digger', run, state['delays'].append)
        return state, build

    def test_icons_and_cleanup(self):
        state, build = self.fixture()
        build()
        self.assertEqual(state['detaches'], [('detach', '/dev/disk42')])
        self.assertFalse(state['mount'].parent.exists())
        self.assertTrue(any(tool == '/usr/bin/swift' for tool, _ in state['commands']))

    def test_busy_device_after_mountpoint_disappears(self):
        state, build = self.fixture(busy=7)
        build()
        self.assertEqual(len(state['detaches']), 8)
        self.assertEqual(state['delays'], [1, 2, 3, 4, 5, 5, 5])
        self.assertFalse(state['mount'].parent.exists())

    def test_force_only_after_normal_retries(self):
        state, build = self.fixture(busy=15)
        build()
        self.assertEqual(state['detaches'][-1], ('detach', '/dev/disk42', '-force'))
        self.assertEqual(sum(state['delays']), 65)
        self.assertTrue(all('-force' not in args for args in state['detaches'][:-1]))

    def test_already_detached(self):
        state, build = self.fixture(busy=1, disappear=True)
        build()
        self.assertEqual(len(state['detaches']), 1)

    def test_persistent_failure_preserves_files(self):
        for status, attempts in [(16, 16), (1, 1)]:
            with self.subTest(status=status):
                state, build = self.fixture(busy=99, status=status)
                with self.assertRaises(subprocess.CalledProcessError):
                    build()
                self.assertEqual(len(state['detaches']), attempts)
                self.assertTrue(state['mount'].parent.exists())
                self.assertFalse(any(args[0] == 'convert' for _, args in state['commands']))

    def test_icon_failure_detaches_and_cleans_up(self):
        state, build = self.fixture(icon_error=True, busy=1)
        with self.assertRaisesRegex(RuntimeError, 'SetFile failed'):
            build()
        self.assertFalse(state['mount'].parent.exists())

    def test_both_failures_are_preserved(self):
        state, build = self.fixture(icon_error=True, busy=99)
        with self.assertRaises(subprocess.CalledProcessError) as error:
            build()
        self.assertIsInstance(error.exception.__context__, RuntimeError)
        self.assertTrue(state['mount'].parent.exists())

    def test_unknown_device_is_preserved(self):
        state, build = self.fixture(unknown=True)
        with self.assertRaisesRegex(RuntimeError, 'Cannot identify'):
            build()
        self.assertEqual(state['detaches'], [])
        self.assertTrue(state['mount'].parent.exists())


if __name__ == '__main__':
    unittest.main()
