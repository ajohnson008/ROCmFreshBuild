#!/usr/bin/env bash
set -euo pipefail

paths=(
  README.md
  HOW-TO.md
  PRD_v6.0.md
  AGENTS.md
  agent_playbooks
  scripts
  .github
  implementation_plan.md
  task.md
)

if grep -rn "tools/rb" "${paths[@]}" | grep -v "scripts/tests/check_entrypoint_refs.sh"; then
  echo "❌ Disallowed tools/rb references found. Use ./rb instead." >&2
  exit 1
fi

if grep -rnE "python(3(\.11)?)?\s+\./rb" "${paths[@]}" | grep -v "scripts/tests/check_entrypoint_refs.sh"; then
  echo "❌ Disallowed 'python ./rb' usage found. Invoke ./rb directly." >&2
  exit 1
fi

echo "✅ Entry point references use ./rb"
