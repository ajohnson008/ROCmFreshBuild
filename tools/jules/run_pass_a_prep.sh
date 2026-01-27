#!/usr/bin/env bash
# =============================================================================
# Jules: Pass A Prep Pipeline Driver
# Orchestrates: Policy -> Mirror -> Prefetch -> Proof -> Lock -> Graph
# =============================================================================
set -euo pipefail

# CONSTANTS
REPO_ROOT="$(pwd)"
RB_CMD="./rb"
RUN_MANAGER="lib/run_manager.py"

# Ensure we are at repo root
if [ ! -f "flake.nix" ]; then
    echo "❌ Error: Must run from repository root"
    exit 1
fi

echo "🤖 Jules: Initializing Pass A Prep Pipeline..."

# 1. Init Run
# Parse JSON output from run_manager create
# Expected output: {"run_id": "...", "run_dir": "..."}
RUN_INFO=$(python3.11 "$RUN_MANAGER" create)
RUN_ID=$(echo "$RUN_INFO" | grep -o '"run_id": *"[^"]*"' | cut -d'"' -f4)

echo "📜 Run Created: $RUN_ID"

# Export for GITHUB_OUTPUT if present
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "RUN_ID=$RUN_ID" >> "$GITHUB_OUTPUT"
fi

# Function to fail run
fail_run() {
    local phase="$1"
    local error="$2"
    echo "❌ Pipeline Failed at Phase: $phase"
    python3.11 "$RUN_MANAGER" phase-end --run-id "$RUN_ID" --phase "$phase" --status "failed" --error "$error"
    python3.11 "$RUN_MANAGER" emit --run-id "$RUN_ID" --event "run_failed" --data "{\"reason\": \"$error\"}"
    exit 1
}

# Log Start
python3.11 "$RUN_MANAGER" emit --run-id "$RUN_ID" --event "pipeline_start" --data "{\"agent\": \"jules\", \"pipeline\": \"pass_a_prep\"}"

# =============================================================================
# PHASE 0: POLICY GATE
# =============================================================================
PHASE="policy-gate"
echo ""
echo "🔐 Starting Phase 0: Policy Gate..."
python3.11 "$RUN_MANAGER" phase-start --run-id "$RUN_ID" --phase "$PHASE"

if python3.11 tools/policy/policy_fence.py --run-id "$RUN_ID" --strict; then
    python3.11 "$RUN_MANAGER" phase-end --run-id "$RUN_ID" --phase "$PHASE" --status "success"
    echo "✅ Policy Gate Passed"
else
    fail_run "$PHASE" "Policy violation detected"
fi

# =============================================================================
# PHASE 1: MIRROR SYNC
# =============================================================================
PHASE="mirror-sync"
echo ""
echo "📦 Starting Phase 1: Mirror Sync..."
python3.11 "$RUN_MANAGER" phase-start --run-id "$RUN_ID" --phase "$PHASE"

if "$RB_CMD" sync-mirrors; then
    python3.11 "$RUN_MANAGER" phase-end --run-id "$RUN_ID" --phase "$PHASE" --status "success"
    echo "✅ Mirror Sync Complete"
else
    fail_run "$PHASE" "Mirror sync failed"
fi

# =============================================================================
# PHASE 2: FLAKE PREFETCH
# =============================================================================
PHASE="flake-prefetch"
echo ""
echo "📥 Starting Phase 2: Flake Input Prefetch..."
python3.11 "$RUN_MANAGER" phase-start --run-id "$RUN_ID" --phase "$PHASE"

if "$RB_CMD" prefetch-flake-inputs; then
    python3.11 "$RUN_MANAGER" phase-end --run-id "$RUN_ID" --phase "$PHASE" --status "success"
    echo "✅ Flake Prefetch Complete"
else
    fail_run "$PHASE" "Flake prefetch failed"
fi

# =============================================================================
# PHASE 3: OFFLINE PROOF
# =============================================================================
PHASE="offline-proof"
echo ""
echo "🛡️  Starting Phase 3: Offline Proof..."
python3.11 "$RUN_MANAGER" phase-start --run-id "$RUN_ID" --phase "$PHASE"

if "$RB_CMD" offline-proof --run-id "$RUN_ID"; then
    python3.11 "$RUN_MANAGER" phase-end --run-id "$RUN_ID" --phase "$PHASE" --status "success"
    echo "✅ Offline Proof Accepted"
else
    fail_run "$PHASE" "Offline proof verification failed"
fi

# =============================================================================
# PHASE 4: LOCK GENERATION
# =============================================================================
PHASE="lock-generation"
echo ""
echo "🔒 Starting Phase 4: Lock Generation..."
python3.11 "$RUN_MANAGER" phase-start --run-id "$RUN_ID" --phase "$PHASE"

LOCK_CMD="python3.11 tools/lock/gen_source_lock.py --manifest pinned/rocm/7.2.0/default.xml --output pinned/rocm/7.2.0/source-lock.json --release 7.2.0"

if $LOCK_CMD; then
    python3.11 "$RUN_MANAGER" phase-end --run-id "$RUN_ID" --phase "$PHASE" --status "success"
    echo "✅ Source Lock Generated"
else
    fail_run "$PHASE" "Lock generation failed"
fi

# =============================================================================
# PHASE 5: GRAPH EXTRACTION
# =============================================================================
PHASE="graph-extraction"
echo ""
echo "📊 Starting Phase 5: Graph Extraction..."
python3.11 "$RUN_MANAGER" phase-start --run-id "$RUN_ID" --phase "$PHASE"

GRAPH_CMD="python3.11 tools/graph/extract_graph.py --source-lock pinned/rocm/7.2.0/source-lock.json --output graph/ --overrides graph/overrides.yaml"
SORT_CMD="python3.11 tools/graph/toposort.py --graph graph/graph.json --output graph/order.json"

if $GRAPH_CMD && $SORT_CMD; then
    python3.11 "$RUN_MANAGER" phase-end --run-id "$RUN_ID" --phase "$PHASE" --status "success"
    echo "✅ Graph Extracted & Sorted"
else
    fail_run "$PHASE" "Graph extraction failed"
fi

# =============================================================================
# FINALIZE
# =============================================================================
echo ""
echo "🎉 Pipeline Complete!"
python3.11 "$RUN_MANAGER" emit --run-id "$RUN_ID" --event "run_success"
# Finalize run status
# Note: Since the loop is manual here, we can assume success if we reached here.
# A real implementation might want a 'finalize' command in run_manager.
# For now, we rely on the emit.

echo "Run ID: $RUN_ID"
exit 0
