# Flake Input Prefetch (flake-prefetch) 📦

Command

```bash
python tools/rb prefetch-flake-inputs --run-id $RUN_ID
```

Evidence

- `runs/$RUN_ID/prefetch-report.json`
- `runs/$RUN_ID/events.jsonl` (event `prefetch_complete`)

Success Criteria

- `prefetch-report.json.success == true` and exit_code == 0

Failure Actions

- Retry (RETRY_3). Inspect `prefetch-report.json.error` or `stderr` content.
- Ensure network allowed for this phase, and mirrors contain required inputs.

Quick commands

- `jq . runs/$RUN_ID/prefetch-report.json`