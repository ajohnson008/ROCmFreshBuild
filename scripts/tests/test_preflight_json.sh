#!/usr/bin/env bash
set -euo pipefail

json_out="runs/preflight-test.json"

./rb preflight --no-preflight --json-out "$json_out" >/dev/null || [ $? -eq 3 ]

python - <<'PY'
import json
from pathlib import Path

path = Path("runs/preflight-test.json")
if not path.exists():
    raise SystemExit("Missing preflight JSON output")

report = json.loads(path.read_text())
required_keys = {"timestamp", "checks", "summary", "exit_code", "elapsed_seconds"}
missing = required_keys - report.keys()
if missing:
    raise SystemExit(f"Missing keys in report: {sorted(missing)}")

summary = report.get("summary", {})
for key in ("pass", "warn", "fail", "skip"):
    if key not in summary:
        raise SystemExit(f"Missing summary key: {key}")

checks = report.get("checks")
if not isinstance(checks, list):
    raise SystemExit("checks must be a list")

print("preflight JSON schema ok")
PY
