#!/usr/bin/env bash
# scripts/validate-targets.sh
# Comprehensive validation script for all GPU target variants
# 
# Usage:
#   ./scripts/validate-targets.sh              # Test all targets
#   ./scripts/validate-targets.sh gfx110x      # Test specific target
#   ./scripts/validate-targets.sh gfx1151      # Test specific target

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✅${NC} $*"
    ((PASSED_TESTS++)) || true
    ((TOTAL_TESTS++)) || true
}

log_warning() {
    echo -e "${YELLOW}⚠️${NC} $*"
}

log_error() {
    echo -e "${RED}❌${NC} $*"
    ((FAILED_TESTS++)) || true
    ((TOTAL_TESTS++)) || true
}

print_header() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  $*"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
}

print_section() {
    echo ""
    echo "─────────────────────────────────────────────────────────"
    echo "  $*"
    echo "─────────────────────────────────────────────────────────"
}

# ============================================================================
# Validation Functions
# ============================================================================

# Test: Nix flake structure is valid
test_flake_validity() {
    print_section "Test: Flake Validity"
    
    if nix flake check 2>/dev/null; then
        log_success "Flake structure is valid"
        return 0
    else
        log_error "Flake check failed"
        return 1
    fi
}

# Test: Target configuration exists
test_target_config_exists() {
    local target="$1"
    print_section "Test: Target Configuration ($target)"
    
    if [ -f "lib/targets.nix" ]; then
        log_success "lib/targets.nix exists"
    else
        log_error "lib/targets.nix not found"
        return 1
    fi
    
    # Verify target is defined in targets.nix
    if grep -q "\"$target\"" lib/targets.nix 2>/dev/null || grep -q "$target =" lib/targets.nix 2>/dev/null; then
        log_success "Target '$target' defined in lib/targets.nix"
        return 0
    else
        log_error "Target '$target' not found in lib/targets.nix"
        return 1
    fi
}

# Test: Build ROCm core for target
test_build_rocm_core() {
    local target="$1"
    print_section "Test: Build ROCm Core ($target)"
    
    log_info "Building rocm-core-$target (this may take 30-60 minutes)..."
    
    if nix build ".#rocm-core-$target" --print-build-logs 2>&1 | tee "/tmp/rocm-build-$target.log"; then
        log_success "ROCm core built successfully for $target"
        
        # Verify result exists
        if [ -L "result" ]; then
            log_success "Build artifact created: $(readlink -f result)"
        else
            log_error "Build succeeded but result symlink not found"
            return 1
        fi
        
        return 0
    else
        log_error "ROCm core build failed for $target"
        log_error "See /tmp/rocm-build-$target.log for details"
        return 1
    fi
}

# Test: Verify ROCm installation
test_rocm_installation() {
    local target="$1"
    print_section "Test: ROCm Installation ($target)"
    
    if [ ! -L "result" ]; then
        log_error "No build result found (run build test first)"
        return 1
    fi
    
    local result_path
    result_path=$(readlink -f result)
    
    # Check for rocminfo binary
    if [ -f "$result_path/bin/rocminfo" ]; then
        log_success "rocminfo binary exists"
    else
        log_error "rocminfo binary not found in $result_path/bin/"
        return 1
    fi
    
    # Check for ROCm version marker
    if [ -f "$result_path/share/rocm-version" ]; then
        local version
        version=$(cat "$result_path/share/rocm-version")
        if [ "$version" = "7.2.0" ]; then
            log_success "ROCm version: $version (correct)"
        else
            log_error "ROCm version: $version (expected 7.2.0)"
            return 1
        fi
    else
        log_warning "ROCm version marker not found (may be OK)"
    fi
    
    return 0
}

# Test: GPU target validation
test_gpu_target_validation() {
    local target="$1"
    print_section "Test: GPU Target Validation ($target)"
    
    if [ ! -L "result" ]; then
        log_error "No build result found (run build test first)"
        return 1
    fi
    
    local result_path
    result_path=$(readlink -f result)
    
    case "$target" in
        gfx110x)
            # Check for gfx110X targets in config
            if grep -qE "gfx110[0-3]" "$result_path/etc/rocm/target.conf" 2>/dev/null; then
                log_success "gfx110X targets found in configuration"
                return 0
            else
                log_error "gfx110X targets not found in configuration"
                return 1
            fi
            ;;
        gfx1151)
            # Check for gfx1151 target in config
            if grep -q "gfx1151" "$result_path/etc/rocm/target.conf" 2>/dev/null; then
                log_success "gfx1151 target found in configuration"
                return 0
            else
                log_error "gfx1151 target not found in configuration"
                return 1
            fi
            ;;
        *)
            log_error "Unknown target: $target"
            return 1
            ;;
    esac
}

