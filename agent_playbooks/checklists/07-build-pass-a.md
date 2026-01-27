# Pass A Build Execution (build-pass-a) 🏗️

Command

```bash
python tools/build/build_driver.py --order graph/order.json --repo-root . --run-id $RUN_ID --parallel 1
```

Resume

```bash
python tools/build/build_driver.py --order graph/order.json --repo-root . --resume runs/$RUN_ID/checkpoint.json
```

Evidence

- `runs/$RUN_ID/events.jsonl`
- `runs/$RUN_ID/status.json`
- `runs/$RUN_ID/receipt.json`
- `runs/$RUN_ID/checkpoint.json` (when checkpointed)

Success Criteria

- All layers complete with successful component builds; run status == success.

Failure Actions

- Inspect `runs/$RUN_ID/events.jsonl` and `nix log .#<failed-package>`.
- Classify failure: compile_error / missing_dep / hash_mismatch / config_error / resource_exhaustion.
- Apply fix (patch/hash/dep), then resume using checkpoint.

Quick commands

- `jq . runs/$RUN_ID/status.json`
- `tail -n 200 $(nix log .#<failed-package> | sed -n '1,1p')` (use nix log with path)
