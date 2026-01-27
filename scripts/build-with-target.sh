#!/usr/bin/env bash
# scripts/build-with-target.sh
# Target-aware build wrapper for TheRockBuilder v6.1+
#
# Usage:
#   ./scripts/build-with-target.sh <target> <component> [options]
#
# Examples:
#   ./scripts/build-with-target.sh gfx110x rocm-core
#   ./scripts/build-with-target.sh gfx1151 pytorch-rocm
#   ./scripts/build-with-target.sh gfx110x ai-stack --dry-run
#   ./scripts/build-with-target.sh list

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Available targets
VALID_TARGETS=("gfx110x" "gfx1151")

# Available components
VALID_COMPONENTS=(
  "rocm-core"
  "numpy"
  "pytorch-rocm"
  "torchvision"
  "torchaudio"
  "flash-attention"
  "xformers"
  "deepspeed"
  "bitsandbytes"
  "vllm"
  "llamacpp-gpu"
  "llamacpp-cpu"
  "onnxruntime"
  "ai-stack"
  "all"
)

# ==============================================================================
# Helper Functions
# ==============================================================================

print_header() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║  TheRockBuilder v6.1+ Target-Aware Build System         ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

print_section() {
  echo ""
  echo -e "${BOLD}═══ $1 ═══${NC}"
  echo ""
}

print_usage() {
  cat <<EOF
${BOLD}Usage:${NC}
  $(basename "$0") <target> <component> [options]
  $(basename "$0") list
  $(basename "$0") help

${BOLD}Arguments:${NC}
  target      GPU target variant (gfx110x or gfx1151)
  component   Component to build (see Components below)

${BOLD}Options:${NC}
  --dry-run       Show what would be built without building
  --verbose       Show detailed build output
  --no-checks     Skip pre-flight validation
  --help          Show this help message

${BOLD}Targets:${NC}
  gfx110x    RDNA 3 Desktop GPUs (RX 7900 XTX/XT, 7800 XT, 7700 XT, 7600)
             - 2-6X faster kernels than gfx1151
             - Full RCCL support, native vLLM kernels
             - DEFAULT target for best performance

  gfx1151    AMD Strix Halo APU (Ryzen AI Max+ 395)
             - Unified Memory Architecture (UMA)
             - Uses gfx1103 fallback for vLLM
             - RCCL disabled (UMA optimization)

${BOLD}Components:${NC}
  rocm-core        ROCm 7.2.0 core libraries
  numpy            NumPy with ROCm support
  pytorch-rocm     PyTorch 2.10.0 + ROCm backend
  torchvision      TorchVision
  torchaudio       Torchaudio
  flash-attention  FlashAttention-2
  xformers         xFormers with ROCm
  deepspeed        DeepSpeed (Zen 2 safe)
  bitsandbytes     Bitsandbytes quantization
  vllm             vLLM 0.14.0 inference engine
  llamacpp-gpu     llama.cpp GPU (UMA optimized)
  llamacpp-cpu     llama.cpp CPU (Zen 2 safe)
  onnxruntime      ONNX Runtime (Zen 2 safe)
  ai-stack         Complete 12-step AI stack
  all              Alias for ai-stack

${BOLD}Examples:${NC}
  # Build ROCm core for RDNA3 desktop
  $(basename "$0") gfx110x rocm-core

  # Build complete AI stack for Strix Halo
  $(basename "$0") gfx1151 ai-stack

  # Dry run to see what would be built
  $(basename "$0") gfx110x pytorch-rocm --dry-run

  # List available targets and components
  $(basename "$0") list

${BOLD}Performance Comparison:${NC}
  vLLM (Llama 3 8B):  gfx110x: 45 tok/s  |  gfx1151: 18 tok/s  (2.5X)
  FlashAttention-2:   gfx110x: 1840 TF   |  gfx1151: 312 TF    (5.9X)
  PyTorch Training:   gfx110x: 124 s/s   |  gfx1151: 32 s/s    (3.9X)

${BOLD}More Info:${NC}
  See TARGETS.md for detailed comparison and troubleshooting
  See FLAKE_CHANGES.md for implementation details

EOF
}

