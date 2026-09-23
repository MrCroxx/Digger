#!/usr/bin/env python3
"""Render current native documentation screenshots with isolated, offline fixtures."""
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
output = root / "docs" / "images"
subprocess.run(["swift", "build"], cwd=root, check=True)
binary_dir = subprocess.check_output(
    ["swift", "build", "--show-bin-path"], cwd=root, text=True
).strip()
binary = pathlib.Path(binary_dir) / "digger"
scenes = {
    "popup": [],
    "markdown": ["--showcase-code"],
    "dark": ["--dark"],
    "prompts": ["--settings", "--settings-tab", "functions"],
    "appearance": ["--settings", "--settings-tab", "popup"],
    "provider": ["--settings", "--settings-tab", "api"],
}
for language in ("en", "zh"):
    for name, options in scenes.items():
        path = output / f"{name}-{language}.png"
        path.unlink(missing_ok=True)
        subprocess.run(
            [str(binary), "--preview", "--showcase", "--light",
             *(["--english"] if language == "en" else []), *options,
             "--render", str(path), "--render-delay", "2"],
            cwd=root, check=True, timeout=30,
        )
        if not path.is_file() or path.stat().st_size == 0:
            raise RuntimeError(f"Preview did not render {path}")
        print(f"Rendered {path.relative_to(root)}", flush=True)
