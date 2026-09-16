#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec /usr/bin/python3 "$ROOT_DIR/scripts/verify_macos_dmg.py" "${1:?Usage: verify-dmg.sh path/to/Digger.dmg [app-name]}" "${2:-Digger}"
