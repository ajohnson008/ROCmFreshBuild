# Agent Playbook Index 📚

Welcome — quick navigation for agents and humans.

- Runbook: `agent_playbooks/README_RUNBOOK.md`
- Per-phase checklists: `agent_playbooks/checklists/`
  - `01-policy-gate.md`
  - `02-mirror-sync.md`
  - `03-flake-prefetch.md`
  - `04-offline-proof.md`
  - `05-lock-generation.md`
  - `06-graph-extraction.md`
  - `07-build-pass-a.md`
  - `08-gator-mini-scan.md`

- Playbook file: `agent_playbooks/playbook.json`
- Stories: `agent_playbooks/stories/` (failure scenarios and remediation)

Usage

- Start with `README_RUNBOOK.md` for one-line commands.
- Consult the per-phase checklist for evidence locations and immediate remediation steps.
- CI: `.github/workflows/ci-agent.yml` validates the playbook and runs a dry policy + offline-proof.

Keep this directory small and agent-readable.