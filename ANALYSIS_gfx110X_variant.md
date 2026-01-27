# ROCmFreshBuild gfx110X-all Variant Creation - Analysis & Strategy

**Analysis Date**: January 27, 2026  
**Repository**: TheRockBuilder v6.0/v6.1/v6.2 (ROCmFreshBuild)  
**Current Target**: gfx1151 (AMD Strix Halo)  
**Proposed Target**: gfx110X-all (parallel variant)  
**Analyst**: GitHub Copilot (Claude Sonnet 4.5)

---

## Executive Summary

This analysis provides a complete strategy for creating a parallel `gfx110X-all` build variant while preserving the existing `gfx1151` configuration. The repository is well-structured with clear separation between configuration, build logic, and orchestration, making this a **LOW-RISK, MODERATE-EFFORT** modification.

**Key Findings**:
- ✅ **Clean Architecture**: Single overlay file (`rocm-overlay.nix`) centralizes most GPU target configuration
- ✅ **Parametric Design**: Build system already supports multiple AMDGPU_TARGETS in a semicolon-separated list
- ✅ **Minimal Surface Area**: Only 5-7 files require modification
- ⚠️ **Documentation Density**: 15+ files reference gfx1151 in explanatory text (low-risk changes)
- 🔧 **Estimated Effort**: 4-6 hours for experienced Nix developer

---

## 1. File Inventory - Complete List

### 1.1 Critical Files (MUST Modify)

| File | Lines | gfx1151 References | Complexity | Priority |
|------|-------|-------------------|------------|----------|
| `rocm-overlay.nix` | 349 | 20 instances | **HIGH** | P0 |
| `flake.nix` | 2156 | 2 instances | **MEDIUM** | P0 |
| `policy/rocm-policy.json` | 50 | 1 instance | **LOW** | P0 |

**Details**:

#### `rocm-overlay.nix` (PRIMARY TARGET)
- **Line 2**: Header comment
- **Line 106**: `DAMDGPU_TARGETS` in rocm-llvm-bootstrap
- **Line 145-153**: Device-libs cmakeFlags (3 separate flags)
- **Line 174-183**: gfx1151 validation logic in postInstall
- **Line 187**: Meta description
- **Line 207**: Final LLVM AMDGPU_TARGETS
- **Line 242**: HIP/CLR AMDGPU_TARGETS
- **Line 281-282**: PyTorch AMDGPU_TARGETS + RCCL comment
- **Line 303**: PyTorch validation (may report as gfx1103)
- **Line 310-320**: vLLM gfx1103 fallback patches
- **Line 329**: vLLM environment AMDGPU_TARGETS

#### `flake.nix`
- **Line 354**: `AMDGPU_TARGETS = "gfx1151"` in rocm-core derivation
- **Line 457**: Comment in rocm-core target.conf generation

#### `policy/rocm-policy.json`
- **Line 17**: `gpu_targets.pass_a.allowed = ["gfx1151"]`

---

### 1.2 Documentation Files (SHOULD Update)

| File | Type | References | Priority |
|------|------|-----------|----------|
| `README.md` | User-facing | 3 | P1 |
| `HOW-TO.md` | Tutorial | 3 | P1 |
| `PRD_v6.0.md` | Specification | 3 | P1 |
| `rocm_fresh_build_v_next_prd_opus_4.md` | PRD | 5 | P1 |
| `AGENTS.md` | AI Guidelines | 0 (indirect) | P2 |
| `opus_instructions.md` | AI Instructions | 0 (indirect) | P2 |
| `vscode_skill_agent.md` | Agent Guide | 0 (indirect) | P2 |

---

### 1.3 Utility/Script Files (CONDITIONAL)

| File | Status | Action |
|------|--------|--------|
| `tools/validate-gfx1151.sh` | ✅ Keep as-is | Create `validate-gfx110x.sh` variant |
| `tools/rb` | ❌ Duplicate code | **CRITICAL**: May need deduplication |
| `generate_overlay.py` | ⚠️ Has gfx1151 | Check if actively used |
| `.vscode/tasks.json` | ❓ Not visible | May need new tasks |

---

### 1.4 Generated/Artifact Files (DO NOT MODIFY)

| File | Type | Action |
|------|------|--------|
| `repo_bundle.txt` | Generated | Regenerate after changes |
| `flake.lock` | Lock file | Regenerate after testing |
| `SBOM.spdx.json` | Generated | Regenerate per build |
| `runs/*` | Build outputs | Preserve existing |

