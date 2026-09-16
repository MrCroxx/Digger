#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--dir" ) ]]; then
  echo "Usage: scripts/package-desktop.sh [--dir]" >&2
  exit 1
fi
if [[ "${1:-}" == "--dir" ]]; then export CREATE_DMG=0 CREATE_ZIP=0; fi
git diff --check
/usr/bin/python3 scripts/test-macos-dmg.py
/usr/bin/python3 scripts/test-transport.py
exec ./scripts/build-app.sh