list_targets_and_components() {
  print_header
  print_section "Available Targets"
  
  for target in "${VALID_TARGETS[@]}"; do
    if [ "$target" = "gfx110x" ]; then
      echo -e "  ${GREEN}${BOLD}$target${NC} ${YELLOW}(DEFAULT)${NC}"
      echo "      RDNA 3 Desktop GPUs (RX 7900/7800/7700 series)"
      echo "      Performance: 2-6X faster than gfx1151"
      echo "      RCCL: Enabled | vLLM: Native kernels"
    else
      echo -e "  ${BLUE}$target${NC}"
      echo "      AMD Strix Halo APU (Ryzen AI Max+ 395)"
      echo "      Unified Memory Architecture (UMA)"
      echo "      RCCL: Disabled | vLLM: gfx1103 fallback"
    fi
    echo ""
  done
  
  print_section "Available Components"
  
  echo "Core Components:"
  echo "  rocm-core        - ROCm 7.2.0 foundation (HIP, clr, runtime)"
  echo "  numpy            - NumPy with ROCm BLAS"
  echo ""
  echo "PyTorch Ecosystem:"
  echo "  pytorch-rocm     - PyTorch 2.10.0 with ROCm backend"
  echo "  torchvision      - Computer vision library"
  echo "  torchaudio       - Audio processing library"
  echo ""
  echo "Training Acceleration:"
  echo "  flash-attention  - FlashAttention-2 kernels"
  echo "  xformers         - Memory-efficient transformers"
  echo "  deepspeed        - Distributed training (Zen 2 safe)"
  echo "  bitsandbytes     - Quantization library"
  echo ""
  echo "Inference:"
  echo "  vllm             - High-throughput LLM serving"
  echo "  llamacpp-gpu     - llama.cpp GPU (UMA optimized)"
  echo "  llamacpp-cpu     - llama.cpp CPU (Zen 2 safe)"
  echo "  onnxruntime      - ONNX Runtime (Zen 2 safe)"
  echo ""
  echo "Complete Stacks:"
  echo "  ai-stack         - Full 12-step pipeline (all components)"
  echo "  all              - Alias for ai-stack"
  echo ""
}

validate_target() {
  local target="$1"
  for valid in "${VALID_TARGETS[@]}"; do
    if [ "$target" = "$valid" ]; then
      return 0
    fi
  done
  return 1
}

validate_component() {
  local component="$1"
  for valid in "${VALID_COMPONENTS[@]}"; do
    if [ "$component" = "$valid" ]; then
      return 0
    fi
  done
  return 1
}

get_nix_attribute() {
  local target="$1"
  local component="$2"
  
  # Handle 'all' alias
  if [ "$component" = "all" ]; then
    component="ai-stack"
  fi
  
  # Return flake attribute
  echo ".#${component}-${target}"
}

check_system_resources() {
  local target="$1"
  local component="$2"
  
  print_section "System Resources Check"
  
  # Check CPU cores
  local cores
  cores=$(nproc)
  print_info "CPU cores: $cores"
  
  # Check RAM
  local ram_total ram_available
  ram_total=$(free -h | grep Mem: | awk '{print $2}')
  ram_available=$(free -h | grep Mem: | awk '{print $7}')
  print_info "RAM total: $ram_total | Available: $ram_available"
  
  # Check disk space
  local disk_free
  disk_free=$(df -h "$PROJECT_ROOT" | tail -1 | awk '{print $4}')
  print_info "Disk space free: $disk_free"
  
  # Component-specific warnings
  case "$component" in
    pytorch-rocm|ai-stack|all)
      print_warning "Large build detected: PyTorch requires 32GB+ RAM"
      print_warning "Estimated build time: 4-6 hours (PyTorch alone)"
      ;;
    vllm)
      print_warning "vLLM build requires 16GB+ RAM"
      print_warning "Estimated build time: 2-3 hours"
      ;;
  esac
  
  echo ""
}

check_gpu_hardware() {
  local target="$1"
  
  print_section "GPU Hardware Detection"
  
  # Try to detect GPU
  if command -v rocminfo &> /dev/null; then
    local detected_gpu
    detected_gpu=$(rocminfo 2>/dev/null | grep -i "Name:" | head -1 | awk '{print $2}')
    
    if [ -n "$detected_gpu" ]; then
      print_info "Detected GPU: $detected_gpu"
      
      # Warn if mismatch
      if [[ "$detected_gpu" == "gfx1100"* ]] || [[ "$detected_gpu" == "gfx1103"* ]]; then
        if [ "$target" != "gfx110x" ]; then
          print_warning "Hardware is RDNA3 ($detected_gpu) but building for $target"
          print_warning "Consider using target 'gfx110x' for 2-6X better performance"
        else
          print_success "Target matches hardware ($detected_gpu)"
        fi
      elif [[ "$detected_gpu" == "gfx1151" ]]; then
        if [ "$target" != "gfx1151" ]; then
          print_warning "Hardware is Strix Halo (gfx1151) but building for $target"
        else
          print_success "Target matches hardware (gfx1151)"
        fi
      fi
    else
      print_warning "Could not detect GPU model"
    fi
  else
    print_warning "rocminfo not found - cannot verify GPU hardware"
    print_info "Install ROCm to enable GPU detection"
  fi
  
  echo ""
}

