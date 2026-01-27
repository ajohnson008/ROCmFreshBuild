#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${RB_PYTHON:-}" ]]; then
  PYTHON_BIN="$RB_PYTHON"
elif command -v python3.11 >/dev/null 2>&1; then
  PYTHON_BIN=python3.11
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN=python3
else
  echo "❌ rb: python3.11 or python3 not found. Install Python 3.11+ or set RB_PYTHON." >&2
  exit 2
fi

exec "$PYTHON_BIN" "$SCRIPT_DIR/tools/rb" "$@"