---

## 2. Proposed Architecture Strategy

### 2.1 Option A: Function-Based Parameterization (RECOMMENDED)

**Approach**: Create a parameterized function in `rocm-overlay.nix` that generates derivations for any GPU target.

**Advantages**:
- ✅ Maximum code reuse (DRY principle)
- ✅ Easy to add more variants (gfx1030, gfx1100, etc.)
- ✅ Single source of truth for build logic
- ✅ Reduces maintenance burden

**Disadvantages**:
- ⚠️ Requires refactoring existing overlay
- ⚠️ More complex initial implementation

**Implementation Sketch**:
```nix
# rocm-overlay.nix
let
  makeROCmVariant = { gpuTargets, variantName, extraPatches ? [] }: {
    rocm-llvm-bootstrap = super.rocm-llvm-bootstrap.overrideAttrs (old: {
      cmakeFlags = (old.cmakeFlags or []) ++ [
        "-DAMDGPU_TARGETS=${gpuTargets}"
        # ... other flags
      ];
    });
    # ... repeat for all components
  };
  
  gfx1151Variant = makeROCmVariant {
    gpuTargets = "gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151";
    variantName = "gfx1151";
  };
  
  gfx110xVariant = makeROCmVariant {
    gpuTargets = "gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1101;gfx1102;gfx1103";
    variantName = "gfx110x-all";
    extraPatches = [
      # Remove gfx1151-specific workarounds
    ];
  };
in
self: super: gfx1151Variant // gfx110xVariant
```

Then in `flake.nix`:
```nix
packages = {
  # gfx1151 variants
  rocm-core-gfx1151 = ...;
  pytorch-rocm-gfx1151 = ...;
  ai-stack-gfx1151 = ...;
  
  # gfx110X-all variants
  rocm-core-gfx110x = ...;
  pytorch-rocm-gfx110x = ...;
  ai-stack-gfx110x = ...;
  
  # Default to gfx1151 for backwards compatibility
  default = self.packages.${system}.ai-stack-gfx1151;
};
```

---

### 2.2 Option B: Separate Overlay Files (SIMPLE)

**Approach**: Duplicate `rocm-overlay.nix` → `rocm-overlay-gfx110x.nix` with target changes.

**Advantages**:
- ✅ Minimal risk to existing gfx1151 build
- ✅ Quick to implement (4-6 hours)
- ✅ Easy to understand
- ✅ Clear isolation between variants

**Disadvantages**:
- ❌ Code duplication (maintenance burden)
- ❌ Bug fixes must be applied twice
- ❌ Scales poorly (adding gfx1030 = 3rd duplicate)

**Implementation**:
```nix
# flake.nix
overlays = [
  self.overlays.default  # gfx1151
  self.overlays.gfx110x  # gfx110X-all
];

# Create two package sets
pkgs-gfx1151 = import nixpkgs {
  overlays = [ (import ./rocm-overlay.nix) ];
};

pkgs-gfx110x = import nixpkgs {
  overlays = [ (import ./rocm-overlay-gfx110x.nix) ];
};

packages = {
  rocm-core-gfx1151 = pkgs-gfx1151.rocm-core;
  rocm-core-gfx110x = pkgs-gfx110x.rocm-core;
  # ...
};
```

---

### 2.3 Option C: Build-Time Parameter (ADVANCED)

**Approach**: Single overlay that reads `ROCM_GPU_TARGET` environment variable.

**Advantages**:
- ✅ Zero code duplication
- ✅ Runtime flexibility

**Disadvantages**:
- ❌ Violates Nix purity principles
- ❌ Breaks reproducibility guarantees
- ❌ Makes caching ineffective
- ❌ **NOT RECOMMENDED** for this use case

---

## 3. Recommended Strategy: Hybrid Approach

**Selected**: **Option A (Parameterization) with Option B (Separate Overlays) as fallback**

### 3.1 Phase 1: Quick Validation (Option B - 4-6 hours)

1. Duplicate `rocm-overlay.nix` → `rocm-overlay-gfx110x.nix`
2. Search/replace gfx1151 → gfx110X-all
3. Remove gfx1151-specific workarounds:
   - Line 310-320: vLLM gfx1103 fallback patches
   - Line 282: RCCL disable comment
4. Update flake.nix to expose both variants
5. Test build: `nix build .#rocm-core-gfx110x`

**Deliverable**: Working gfx110X-all build in <1 day

