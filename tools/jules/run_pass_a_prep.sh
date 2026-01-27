#!/usr/bin/env bash
set -euo pipefail

# tools/jules/run_pass_a_prep.sh
# Orchestrates the full Pass A prep pipeline for agent Jules.

LOG_FILE="runs/pass_a_prep_$(date +%Y%m%d_%H%M%S).log"
mkdir -p runs

echo "=== Pass A Prep Pipeline Started at $(date) ===" | tee -a "$LOG_FILE"

# Trap failure
on_failure() {
    echo "❌ Pass A Prep Pipeline FAILED at $(date)" | tee -a "$LOG_FILE"
    exit 1
}
trap on_failure ERR

# The pipeline is now encapsulated in './rb prep full'
./rb prep full 2>&1 | tee -a "$LOG_FILE"

echo "=== Pass A Prep Pipeline Finished at $(date) ===" | tee -a "$LOG_FILE"