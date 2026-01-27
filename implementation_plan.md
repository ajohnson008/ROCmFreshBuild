# Operationalizing Pass A Prep Pipeline

This plan details the creation of the `run_pass_a_prep.sh` script for the agent "Jules" and the update of `tools/rb`.

## User Review Required
> [!IMPORTANT]
> The script assumes `lib/run_manager.py` is in the python path or called from repo root. The script will explicitly call `python3 lib/run_manager.py`.

## Proposed Changes

### Tools
#### [MODIFY] [rb](file:///home/thenexussidekick/code/test/prd3/tools/rb)
- Implement `sync_mirrors` function to call `tools/mirror/sync_git_mirrors.py` and `tools/mirror/sync_blobs.py`.
- Ensure output streaming using `subprocess.run` (no capture).

#### [NEW] [run_pass_a_prep.sh](file:///home/thenexussidekick/code/test/prd3/tools/jules/run_pass_a_prep.sh)
- BASH script to orchestrate the full Pass A prep pipeline.
- Phases:
    1. Init Run
    2. Policy Check (`rb policy verify`)
    3. Mirror Sync (`rb sync-mirrors`)
    4. Prefetch (`rb prefetch-flake-inputs`)
    5. Offline Proof (`rb offline-proof`)
    6. Lock Generation (`gen_source_lock.py`)
    7. Graph Extraction (`extract_graph.py`)
    8. Finalize Run
- Error handling: `set -e`, trap failures to log "failed" status.

## Verification Plan

### Automated Verification
- **Syntax Check**: Run `bash -n tools/jules/run_pass_a_prep.sh` to verify syntax.
- **Dry Run**: `tools/jules/run_pass_a_prep.sh` will initiate a real run. Since this involves network (mirrors/prefetch), I will rely on the user to execute the full run, or run a partial check if feasible.
- **Unit Test**: Verify `rb sync-mirrors` calls the subprocesses correctly (can be inferred from code or simple dry run if scripts are robust to repeated runs).
