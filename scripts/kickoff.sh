#!/usr/bin/env bash
set -euo pipefail

# Scripts/kickoff.sh - Wrapper for TheRockBuilder with GPU target support

# Default values
LOG_DIR="runs"
FORCE=false
ARCHIVE_TO=""
DRY_RUN=false
CMD=""
ARGS=()
TARGET="${ROCM_BUILD_TARGET:-gfx110x}"  # Default to gfx110x (better performance)

usage() {
    echo "Usage: $0 [prep-full|build-full|full] [options]"
    echo ""
    echo "Commands:"
    echo "  prep-full   Run full preparation"
    echo "  build-full  Run full build (implies prep unless skipped)"
    echo "  full        Run prep-full then build-full"
    echo ""
    echo "Options:"
    echo "  --dry-run           Show what would be run"
    echo "  --archive-to <path> Path to archive flake inputs (prep only)"
    echo "  --force             Bypass warnings (not hard fails)"
    echo "  --log-dir <path>    Directory for logs (default: runs/)"
    echo "  --target <name>     GPU target variant (default: gfx110x)"
    echo "  --help              Show this help"
    echo ""
    echo "GPU Targets:"
    echo "  gfx110x   RDNA3 GPUs (RX 7900/7800/7700) - DEFAULT (2-6X faster)"
    echo "  gfx1151   Strix Halo (Ryzen AI Max+) - Legacy support"
    echo ""
    echo "Environment Variables:"
    echo "  ROCM_BUILD_TARGET   Override default target (gfx110x or gfx1151)"
    echo ""
    echo "Examples:"
    echo "  $0 full                         # Build gfx110x (default)"
    echo "  $0 full --target gfx1151        # Build for Strix Halo"
    echo "  ROCM_BUILD_TARGET=gfx1151 $0 full  # Same as above"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        prep-full)
            CMD="prep"
            ARGS+=("full")
            shift
            ;;
        build-full)
            CMD="build"
            ARGS+=("full")
            shift
            ;;
        full)
            CMD="full"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --target)
            TARGET="$2"
            case "$TARGET" in
                gfx110x|gfx1151)
                    # Valid target
                    ;;
                *)
                    echo "Error: Invalid target '$TARGET'"
                    echo "Valid targets: gfx110x, gfx1151"
                    exit 1
                    ;;
            esac
            shift 2
            ;;
        --)
            shift
            ;;
        --archive-to)
            ARCHIVE_TO="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --log-dir)
            LOG_DIR="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            ;;
    esac
done

if [ -z "$CMD" ]; then
    usage
fi

# Setup logging
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/kickoff_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1


# Export target for downstream scripts
export ROCM_BUILD_TARGET="$TARGET"

# Display target info
case "$TARGET" in
    gfx110x)
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  GPU Target: gfx110X-all (RDNA3)                       ║"
        echo "║  Hardware: RX 7900 XTX/XT, 7800 XT, 7700 XT, etc.     ║"
        echo "║  Performance: 2-6X faster than gfx1151                 ║"
        echo "╚════════════════════════════════════════════════════════╝"
        ;;
    gfx1151)
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  GPU Target: gfx1151 (Strix Halo)                     ║"
        echo "║  Hardware: Ryzen AI Max+ (Radeon 890M integrated)     ║"
        echo "║  Note: Legacy target, use gfx110x for better perf     ║"
        echo "╚════════════════════════════════════════════════════════╝"
        ;;
esac
echo ""
echo "=== Kickoff Started at $(date) ==="
echo "Command: $CMD"
echo "Log file: $LOG_FILE"

# Construct RB arguments
RB_OPTS=()
if [ "$FORCE" = true ]; then
    RB_OPTS+=("--force")
fi
if [ -n "$ARCHIVE_TO" ]; then
    # Only applicable to prep usually, but passing it won't hurt if we logic it right
    if [[ "$CMD" == "prep" || "$CMD" == "full" ]]; then
        RB_OPTS+=("--archive-to" "$ARCHIVE_TO")
    fi
fi

# Helper to run rb
run_rb() {
    local subcommand=$1
    shift
    local cmd_args=("$@")
    
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] ./rb $subcommand ${cmd_args[*]} ${RB_OPTS[*]}"
    else
        echo "Running: ./rb $subcommand ${cmd_args[*]} ${RB_OPTS[*]}"
        ./rb "$subcommand" "${cmd_args[@]}" "${RB_OPTS[@]}"
    fi
}

# Execution
if [ "$CMD" == "prep" ]; then
    run_rb "prep" "full"
elif [ "$CMD" == "build" ]; then
    run_rb "build" "full"
elif [ "$CMD" == "full" ]; then
    # Full means prep-full then build-full
    run_rb "prep" "full"
    
    # Check exit code if not dry run
    if [ "$DRY_RUN" = false ] && [ $? -ne 0 ]; then
        echo "❌ Prep failed. Aborting."
        exit 1
    fi
    
    run_rb "build" "full"
fi

echo "=== Kickoff Finished at $(date) ==="