### 3.2 Phase 2: Refactor for Maintainability (Option A - 8-12 hours)

1. Extract common logic into `lib/rocm-builder.nix`
2. Consolidate overlays
3. Add integration tests
4. Update documentation

**Deliverable**: Production-ready dual-variant system

---

## 4. Detailed Implementation Plan

### 4.1 Naming Convention

**Pattern**: `<component>-<variant>`

| Component | gfx1151 | gfx110X-all |
|-----------|---------|-------------|
| ROCm Core | `rocm-core-gfx1151` | `rocm-core-gfx110x` |
| PyTorch | `pytorch-rocm-gfx1151` | `pytorch-rocm-gfx110x` |
| vLLM | `vllm-gfx1151` | `vllm-gfx110x` |
| llama.cpp | `llamacpp-gpu-gfx1151` | `llamacpp-gpu-gfx110x` |
| Full Stack | `ai-stack-gfx1151` | `ai-stack-gfx110x` |

**Flake Outputs**:
```nix
packages = {
  # Explicit variants
  rocm-core-gfx1151 = ...;
  rocm-core-gfx110x = ...;
  ai-stack-gfx1151 = ...;
  ai-stack-gfx110x = ...;
  
  # Backwards-compatible defaults
  rocm-core = self.packages.${system}.rocm-core-gfx1151;
  ai-stack = self.packages.${system}.ai-stack-gfx1151;
  default = self.packages.${system}.ai-stack-gfx1151;
};
```

**VS Code Tasks**:
```json
{
  "label": "Stage 2: Build ROCm (gfx1151)",
  "command": "nix build .#rocm-core-gfx1151"
},
{
  "label": "Stage 2: Build ROCm (gfx110x)",
  "command": "nix build .#rocm-core-gfx110x"
}
```

---

### 4.2 File Modifications (Phase 1 - Quick Validation)

#### Step 1: Create `rocm-overlay-gfx110x.nix`

```bash
cp rocm-overlay.nix rocm-overlay-gfx110x.nix
```

**Changes in `rocm-overlay-gfx110x.nix`**:

1. **Line 2**: Update header
```nix
# rocm-overlay-gfx110x.nix
# ROCm 7.2.0 overlay with gfx110X-all support (gfx1100, gfx1101, gfx1102, gfx1103)
```

2. **Line 106, 152-153, 207, 242, 281, 329**: Update AMDGPU_TARGETS
```nix
# OLD:
"-DAMDGPU_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151"

# NEW:
"-DAMDGPU_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1101;gfx1102;gfx1103"
```

3. **Line 145**: Update comment
```nix
# OLD:
# gfx1151 (Strix Halo) target support - EXPLICIT FLAGS REQUIRED

# NEW:
# gfx110X-all (RDNA3 full family) target support
```

4. **Line 174-183**: Update validation logic
```nix
# OLD:
echo "=== Verifying gfx1151 bitcode generation ==="
if command -v llvm-dis &>/dev/null && ! llvm-dis $out/amdgcn/bitcode/ocml.bc 2>/dev/null | grep -q "gfx1151"; then
  echo "WARNING: gfx1151 intrinsics not detected in bitcode (may still work)"
fi
echo "SUCCESS: rocm-device-libs built with gfx1151 support"

# NEW:
echo "=== Verifying gfx110X bitcode generation ==="
if command -v llvm-dis &>/dev/null && ! llvm-dis $out/amdgcn/bitcode/ocml.bc 2>/dev/null | grep -qE "gfx110[0-3]"; then
  echo "WARNING: gfx110X intrinsics not detected in bitcode (may still work)"
fi
echo "SUCCESS: rocm-device-libs built with gfx110X-all support"
```

5. **Line 282**: Remove RCCL disable (gfx110X has working RCCL)
```nix
# DELETE:
"-DUSE_RCCL=OFF"  # RCCL broken for gfx1151 - disable
```

6. **Line 303**: Update PyTorch validation
```nix
# OLD:
# gfx1151 may report as gfx1103 - accept either
assert "gfx11" in torch.cuda.get_device_name(0).lower(), "Wrong GPU architecture"

# NEW:
# Verify gfx11xx architecture detected
assert "gfx11" in torch.cuda.get_device_name(0).lower(), "Wrong GPU architecture (expected gfx110X)"
```

