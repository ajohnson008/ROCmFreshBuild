#!/usr/bin/env bash
set -euo pipefail

json_out="runs/preflight-missing.json"
backup="flake.nix.bak"

if [ ! -f flake.nix ]; then
  echo "flake.nix not found; cannot run test" >&2
  exit 2
fi

mv flake.nix "$backup"
trap 'mv "$backup" flake.nix' EXIT

set +e
./rb preflight --json-out "$json_out" >/dev/null 2>&1
rc=$?
set -e

if [ "$rc" -ne 2 ]; then
  echo "Expected exit code 2 when flake.nix missing, got $rc" >&2
  exit 1
fi

python - <<'PY'
import json
from pathlib import Path

path = Path("runs/preflight-missing.json")
if not path.exists():
    raise SystemExit("Missing preflight JSON output")

report = json.loads(path.read_text())
checks = {c["id"]: c for c in report.get("checks", [])}
req = checks.get("required_files")
if not req:
    raise SystemExit("Missing required_files check")
missing = req.get("details", {}).get("missing", [])
if "flake.nix" not in missing:
    raise SystemExit(f"flake.nix not reported missing: {missing}")

print("missing-file preflight test ok")
PY
