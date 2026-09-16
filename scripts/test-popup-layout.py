#!/usr/bin/env python3
"""Exercise real native streaming windows with isolated preferences and no API calls."""
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
subprocess.run(['swift', 'build'], cwd=root, check=True)
binary = subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=root, text=True).strip()
for options in [[], ['--small'], ['--small', '--expanded', '--dark', '-AppleShowScrollBars', 'Always'], ['--fixed-size']]:
    print(f'Checking popup layout: {options or "default"}', flush=True)
    result = subprocess.run(
        [str(pathlib.Path(binary) / 'digger'), '--preview', '--markdown-stream', '--verify-stream-layout', *options],
        cwd=root, timeout=60, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'Stream layout, scrolling and resizing passed.' in result.stdout, result.stdout + result.stderr
    print(result.stdout.strip(), flush=True)

result = subprocess.run([str(pathlib.Path(binary) / 'digger'), '--preview', '--verify-autosize'],
                        cwd=root, timeout=30, capture_output=True, text=True)
assert result.returncode == 0, result.stdout + result.stderr
assert 'Adaptive sizing, collapse, screen edges, manual resize and fixed mode passed.' in result.stdout
print(result.stdout.strip(), flush=True)