7. **Line 310-320**: **DELETE** vLLM gfx1103 fallback patches (not needed for gfx110X-all)
```nix
# DELETE ENTIRE SECTION:
# vLLM 0.14.0: Force gfx1103 fallback kernels (gfx1151 kernels missing)
postPatch = (old.postPatch or "") + ''
  # Force gfx1103 kernel compatibility for gfx1151
  substituteInPlace cmake/ROCM.cmake \
    --replace "gfx1151" "gfx1103" || true
  
  # Disable RCCL (broken for gfx1151)
  substituteInPlace CMakeLists.txt \
    --replace "find_package(RCCL)" "# find_package(RCCL)"
'';
```

8. **Line 329**: Update environment variables
```nix
env = old.env // {
  HIP_PLATFORM = "amd";
  CUDA_PATH = "";
  CUDA_HOME = "";
  AMDGPU_TARGETS = "gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1101;gfx1102;gfx1103";
  # NOTE: No HSA_ENABLE_SDMA/HSA_DISABLE_GWS needed for gfx110X (no UMA issues)
};
```

---

#### Step 2: Update `flake.nix`

**Add second overlay at line ~53**:
```nix
overlays = [ 
  self.overlays.default          # gfx1151 variant
  self.overlays.gfx110x           # gfx110X-all variant
];
```

**Update overlays export at bottom of file** (~line 2100):
```nix
overlays = {
  default = import ./rocm-overlay.nix;
  gfx110x = import ./rocm-overlay-gfx110x.nix;
};
```

**Add new packages** (after line ~100):
```nix
# ========================================================================
# gfx110X-all Variant Packages
# ========================================================================
rocm-core-gfx110x = pkgs.rocm-core;  # Uses gfx110x overlay
pytorch-rocm-gfx110x = pkgs.pytorch-rocm;
vllm-gfx110x = pkgs.vllm;
llamacpp-gpu-gfx110x = pkgs.llamacpp-gpu;

ai-stack-gfx110x = pkgs.buildEnv {
  name = "theRockBuilder-ai-stack-v6.1-gfx110x";
  paths = [
    self.packages.${system}.rocm-core-gfx110x
    self.packages.${system}.numpy
    self.packages.${system}.pytorch-rocm-gfx110x
    self.packages.${system}.torchvision
    self.packages.${system}.torchaudio
    self.packages.${system}.flash-attention
    self.packages.${system}.xformers
    self.packages.${system}.deepspeed
    self.packages.${system}.bitsandbytes
    self.packages.${system}.vllm-gfx110x
    self.packages.${system}.llamacpp-gpu-gfx110x
    self.packages.${system}.llamacpp-cpu
    self.packages.${system}.onnxruntime
    self.packages.${system}.model-manager
  ];
  
  postBuild = ''
    echo "🧪 Validating gfx110X-all AI stack..."
    ${self.packages.${system}.dependency-auditor}/bin/audit-dependencies $out
    echo "✅ TheRockBuilder v6.1 AI Stack ready (gfx110X-all variant)"
  '';
};
```

**Update line 354** (rocm-core environment):
```nix
# OLD:
AMDGPU_TARGETS = "gfx1151";

# NEW - Keep as-is (this is gfx1151 default)
# gfx110x variant will use different pkgs instance
```

---

#### Step 3: Update `policy/rocm-policy.json`

```json
{
  "gpu_targets": {
    "pass_a": {
      "allowed": ["gfx1151", "gfx1100", "gfx1101", "gfx1102", "gfx1103"],
      "description": "AMD Strix Halo (gfx1151) and RDNA3 family (gfx110X)"
    },
    "pass_b": {
      "enabled": false,
      "note": "Pass B deferred to NexusJr"
    }
  }
}
```

---

#### Step 4: Create New VS Code Tasks

**Add to `.vscode/tasks.json`** (if it exists):
```json
{
  "label": "Stage 2: Build ROCm (gfx110x)",
  "type": "shell",
  "command": "nix build .#rocm-core-gfx110x",
  "group": "build",
  "detail": "Build ROCm 7.2.0 core for gfx110X-all (RDNA3 family)"
},
{
  "label": "Stage 3: Build PyTorch (gfx110x)",
  "type": "shell",
  "command": "nix build .#pytorch-rocm-gfx110x",
  "group": "build",
  "detail": "Build PyTorch 2.10.0 for gfx110X-all"
},
{
  "label": "Build: Complete AI Stack (gfx110x)",
  "type": "shell",
  "command": "nix build .#ai-stack-gfx110x",
  "group": "build",
  "detail": "Build complete AI stack for gfx110X-all"
}
```

