# Offline Proof Gate (offline-proof) 🔒

Command

```bash
python tools/rb offline-proof --run-id $RUN_ID --scope all
```

Evidence

- `runs/$RUN_ID/reports/offline-proof.json`

Success Criteria

- Report status == "passed" and a `proof_hash` present.

Failure Actions

- Preserve `offline-proof.json` and `events.jsonl`.
- Inspect `error` and `offender_uris` fields.
- If `nix eval` failed due to blocked URIs, ensure mirrors/blobs cover inputs and re-run prefetch/mirror sync; escalate if unexpected.

Quick commands

- `jq . runs/$RUN_ID/reports/offline-proof.json`