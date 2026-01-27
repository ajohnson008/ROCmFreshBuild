# Source Lock Generation (lock-generation) 🔐

Command

```bash
python tools/lock/gen_source_lock.py --manifest pinned/rocm/7.2.0/default.xml --output pinned/rocm/7.2.0/source-lock.json --release 7.2.0 --run-id $RUN_ID
```

Evidence

- `pinned/rocm/7.2.0/source-lock.json`
- `pinned/rocm/7.2.0/source-lock.json.sha256`

Success Criteria

- File exists and `lock_sha256` field populated.

Failure Actions

- If refs fail to resolve, re-run with network or use `--no-resolve` for offline generation.
- Verify manifest and hash files exist and match.

Quick commands

- `jq . pinned/rocm/7.2.0/source-lock.json | head -n 50`
- `cat pinned/rocm/7.2.0/source-lock.json.sha256`