---

#### Step 5: Create Validation Script

**Create `tools/validate-gfx110x.sh`**:
```bash
#!/usr/bin/env bash
# tools/validate-gfx110x.sh - gfx110X-all runtime validation suite

set -euo pipefail
IFS=$'\n\t'

ROCM_PATH="${ROCM_PATH:-/opt/rocm}"
ARTIFACTS_PATH="${ARTIFACTS_PATH:-$(dirname "$0")/../artifacts}"

echo "=========================================="
echo "gfx110X-all (RDNA3) Runtime Validation"
echo "Date: $(date)"
echo "ROCm Path: $ROCM_PATH"
echo "=========================================="
echo ""

# ============================================================================
# PHASE 1: Bitcode Verification
# ============================================================================
echo "🔍 PHASE 1: Bitcode Verification"
if [ ! -f "$ROCM_PATH/amdgcn/bitcode/ocml.bc" ]; then
  echo "❌ FAIL: Missing ocml.bc bitcode file"
  exit 1
fi
echo "✓ ocml.bc exists"

# Check for gfx110X intrinsics
if command -v llvm-dis &>/dev/null; then
  if llvm-dis "$ROCM_PATH/amdgcn/bitcode/ocml.bc" 2>/dev/null | grep -qE "gfx110[0-3]"; then
    echo "✓ gfx110X intrinsics detected in bitcode"
  else
    echo "⚠️  WARNING: gfx110X intrinsics not found in bitcode"
  fi
else
  echo "⚠️  llvm-dis not available - skipping bitcode inspection"
fi
echo ""

# ============================================================================
# PHASE 2: PyTorch Device Detection
# ============================================================================
echo "🔍 PHASE 2: PyTorch Device Detection"
if [ ! -f "$ARTIFACTS_PATH/pytorch/bin/python3" ]; then
  echo "❌ FAIL: PyTorch not built"
  exit 1
fi

"$ARTIFACTS_PATH/pytorch/bin/python3" <<'EOF' || { echo "❌ PyTorch validation failed"; exit 1; }
import torch
import sys

if not torch.cuda.is_available():
    print("❌ FAIL: ROCm not detected by PyTorch")
    sys.exit(1)

print(f"✓ PyTorch {torch.__version__} with ROCm detected")
print(f"✓ GPU: {torch.cuda.get_device_name(0)}")

# Verify gfx11xx architecture
gpu_name = torch.cuda.get_device_name(0).lower()
if "gfx11" not in gpu_name:
    print(f"❌ FAIL: Expected gfx11xx GPU, got: {gpu_name}")
    sys.exit(1)

print("✅ gfx110X GPU validated")
EOF

echo ""
echo "=========================================="
echo "✅ gfx110X-all Validation PASSED"
echo "=========================================="
```

Make executable:
```bash
chmod +x tools/validate-gfx110x.sh
```

---

### 4.3 Documentation Updates

#### Update `README.md` (lines 21, 44, etc.):

**Add variant section**:
```markdown
### GPU Target Support

TheRockBuilder supports two GPU target variants:

| Variant | GPU Target | Description | Best For |
|---------|-----------|-------------|----------|
| **gfx1151** | AMD Strix Halo (Radeon 890M) | Latest Strix architecture with UMA optimizations | Ryzen AI Max laptops |
| **gfx110x-all** | RDNA3 family (RX 7000 series) | Full RDNA3 support (gfx1100, gfx1101, gfx1102, gfx1103) | Desktop RX 7900 XTX/XT, 7800 XT, etc. |

**Building a specific variant**:
```bash
# Build for gfx1151 (default)
nix build .#ai-stack-gfx1151

# Build for gfx110X-all (RDNA3)
nix build .#ai-stack-gfx110x
```
```

---

#### Update `HOW-TO.md`:

**Replace line 21**:
```markdown
# OLD:
- GPU: AMD Strix Halo (gfx1151) - Radeon 890M integrated

# NEW:
- GPU: AMD Strix Halo (gfx1151) or RDNA3 (gfx110X-all)
  - gfx1151: Radeon 890M (Ryzen AI Max)
  - gfx110X: RX 7900 XTX, 7900 XT, 7800 XT, 7700 XT, etc.
```

