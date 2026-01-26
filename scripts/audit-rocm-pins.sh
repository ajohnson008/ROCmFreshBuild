#!/usr/bin/env bash
# =============================================================================
# ROCm 7.2.0 Source Verification
# Validates that flake uses correct ROCm 7.2.0 sources via fetchFromGitHub
# =============================================================================
# NOTE: ROCm sources are NOT pinned as flake inputs because:
# 1. Large archives (686 MiB rocm-libraries) cause flake lock timeouts
# 2. Derivations fetch sources directly with rev="rocm-7.2.0"
# 3. SBOM records actual commit SHAs for reproducibility
#
# This script verifies the flake.nix contains correct ROCm 7.2.0 references
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FLAKE_NIX="$PROJECT_ROOT/flake.nix"
FLAKE_LOCK="$PROJECT_ROOT/flake.lock"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ROCm 7.2.0 Source Verification                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check flake.nix exists
if [ ! -f "$FLAKE_NIX" ]; then
  echo "❌ ERROR: flake.nix not found at $FLAKE_NIX"
  exit 1
fi

# Check flake.lock exists
if [ ! -f "$FLAKE_LOCK" ]; then
  echo "❌ ERROR: flake.lock not found at $FLAKE_LOCK"
  echo "   Run 'nix flake update' to generate the lockfile"
  exit 1
fi

echo "Checking flake.nix for ROCm 7.2.0 references..."
echo ""

# Count ROCm 7.2.0 references in fetchFromGitHub calls
rocm_refs=$(grep -c 'rev = "rocm-7.2.0"' "$FLAKE_NIX" || echo "0")
echo "✅ Found $rocm_refs derivations using rev=\"rocm-7.2.0\""

# Check for rocm-libraries (monorepo) usage
if grep -q 'repo = "rocm-libraries"' "$FLAKE_NIX"; then
  lib_count=$(grep -c 'repo = "rocm-libraries"' "$FLAKE_NIX" || echo "0")
  echo "✅ Found $lib_count derivations using rocm-libraries monorepo"
fi

echo ""
echo "Checking flake.lock for required inputs..."

# Verify essential inputs are locked
if ! command -v jq &> /dev/null; then
  echo "⚠️  jq not available, skipping lockfile validation"
else
  for input in nixpkgs nixpkgs-unstable flake-utils; do
    if jq -e ".nodes[\"$input\"]" "$FLAKE_LOCK" > /dev/null 2>&1; then
      rev=$(jq -r ".nodes[\"$input\"].locked.rev" "$FLAKE_LOCK" 2>/dev/null | head -c 12)
      echo "✅ LOCKED: $input (rev: ${rev}...)"
    else
      echo "❌ MISSING: $input"
    fi
  done
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo ""

# Summary
echo "ROCm 7.2.0 Source Verification Complete"
echo ""
echo "NOTE: ROCm sources are fetched directly by derivations using"
echo "fetchFromGitHub with rev=\"rocm-7.2.0\". The SBOM records"
echo "actual commit SHAs for full reproducibility."
echo ""

if [ "$rocm_refs" -gt 0 ]; then
  echo "✅ VERIFICATION PASSED"
  exit 0
else
  echo "⚠️  No ROCm 7.2.0 references found - check derivations"
  exit 1
fi
