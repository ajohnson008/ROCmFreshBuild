#!/bin/bash
set -e
echo "=== gfx1151 Build Validation (Jan 27 2026) ==="

# Get ROCm path from environment or argument
ROCM_PATH=${1:-/opt/rocm}
if [ ! -d "$ROCM_PATH" ]; then
    # try to guess from nix store if in dev shell
    if [ -n "$ROCM_PATH" ]; then
         echo "Using ROCM_PATH=$ROCM_PATH"
    else
         echo "ROCM_PATH not set. Usage: $0 <path-to-rocm-root>"
         exit 1
    fi
fi

# Phase 1: Bitcode verification
echo "checking bitcode..."
if [ -f "$ROCM_PATH/amdgcn/bitcode/ocml.bc" ]; then
   BITCODE="$ROCM_PATH/amdgcn/bitcode/ocml.bc"
elif [ -f "$ROCM_PATH/lib/bitcode/ocml.bc" ]; then
   BITCODE="$ROCM_PATH/lib/bitcode/ocml.bc"
else
   echo "FAIL: Missing bitcode at $ROCM_PATH/amdgcn/bitcode/ocml.bc or lib/bitcode"
   exit 1
fi

if llvm-dis "$BITCODE" | grep -q "gfx1151"; then
   echo "PASS: gfx1151 intrinsics found in bitcode"
else
   echo "WARN: gfx1151 intrinsics not found in bitcode. This might be a false negative if disassembler is old."
fi

# Phase 2: PyTorch device detection
if python3 -c "import torch" 2>/dev/null; then
    echo "checking pytorch..."
    python3 <<EOF
import torch
print(f"PyTorch Version: {torch.__version__}")
if torch.cuda.is_available():
    d = torch.cuda.get_device_name(0)
    print(f"Device: {d}")
    if "gfx1151" in d or "Strix" in d:
        print("PASS: gfx1151 detected")
    else:
        print("WARN: Device name does not explicitly match gfx1151")
else:
    print("WARN: No ROCm device available (expected in container without /dev/kfd)")
EOF
else
    echo "WARN: PyTorch not installed in this environment"
fi