**Add variant selection section after Prerequisites**:
```markdown
## Selecting Your GPU Variant

TheRockBuilder supports two build variants:

### gfx1151 (Default)
- **Target**: AMD Strix Halo (Ryzen AI Max)
- **Optimizations**: Unified memory access (UMA), LPDDR5X tuning
- **Build command**: `nix build .#ai-stack-gfx1151`

### gfx110X-all
- **Target**: RDNA3 desktop GPUs (RX 7000 series)
- **Performance**: 2-6X faster kernels than gfx1151
- **Build command**: `nix build .#ai-stack-gfx110x`

To check your GPU architecture:
```bash
rocminfo | grep "Name:"
# Look for gfx1151 or gfx1100/gfx1101/gfx1102/gfx1103
```
```

**Update line 619** (FAQ):
```markdown
# OLD:
A: Yes, but you need to change `gfx1151` to your architecture (e.g., `gfx1030` for RX 6000 series). Ask Opus to update all `AMDGPU_TARGETS` references.

# NEW:
A: TheRockBuilder v6.1+ supports two variants out of the box:
- gfx1151: For AMD Strix Halo (Ryzen AI Max)
- gfx110X-all: For RDNA3 (RX 7900/7800/7700 series)

For other GPUs (e.g., RX 6000 series = gfx1030), you'll need to create a custom variant:
1. Duplicate `rocm-overlay-gfx110x.nix`
2. Replace AMDGPU_TARGETS with your architecture
3. Update flake.nix to expose the new variant
```

---

#### Update `PRD_v6.0.md`:

**Update Section 2.3 (Target Platform)**:
```markdown
### 2.3 Target Platform

TheRockBuilder supports two GPU variants:

#### Variant 1: gfx1151 (AMD Strix Halo)
- **Platform**: GMKtec EVO-X2
- **Architecture**: gfx1151 (AMD Strix Halo)
- **Memory**: 128GB LPDDR5X unified memory
- **Kernel**: Linux 6.18.6 (XNACK retry support required)
- **GPU**: Radeon 890M integrated (gfx1151)
- **Optimizations**: UMA-aware, SDMA disabled for stability

#### Variant 2: gfx110X-all (RDNA3 Desktop)
- **Architecture**: gfx1100, gfx1101, gfx1102, gfx1103
- **GPU Examples**: RX 7900 XTX, 7900 XT, 7800 XT, 7700 XT
- **Memory**: Dedicated VRAM (24GB typical)
- **Performance**: 2-6X faster compute kernels than gfx1151
- **Optimizations**: Full RCCL support, native gfx110X kernels
```

---

### 4.4 Build Flow Comparison

#### Current (gfx1151 Only):
```
User → nix build .#ai-stack
       ↓
     flake.nix (packages.default)
       ↓
     rocm-overlay.nix (gfx1151 targets)
       ↓
     ROCm 7.2.0 + PyTorch + vLLM
       ↓
     gfx1151-specific patches (vLLM workarounds)
       ↓
     Result (gfx1151 binaries)
```

#### Proposed (Dual Variant):
```
User → nix build .#ai-stack-gfx1151  OR  nix build .#ai-stack-gfx110x
         ↓                                    ↓
       flake.nix                            flake.nix
       (gfx1151 packages)                   (gfx110x packages)
         ↓                                    ↓
       rocm-overlay.nix                     rocm-overlay-gfx110x.nix
       (gfx1151 targets)                    (gfx110X-all targets)
         ↓                                    ↓
       gfx1151-specific patches             No workarounds needed
       (vLLM gfx1103 fallback)              (native gfx110X kernels)
         ↓                                    ↓
       Result (gfx1151 binaries)            Result (gfx110X binaries)
```

---

## 5. Testing Strategy

### 5.1 Build Validation

**Phase 1 Tests** (after each component):
```bash
# Test 1: ROCm Core
nix build .#rocm-core-gfx110x
./result/bin/rocminfo | grep -E "gfx110[0-3]"

# Test 2: PyTorch
nix build .#pytorch-rocm-gfx110x
./result/bin/python3 -c "import torch; print(torch.cuda.is_available())"

# Test 3: vLLM
nix build .#vllm-gfx110x
./result/bin/vllm --version

# Test 4: Full Stack
nix build .#ai-stack-gfx110x
```

### 5.2 Isolation Validation

Ensure gfx1151 and gfx110X builds are truly independent:
```bash
# Build both variants
nix build .#ai-stack-gfx1151 -o result-gfx1151
nix build .#ai-stack-gfx110x -o result-gfx110x