# Test: NVIDIA isolation
test_nvidia_isolation() {
    local target="$1"
    print_section "Test: NVIDIA Isolation ($target)"
    
    if [ ! -L "result" ]; then
        log_error "No build result found (run build test first)"
        return 1
    fi
    
    local result_path
    result_path=$(readlink -f result)
    
    # Check for NVIDIA contamination in dependencies
    local deps
    deps=$(nix-store -qR "$result_path" 2>/dev/null || echo "")
    
    if echo "$deps" | grep -iE "(cuda|nvidia|nccl|cudnn)" >/dev/null; then
        log_error "NVIDIA contamination detected in dependency closure:"
        echo "$deps" | grep -iE "(cuda|nvidia|nccl|cudnn)"
        return 1
    else
        log_success "No NVIDIA contamination detected"
    fi
    
    # Check for CUDA symbols in binaries (if objdump available)
    if command -v objdump &>/dev/null; then
        if find "$result_path/bin" -type f -executable 2>/dev/null | head -n 5 | while read -r binary; do
            if objdump -T "$binary" 2>/dev/null | grep -iE "(cuda|nv_)" >/dev/null; then
                log_error "CUDA symbols found in $binary"
                return 1
            fi
        done; then
            log_error "CUDA symbols detected in binaries"
            return 1
        else
            log_success "No CUDA symbols in binaries"
        fi
    else
        log_warning "objdump not available, skipping binary symbol check"
    fi
    
    return 0
}

# Test: Package independence
test_package_independence() {
    print_section "Test: Package Independence"
    
    log_info "Verifying gfx110x and gfx1151 produce different artifacts..."
    
    local path_gfx110x
    local path_gfx1151
    
    path_gfx110x=$(nix path-info ".#rocm-core-gfx110x" 2>/dev/null || echo "")
    path_gfx1151=$(nix path-info ".#rocm-core-gfx1151" 2>/dev/null || echo "")
    
    if [ -z "$path_gfx110x" ] || [ -z "$path_gfx1151" ]; then
        log_error "Could not determine package paths (build packages first)"
        return 1
    fi
    
    if [ "$path_gfx110x" = "$path_gfx1151" ]; then
        log_error "Packages have identical paths (not independent!)"
        log_error "  gfx110x: $path_gfx110x"
        log_error "  gfx1151: $path_gfx1151"
        return 1
    else
        log_success "Packages are independent:"
        log_info "  gfx110x: $path_gfx110x"
        log_info "  gfx1151: $path_gfx1151"
    fi
    
    return 0
}

# ============================================================================
# Target Test Suite
# ============================================================================

run_target_tests() {
    local target="$1"
    
    print_header "Testing Target: $target"
    
    # Test 1: Configuration exists
    test_target_config_exists "$target" || return 1
    
    # Test 2: Build ROCm core
    if ! test_build_rocm_core "$target"; then
        log_error "Build failed, skipping remaining tests for $target"
        return 1
    fi
    
    # Test 3: Verify installation
    test_rocm_installation "$target" || return 1
    
    # Test 4: GPU target validation
    test_gpu_target_validation "$target" || return 1
    
    # Test 5: NVIDIA isolation
    test_nvidia_isolation "$target" || return 1
    
    # Cleanup result symlink for next test
    rm -f result
    
    return 0
}

# ============================================================================
# Main
# ============================================================================

main() {
    print_header "TheRockBuilder Target Validation Suite"
    
    log_info "Repository: $REPO_ROOT"
    log_info "Date: $(date)"
    log_info "Nix version: $(nix --version 2>/dev/null || echo 'not found')"
    
    # Parse arguments
    local targets_to_test=()
    
    if [ $# -eq 0 ]; then
        # No arguments - test all targets
        targets_to_test=("gfx110x" "gfx1151")
        log_info "No targets specified - testing all targets"
    else
        # Test specified targets
        targets_to_test=("$@")
        log_info "Testing specified targets: ${targets_to_test[*]}"
    fi
    
    # Pre-flight: Flake validity
    if ! test_flake_validity; then
        log_error "Flake validation failed - cannot proceed"
        exit 1
    fi
    
    # Test each target
    local failed_targets=()
    for target in "${targets_to_test[@]}"; do
        if run_target_tests "$target"; then
            log_success "All tests passed for $target"
        else
            log_error "Some tests failed for $target"
            failed_targets+=("$target")
        fi
    done
    
    # Cross-target tests (if testing multiple targets)
    if [ ${#targets_to_test[@]} -gt 1 ]; then
        print_header "Cross-Target Tests"
        test_package_independence
    fi
    
    # Final summary
    print_header "Test Summary"
    
    echo "Total tests run: $TOTAL_TESTS"
    echo "  ${GREEN}✅ Passed: $PASSED_TESTS${NC}"
    if [ $FAILED_TESTS -gt 0 ]; then
        echo "  ${RED}❌ Failed: $FAILED_TESTS${NC}"
    fi
    echo ""
    
    if [ ${#failed_targets[@]} -eq 0 ]; then
        log_success "All targets validated successfully!"
        echo ""
        echo "Next steps:"
        echo "  1. Build full AI stack: nix build .#ai-stack-gfx110x"
        echo "  2. Run integration tests: nix run .#integration-test"
        echo "  3. Create deployment bundle: nix run .#bundle-creator"
        return 0
    else
        log_error "Validation failed for targets: ${failed_targets[*]}"
        echo ""
        echo "Troubleshooting:"
        echo "  - Check build logs in /tmp/rocm-build-*.log"
        echo "  - Verify lib/targets.nix configuration"
        echo "  - Review flake.nix package definitions"
        return 1
    fi
}

# Run main function
main "$@"
exit $?
