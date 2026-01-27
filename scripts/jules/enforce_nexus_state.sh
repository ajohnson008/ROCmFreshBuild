#!/usr/bin/env bash
set -euo pipefail

echo "🤖 Nexus Prep Protocol Initiated..."

# Sanitize Repo (placeholder)
echo "🧹 Sanitizing repository..."
# In a real scenario, this might run 'git clean' or similar, but I'll keep it safe for now.

# Audit Agent Definitions
echo "🔍 Auditing agent definitions (Omnibook)..."
if python3 scripts/jules/audit_omnibook.py; then
    echo "✅ Agent definitions audited successfully."
else
    echo "❌ Audit failed."
    exit 1
fi

# Verify Pre-flight Checklist
echo "📋 Verifying pre-flight checklist..."
if ./rb preflight "$@"; then
    echo "✅ Pre-flight checklist verified."
else
    PREFLIGHT_RC=$?
    if [ "$PREFLIGHT_RC" -eq 3 ]; then
        echo "⚠️  Pre-flight warnings overridden (exit 3)."
    else
        echo "❌ Pre-flight checklist failed."
        exit "$PREFLIGHT_RC"
    fi
fi

echo "✅ Nexus State Enforced."
