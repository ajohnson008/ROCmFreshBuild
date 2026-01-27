# Policy Fence Gate (policy-gate) ⚖️

Command

```bash
python tools/rb policy verify --strict --run-id $RUN_ID
```

Evidence

- `runs/$RUN_ID/reports/policy-report.json`
- `runs/$RUN_ID/receipt.json`

Success Criteria

- `policy-report.json.passed == true` and no violations.

Failure Actions

- Preserve evidence files in `runs/$RUN_ID/`.
- Inspect `policy-report.json` for violation categories (version_drift, source_lock_missing, manifest_hash_mismatch).
- Fix manifest / source-lock or escalate to human if unexpected violations.

Quick commands

- `jq . runs/$RUN_ID/reports/policy-report.json`
- `cat runs/$RUN_ID/receipt.json`