# Verify different derivations
diff <(nix path-info .#ai-stack-gfx1151) <(nix path-info .#ai-stack-gfx110x)
# Should show different store paths

# Verify AMDGPU_TARGETS in binaries
strings result-gfx1151/bin/rocminfo | grep -i "gfx1151"
strings result-gfx110x/bin/rocminfo | grep -iE "gfx110[0-3]"
```

### 5.3 Performance Comparison

```bash
# Benchmark kernel performance (requires actual hardware)
./tools/validate-gfx1151.sh   # On Strix Halo hardware
./tools/validate-gfx110x.sh   # On RDNA3 hardware

# Compare build times
time nix build .#ai-stack-gfx1151
time nix build .#ai-stack-gfx110x
# Expected: Similar (mostly compile time, not target-dependent)
```

---

## 6. Potential Issues & Mitigations

### 6.1 Known Issues

| Issue | Severity | Impact | Mitigation |
|-------|----------|--------|------------|
| **vLLM gfx1103 fallback removed** | LOW | gfx110X gets native kernels (better performance) | None needed |
| **RCCL re-enabled** | MEDIUM | Distributed training works on gfx110X | Test multi-GPU scenarios |
| **UMA optimizations disabled** | LOW | gfx110X doesn't need UMA (dedicated VRAM) | Expected behavior |
| **Build time doubles** | LOW | Two full variants require 2X storage | Cache in /nix/store |
| **Flake lock complexity** | LOW | Single flake.lock covers both | No change needed |

---

### 6.2 Validation Checklist

Before merging to main:
- [ ] gfx1151 variant still builds successfully
- [ ] gfx1151 validation script passes (tools/validate-gfx1151.sh)
- [ ] gfx110X variant builds successfully
- [ ] gfx110X validation script passes (tools/validate-gfx110x.sh)
- [ ] Both variants have different /nix/store paths
- [ ] No NVIDIA contamination in either variant
- [ ] Documentation updated (README, HOW-TO, PRD)
- [ ] VS Code tasks work for both variants
- [ ] Policy checks pass for both variants
- [ ] SBOM generation works for both variants

---

## 7. Risk Assessment

### 7.1 Risk Matrix

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **Breaking gfx1151 build** | LOW | HIGH | Create git branch before changes, test gfx1151 first |
| **gfx110X performance worse than expected** | MEDIUM | MEDIUM | Benchmark early, adjust patches if needed |
| **Build cache invalidation** | HIGH | LOW | Expected (new derivations), user accepts longer first build |
| **Documentation drift** | MEDIUM | LOW | Update all docs atomically with code |
| **Policy enforcement failure** | LOW | MEDIUM | Test policy checks explicitly |
| **Storage exhaustion** | MEDIUM | MEDIUM | Warn users about 2X storage requirement |

---

### 7.2 Rollback Plan

If gfx110X variant fails:
1. **Git rollback**: `git revert <commit>`
2. **Remove overlay**: Delete `rocm-overlay-gfx110x.nix`
3. **Remove tasks**: Delete gfx110X tasks from `.vscode/tasks.json`
4. **Nix garbage collect**: `nix-collect-garbage -d` to free space

**Recovery time**: <30 minutes

---

## 8. Implementation Timeline

### 8.1 Quick Validation Path (Recommended First)

| Phase | Tasks | Time | Cumulative |
|-------|-------|------|------------|
| **Prep** | Read this document, create git branch | 30 min | 0.5h |
| **Copy & Modify** | Create rocm-overlay-gfx110x.nix | 1.5h | 2h |
| **Flake Updates** | Add packages, overlays, tasks | 1h | 3h |
| **First Build** | `nix build .#rocm-core-gfx110x` | 2-3h | 5-6h |
| **Testing** | Validate both variants | 1h | 6-7h |
| **Documentation** | Update README, HOW-TO, PRD | 1h | 7-8h |
| **Review & Polish** | Check for issues, cleanup | 30 min | 7.5-8.5h |

**Total**: 1 day (8-9 hours) for experienced Nix developer

---

### 8.2 Refactoring Path (Long-Term)

| Phase | Tasks | Time | Cumulative |
|-------|-------|------|------------|
| **Phase 1** | Quick validation (above) | 8h | 8h |
| **Phase 2** | Extract to lib/rocm-builder.nix | 3h | 11h |
| **Phase 3** | Consolidate overlays | 2h | 13h |
| **Phase 4** | Add gfx1030 variant (RX 6000 series) | 2h | 15h |
| **Phase 5** | Integration tests | 2h | 17h |
| **Phase 6** | CI/CD setup (optional) | 3h | 20h |

**Total**: 2.5 days (20 hours) for production-ready multi-variant system

---

## 9. Maintenance Considerations

### 9.1 Future Additions

**Adding a third variant (e.g., gfx1030 for RX 6000 series)**:

With **Option A (parameterization)**: 2-3 hours
- Add entry to `lib/rocm-builder.nix`
- Update flake.nix packages
- Create validation script

With **Option B (separate overlays)**: 6-8 hours
- Duplicate overlay file (3rd time)
- Update flake.nix
- High maintenance burden

**Recommendation**: If planning >2 variants, invest in parameterization (Option A).

---

### 9.2 Upstream Compatibility

**ROCm 7.2.0 → 7.3.0 upgrade**:
- Both overlays need updates
- Test both variants independently
- Policy check must allow 7.3.0

**PyTorch 2.10.0 → 2.11.0 upgrade**:
- May require new AMDGPU_TARGETS (gfx110X improvements)
- Test vLLM compatibility with both variants

---

## 10. Conclusion & Recommendation

### 10.1 Summary

Creating a gfx110X-all variant is **LOW RISK, MODERATE EFFORT**:
- ✅ Clean architecture supports this naturally
- ✅ Most changes are mechanical search/replace
- ✅ Independent overlays prevent cross-contamination
- ✅ Documentation is comprehensive and well-structured

**Recommended Approach**: 
1. **Start with Option B** (separate overlays) for quick validation (1 day)
2. **Refactor to Option A** (parameterization) if planning more variants (1-2 days additional)

---

### 10.2 Expected Benefits

**For gfx110X users**:
- ✅ **2-6X faster kernels** (per user requirement)
- ✅ Native RDNA3 support (no gfx1103 fallbacks)
- ✅ RCCL enabled (distributed training works)
- ✅ Better vLLM performance

**For gfx1151 users**:
- ✅ **Zero impact** to existing builds
- ✅ Continued UMA optimizations
- ✅ Same stability guarantees

**For developers**:
- ✅ Easy to add more variants
- ✅ Clear separation of concerns
- ✅ Maintainable codebase

---

### 10.3 Next Steps

**Immediate**:
1. Create git branch: `git checkout -b feature/gfx110x-variant`
2. Copy overlay: `cp rocm-overlay.nix rocm-overlay-gfx110x.nix`
3. Follow Section 4.2 step-by-step

**After validation**:
4. Test both variants on actual hardware
5. Benchmark performance difference
6. Update documentation
7. Create PR for review

**Long-term**:
8. Consider parameterization refactor
9. Add CI/CD for both variants
10. Expand to gfx1030 (RX 6000) if needed

---

## Appendix A: Quick Reference Commands

```bash
# Build Commands
nix build .#rocm-core-gfx1151        # Original variant
nix build .#rocm-core-gfx110x        # New variant
nix build .#ai-stack-gfx1151         # Full stack (gfx1151)
nix build .#ai-stack-gfx110x         # Full stack (gfx110X-all)

# Validation
./tools/validate-gfx1151.sh          # Test gfx1151 build
./tools/validate-gfx110x.sh          # Test gfx110X build

# Comparison
nix path-info .#ai-stack-gfx1151     # Show derivation path
nix path-info .#ai-stack-gfx110x     # Should differ

# Cleanup
nix-collect-garbage -d               # Remove old builds
```

---

## Appendix B: File Checklist

**Critical Files (MUST modify)**:
- [ ] `rocm-overlay-gfx110x.nix` (create new)
- [ ] `flake.nix` (add packages & overlays)
- [ ] `policy/rocm-policy.json` (update allowed targets)

**Documentation (SHOULD update)**:
- [ ] `README.md` (add variant section)
- [ ] `HOW-TO.md` (GPU selection guide)
- [ ] `PRD_v6.0.md` (target platform section)
- [ ] `rocm_fresh_build_v_next_prd_opus_4.md` (Pass A update)

**Optional**:
- [ ] `.vscode/tasks.json` (add variant tasks)
- [ ] `tools/validate-gfx110x.sh` (create new)
- [ ] `AGENTS.md` (update AI guidelines)

---

**Document Version**: 1.0  
**Last Updated**: January 27, 2026  
**Next Review**: After Phase 1 completion
