# Agent Runbook — ROCmFreshBuild Pass A 🚦

**Purpose:** Simple, agent-friendly checklist for running the Pass A pipeline, preserving evidence, and troubleshooting common failures.

## Quick start (one-liners) 🔧
- Create a run id:

```bash
export RUN_ID=$(date +%Y%m%d-%H%M%S)-$(head /dev/urandom | tr -dc a-z0-9 | head -c6)
echo $RUN_ID
```

- Policy check (must pass):

```bash
python tools/rb policy verify --strict --run-id $RUN_ID
```

- Mirror sync (git + blobs):

```bash
python tools/rb sync-mirrors --run-id $RUN_ID
```

- Prefetch flake inputs:

```bash
python tools/rb prefetch-flake-inputs --run-id $RUN_ID
```

- Offline proof (no network):

```bash
python tools/rb offline-proof --run-id $RUN_ID --scope all
```

- Generate source lock:

```bash
python tools/lock/gen_source_lock.py --manifest pinned/rocm/7.2.0/default.xml \
  --output pinned/rocm/7.2.0/source-lock.json --release 7.2.0 --run-id $RUN_ID
```

- Extract graph & topo order:

```bash
python tools/graph/extract_graph.py --source-lock pinned/rocm/7.2.0/source-lock.json --output graph/ --run-id $RUN_ID
python tools/graph/toposort.py --graph graph/graph.json --output graph/order.json
```

- Execute Pass A build (checkpointable):

```bash
python tools/build/build_driver.py --order graph/order.json --repo-root . --run-id $RUN_ID --parallel 1
```

### Resume after a checkpoint
```bash
python tools/build/build_driver.py --order graph/order.json --repo-root . --resume runs/$RUN_ID/checkpoint.json
```

---

## Evidence locations 📁
- Run directory: `runs/$RUN_ID/`
  - `events.jsonl`, `status.json`, `receipt.json`, `checkpoint.json`
- Policy: `runs/$RUN_ID/reports/policy-report.json`
- Offline proof: `runs/$RUN_ID/reports/offline-proof.json`
- Prefetch: `runs/$RUN_ID/prefetch-report.json`
- Mirrors: `mirrors/git/index.json`, `mirrors/blobs/index.json`
- Graph: `graph/graph.json`, `graph/order.json`

> Always preserve evidence files on failures — do not overwrite or delete.

---

## Failure handling (agent-friendly) ⚠️
- Policy/Offline proof: **ABORT**. Preserve evidence and escalate to human operator.
- Network phases (mirror, prefetch): **RETRY_3** with backoff; inspect mirrors indices for failures.
- Build failures: **CHECKPOINT**. Preserve `runs/$RUN_ID/checkpoint.json` then diagnose:
  - Hash mismatch: run `nix-prefetch-url <URL>`, update hash, re-run
  - Missing mirror: `rb sync-mirrors` (do not fetch from upstream in offline run)
  - OOM / resource: reduce `--parallel`, check `free -h` and `df -h`
  - Config/compile: run `nix log .#<failed-package>` and capture last 200 lines

See `agent_playbooks/stories/` for scripted remediation steps.

---

## Best practices ✨
- Use a generated `RUN_ID` env var for all commands in a run.
- Keep commands idempotent and single-line.
- Always run `policy verify` before network or build phases.
- For long builds, prefer `--parallel 1` to avoid OOMs; bump only with monitoring.
- Add minimal, well-scoped overrides in `graph/overrides.yaml` when a project graph is incomplete.

---

## CI / Automation tips 🤖
- CI job: run a dry-run policy + offline-proof (no network) to validate baseline infrastructure.
- Add linting for `agent_playbooks/playbook.json` to catch schema drift.

---

## Security & escalation 🔒
- Never fetch from upstream during an offline run; always populate mirrors first.
- If policy or offline-proof fails with a forbidden URI, capture `reports/offline-proof.json` and escalate.
- Escalate to the human operator with: run id, failing phase, logs (last 200 lines), and proposed fix.

---

File created by the automation helper — keep it small and agent-readable. ✨