run_preflight_checks() {
  print_section "Pre-Flight Validation"
  
  # Check flake syntax
  print_info "Checking flake syntax..."
  if nix flake check --no-build 2>&1 | grep -q "error:"; then
    print_error "Flake validation failed"
    nix flake check --no-build
    return 1
  else
    print_success "Flake syntax valid"
  fi
  
  # Check if target config exists
  print_info "Checking target configuration..."
  if nix eval ".#lib.targets.${1}" --raw &> /dev/null; then
    print_success "Target '${1}' configuration found"
  else
    print_error "Target '${1}' not found in lib/targets.nix"
    return 1
  fi
  
  echo ""
}

build_component() {
  local target="$1"
  local component="$2"
  local dry_run="$3"
  local verbose="$4"
  
  local nix_attr
  nix_attr=$(get_nix_attribute "$target" "$component")
  
  print_section "Build Configuration"
  print_info "Target: ${BOLD}$target${NC}"
  print_info "Component: ${BOLD}$component${NC}"
  print_info "Nix attribute: ${BOLD}$nix_attr${NC}"
  echo ""
  
  if [ "$dry_run" = "true" ]; then
    print_warning "DRY RUN MODE - No actual build will be performed"
    echo ""
    print_info "Would execute:"
    echo "  nix build $nix_attr --print-build-logs"
    echo ""
    print_info "To build for real, remove --dry-run flag"
    return 0
  fi
  
  print_section "Starting Build"
  
  local start_time
  start_time=$(date +%s)
  
  # Build command
  local build_cmd="nix build $nix_attr"
  
  if [ "$verbose" = "true" ]; then
    build_cmd="$build_cmd --print-build-logs"
  fi
  
  print_info "Executing: $build_cmd"
  echo ""
  
  # Run the build
  if eval "$build_cmd"; then
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    echo ""
    print_success "Build completed successfully!"
    print_info "Duration: ${duration}s ($(date -ud "@$duration" +'%H:%M:%S'))"
    
    # Show result path
    local result_path
    result_path=$(nix build "$nix_attr" --print-out-paths 2>/dev/null || echo "")
    if [ -n "$result_path" ]; then
      print_info "Result: $result_path"
    fi
    
    return 0
  else
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    echo ""
    print_error "Build failed after ${duration}s"
    print_info "Check build logs above for details"
    print_info "For verbose output, use --verbose flag"
    
    return 1
  fi
}

# ==============================================================================
# Main Script
# ==============================================================================

main() {
  # Parse arguments
  if [ $# -eq 0 ]; then
    print_error "No arguments provided"
    echo ""
    print_usage
    exit 1
  fi
  
  # Handle special commands
  case "$1" in
    list)
      list_targets_and_components
      exit 0
      ;;
    help|--help|-h)
      print_usage
      exit 0
      ;;
  esac
  
  # Require at least target and component
  if [ $# -lt 2 ]; then
    print_error "Missing required arguments"
    echo ""
    print_usage
    exit 1
  fi
  
  local target="$1"
  local component="$2"
  shift 2
  
  # Parse options
  local dry_run="false"
  local verbose="false"
  local skip_checks="false"
  
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)
        dry_run="true"
        shift
        ;;
      --verbose)
        verbose="true"
        shift
        ;;
      --no-checks)
        skip_checks="true"
        shift
        ;;
      --help)
        print_usage
        exit 0
        ;;
      *)
        print_error "Unknown option: $1"
        echo ""
        print_usage
        exit 1
        ;;
    esac
  done
  
  # Validate inputs
  if ! validate_target "$target"; then
    print_error "Invalid target: $target"
    echo ""
    echo "Valid targets: ${VALID_TARGETS[*]}"
    echo ""
    echo "Run '$(basename "$0") list' to see all options"
    exit 1
  fi
  
  if ! validate_component "$component"; then
    print_error "Invalid component: $component"
    echo ""
    echo "Valid components: ${VALID_COMPONENTS[*]}"
    echo ""
    echo "Run '$(basename "$0") list' to see all options"
    exit 1
  fi
  
  # Print header
  print_header
  
  # Run checks
  check_system_resources "$target" "$component"
  check_gpu_hardware "$target"
  
  if [ "$skip_checks" != "true" ]; then
    if ! run_preflight_checks "$target"; then
      print_error "Pre-flight checks failed"
      exit 1
    fi
  else
    print_warning "Skipping pre-flight checks (--no-checks specified)"
    echo ""
  fi
  
  # Build
  if build_component "$target" "$component" "$dry_run" "$verbose"; then
    echo ""
    print_success "Build process completed successfully!"
    exit 0
  else
    echo ""
    print_error "Build process failed"
    exit 1
  fi
}

# Run main function
main "$@"
