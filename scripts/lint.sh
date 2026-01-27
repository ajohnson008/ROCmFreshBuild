#!/usr/bin/env bash
# lint.sh - Shell script linting and formatting check
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Find all shell scripts in scripts directory
FILES=$(find scripts -type f -name "*.sh")

echo "📂 Checking scripts: $(echo "$FILES" | tr '\n' ' ')"

MISSING=()
if ! command -v shellcheck >/dev/null 2>&1; then
    MISSING+=("shellcheck")
fi
if ! command -v shfmt >/dev/null 2>&1; then
    MISSING+=("shfmt")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "⚠️ Missing tools: ${MISSING[*]}"
    echo "💡 Run with: nix shell nixpkgs#shellcheck nixpkgs#shfmt -c ./scripts/lint.sh"
    echo ""
fi

EXIT_CODE=0

if command -v shellcheck >/dev/null 2>&1; then
    echo "🔍 Running shellcheck..."
    if shellcheck $FILES; then
        echo "✅ ShellCheck passed!"
    else
        echo "❌ ShellCheck failed!"
        EXIT_CODE=1
    fi
fi

if command -v shfmt >/dev/null 2>&1; then
    echo "🔍 Checking shfmt formatting..."
    if shfmt -d $FILES; then
        echo "✅ shfmt check passed!"
    else
        echo "❌ shfmt check failed! Run 'shfmt -w scripts/' to fix."
        EXIT_CODE=1
    fi
fi

exit $EXIT_CODE
