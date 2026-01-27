# Mirror Synchronization (mirror-sync) 🔁

Command

```bash
python tools/rb sync-mirrors --run-id $RUN_ID
```

(Or run components directly)

```bash
python tools/mirror/sync_git_mirrors.py --lock pinned/rocm/7.2.0/source-lock.json --output mirrors/git --run-id $RUN_ID
python tools/mirror/sync_blobs.py --lock pinned/rocm/7.2.0/source-lock.json --output mirrors/blobs --run-id $RUN_ID
```

Evidence

- `mirrors/git/index.json`
- `mirrors/blobs/index.json`
- `runs/$RUN_ID/events.jsonl` may contain mirror_sync_complete

Success Criteria

- `index.json.synced_count == total_count` and `failed_count == 0`.

Failure Actions

- Retry (playbook uses RETRY_3).
- If repo missing, re-run `rb sync-mirrors`; do NOT fetch upstream during offline runs.
- Check `agent_playbooks/stories/mirror-missing-repo.json` for remediation steps.

Quick commands

- `jq . mirrors/git/index.json`
- `jq . mirrors/blobs/index.json`