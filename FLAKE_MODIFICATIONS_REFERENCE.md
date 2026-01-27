# flake.nix Modifications for Dual-Target Support

**Status**: Implementation Guide  
**Version**: 6.1+  
**Date**: January 27, 2026

---

## Overview

This document provides the complete, production-ready modifications to `flake.nix` to enable dual-target support (gfx110X-all + gfx1151).

**Strategy**: Parametric build functions with target-aware overlays

**Key Changes**:
1. Import lib/targets.nix
2. Create target-aware overlay function
3. Parameterize all ROCm-dependent packages
4. Duplicate package definitions with target suffixes
5. Update default to gfx110x

---

## Step 1: Add Target Import (Line ~40)

**Location**: After `outputs = { self, nixpkgs, ... }:` declaration, in the `let` block

**Add this import**:

```nix
outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils, ... }:
  flake-utils.lib.eachDefaultSystem (system:
    let
      # ========================================================================
      # TARGET CONFIGURATION - Import dual-target definitions
      # ========================================================================
      targetLib = import ./lib/targets.nix;
      
      # Helper function to create target-specific pkgs with custom overlay
      mkTargetPkgs = targetName: let
        target = targetLib.targets.${targetName};
        targetOverlay = import ./rocm-overlay.nix { inherit target; };
      in import nixpkgs {
        inherit system;
        overlays = [ 
          self.overlays.default 
          (final: prev: {
            # Base ROCm 7.x on unstable nixpkgs to get modern LLVM/Clang
            rocmPackages = (import nixpkgs-unstable { 
              inherit system; 
              config = { 
                allowUnfree = true; 
                allowBroken = true;
              }; 
            }).rocmPackages;
          })
          targetOverlay
        ];
        config = {
          allowUnfree = true;
          allowBroken = true;
        };
      };
      
      # Create pkgs instances for both targets
      pkgs-gfx110x = mkTargetPkgs "gfx110x";
      pkgs-gfx1151 = mkTargetPkgs "gfx1151";
      
      # Default pkgs (gfx110x for best performance)
      pkgs = pkgs-gfx110x;
```

---

## Step 2: Update rocm-overlay.nix Import

**Current Code** (around line 40-60):
```nix
pkgs = import nixpkgs {
  inherit system;
  overlays = [ 
    self.overlays.default 
    (final: prev: { /* ... */ })
    (import ./rocm-overlay.nix)  # ← REPLACE THIS LINE
  ];
```

**New Code**:
```nix
# REMOVE the old static overlay import
# (import ./rocm-overlay.nix)

# REPLACE with the mkTargetPkgs function shown in Step 1
```

---

## Step 3: Modify rocm-overlay.nix to Accept Target Parameter

**File**: `rocm-overlay.nix`

**Current signature**:
```nix
# rocm-overlay.nix
final: prev: {
  # ... packages ...
}
```

**New signature**:
```nix
# rocm-overlay.nix - Target-aware overlay for TheRockBuilder v6.1+
{ target }:  # ← Accept target parameter

final: prev: let
  # Extract target-specific configuration
  rocmTargets = target.rocmTargets;
  cmakeFlags = target.cmakeFlags;
  targetName = target.name;
in {
  # ... rest of overlay using target.* ...
}
```

**Update all hardcoded gfx1151 references**:

Replace:
```nix
AMDGPU_TARGETS = "gfx1151";
```

With:
```nix
AMDGPU_TARGETS = rocmTargets;  # Uses target.rocmTargets parameter
```

---

## Step 4: Duplicate All ROCm-Dependent Packages

**Pattern**: Every package that depends on ROCm needs two variants:
- `package-name-gfx110x` (new)
- `package-name-gfx1151` (preserves existing behavior)

**Helper Function** (add after `mkTargetPkgs`):

```nix
# Helper to create target-specific packages
mkTargetPackages = pkgsTarget: targetName: {
  # ROCm Core
  rocm-core = pkgsTarget.buildEnv {
    name = "rocm-core-7.2.0-${targetName}";
    paths = with pkgsTarget.rocmPackages; [
      rocm-cmake
      rocm-runtime
      clr
      rocm-comgr
      rocm-device-libs
      rocminfo
      rocm-smi
    ];
  };
  
  # NumPy
  numpy = pkgsTarget.python3Packages.numpy.override {
    blas = pkgsTarget.rocmPackages.rocblas;
  };
  
  # PyTorch
  pytorch-rocm = pkgsTarget.python3Packages.pytorch.override {
    rocmSupport = true;
    cudaSupport = false;
    # Target-specific RCCL handling
    enableRCCL = targetLib.targets.${targetName}.patches.pytorch.enableRCCL;
  };
  
  # TorchVision
  torchvision = pkgsTarget.python3Packages.torchvision.override {
    pytorch = self.packages.${system}."pytorch-rocm-${targetName}";
  };
  
  # Torchaudio
  torchaudio = pkgsTarget.python3Packages.torchaudio.override {
    pytorch = self.packages.${system}."pytorch-rocm-${targetName}";
  };
  
  # FlashAttention-2
  flash-attention = pkgsTarget.python3Packages.buildPythonPackage rec {
    pname = "flash-attn-${targetName}";
    version = "2.7.3";
    
    buildInputs = with pkgsTarget; [
      python3Packages.torch
      rocmPackages.clr
      rocmPackages.rocm-cmake
    ];
    
    # Target-specific GPU flags
    AMDGPU_TARGETS = targetLib.targets.${targetName}.rocmTargets;
  };
  
  # xFormers
  xformers = pkgsTarget.python3Packages.buildPythonPackage rec {
    pname = "xformers-${targetName}";
    version = "0.0.30";
    
    buildInputs = [
      self.packages.${system}."pytorch-rocm-${targetName}"
      pkgsTarget.rocmPackages.rocm-cmake
    ];
    
    AMDGPU_TARGETS = targetLib.targets.${targetName}.rocmTargets;
  };
  
  # vLLM
  vllm = pkgsTarget.python3Packages.buildPythonPackage rec {
    pname = "vllm-${targetName}";
    version = "0.14.0";
    
    buildInputs = [
      self.packages.${system}."pytorch-rocm-${targetName}"
      pkgsTarget.rocmPackages.hipblas
      pkgsTarget.rocmPackages.rocrand
    ];
    
    # Target-specific vLLM config
    preConfigure = ''
      export AMDGPU_TARGETS="${targetLib.targets.${targetName}.rocmTargets}"
      ${if targetLib.targets.${targetName}.patches.vllm.disableGfx1103Fallback 
        then ""
        else "export VLLM_TARGET_GFX=gfx1103"}
    '';
  };
  
  # llama.cpp GPU
  llamacpp-gpu = pkgsTarget.stdenv.mkDerivation rec {
    pname = "llama.cpp-rocm-${targetName}";
    version = "2024-12-20";
    
    cmakeFlags = [
      "-DLLAMA_HIPBLAS=ON"
      "-DLLAMA_ROCM=ON"
      "-DAMDGPU_TARGETS=${targetLib.targets.${targetName}.rocmTargets}"
    ];
    
    buildInputs = with pkgsTarget.rocmPackages; [
      clr
      hipblas
      rocblas
    ];
  };
  
  # DeepSpeed (Zen 2 safe - no GPU targets needed)
  deepspeed = pkgsTarget.python3Packages.deepspeed.override {
    pytorch = self.packages.${system}."pytorch-rocm-${targetName}";
  };
  
  # Bitsandbytes
  bitsandbytes = pkgsTarget.python3Packages.buildPythonPackage rec {
    pname = "bitsandbytes-${targetName}";
    version = "0.44.1";
    
    buildInputs = [
      pkgsTarget.rocmPackages.clr
      pkgsTarget.rocmPackages.hipblas
    ];
    
    AMDGPU_TARGETS = targetLib.targets.${targetName}.rocmTargets;
  };
  
  # llama.cpp CPU (no target dependency)
  llamacpp-cpu = pkgsTarget.stdenv.mkDerivation rec {
    pname = "llama.cpp-cpu";
    version = "2024-12-20";
    
    cmakeFlags = [
      "-DLLAMA_NATIVE=OFF"
      "-DLLAMA_AVX512=OFF"  # Zen 2 safety
    ];
  };
  
  # ONNX Runtime (Zen 2 safe)
  onnxruntime = pkgsTarget.onnxruntime.override {
    rocmSupport = true;
    cudaSupport = false;
  };
  
  # Complete AI Stack
  ai-stack = pkgsTarget.buildEnv {
    name = "theRockBuilder-ai-stack-v6.1-${targetName}";
    paths = [
      self.packages.${system}."rocm-core-${targetName}"
      self.packages.${system}."numpy-${targetName}"
      self.packages.${system}."pytorch-rocm-${targetName}"
      self.packages.${system}."torchvision-${targetName}"
      self.packages.${system}."torchaudio-${targetName}"
      self.packages.${system}."flash-attention-${targetName}"
      self.packages.${system}."xformers-${targetName}"
      self.packages.${system}."deepspeed-${targetName}"
      self.packages.${system}."bitsandbytes-${targetName}"
      self.packages.${system}."vllm-${targetName}"
      self.packages.${system}."llamacpp-gpu-${targetName}"
      self.packages.${system}."llamacpp-cpu-${targetName}"
      self.packages.${system}."onnxruntime-${targetName}"
    ];
    
    postBuild = ''
      echo "🧪 Validating ${targetName} AI stack..."
      ${self.packages.${system}.dependency-auditor}/bin/audit-dependencies $out
      echo "✅ TheRockBuilder v6.1 AI Stack (${targetName}) ready"
    '';
  };
};
```

---

## Step 5: Update packages.x86_64-linux

**Replace the entire `packages = { ... }` block**:

```nix
packages = 
  # Generate all packages for both targets
  let
    gfx110xPkgs = mkTargetPackages pkgs-gfx110x "gfx110x";
    gfx1151Pkgs = mkTargetPackages pkgs-gfx1151 "gfx1151";
  in
  {
    # ==========================================================================
    # DEFAULT - Points to gfx110x for best performance
    # ==========================================================================
    default = self.packages.${system}.ai-stack-gfx110x;
    
    # ==========================================================================
    # GFX110X (RDNA 3) VARIANTS - NEW DEFAULT
    # ==========================================================================
    inherit (gfx110xPkgs)
      rocm-core-gfx110x
      numpy-gfx110x
      pytorch-rocm-gfx110x
      torchvision-gfx110x
      torchaudio-gfx110x
      flash-attention-gfx110x
      xformers-gfx110x
      deepspeed-gfx110x
      bitsandbytes-gfx110x
      vllm-gfx110x
      llamacpp-gpu-gfx110x
      llamacpp-cpu-gfx110x
      onnxruntime-gfx110x
      ai-stack-gfx110x;
    
    # Convenience aliases without suffix (point to gfx110x)
    rocm-core = gfx110xPkgs.rocm-core-gfx110x;
    numpy = gfx110xPkgs.numpy-gfx110x;
    pytorch-rocm = gfx110xPkgs.pytorch-rocm-gfx110x;
    vllm = gfx110xPkgs.vllm-gfx110x;
    ai-stack = gfx110xPkgs.ai-stack-gfx110x;
    
    # ==========================================================================
    # GFX1151 (STRIX HALO) VARIANTS - Preserved for UMA systems
    # ==========================================================================
    inherit (gfx1151Pkgs)
      rocm-core-gfx1151
      numpy-gfx1151
      pytorch-rocm-gfx1151
      torchvision-gfx1151
      torchaudio-gfx1151
      flash-attention-gfx1151
      xformers-gfx1151
      deepspeed-gfx1151
      bitsandbytes-gfx1151
      vllm-gfx1151
      llamacpp-gpu-gfx1151
      llamacpp-cpu-gfx1151
      onnxruntime-gfx1151
      ai-stack-gfx1151;
    
    # ==========================================================================
    # SHARED UTILITIES (Target-independent)
    # ==========================================================================
    gcc14 = pkgs.gcc14;
    dependency-auditor = /* ... keep existing ... */;
    build-orchestrator = /* ... keep existing ... */;
    binary-scanner = /* ... keep existing ... */;
    sbom-generator = /* ... keep existing ... */;
    integration-test = /* ... keep existing ... */;
    bundle-creator = /* ... keep existing ... */;
    zen2-safety-audit = /* ... keep existing ... */;
    model-manager = /* ... keep existing ... */;
    
    # NEW: Target-aware build wrapper
    build-with-target = pkgs.writeShellScriptBin "build-with-target" ''
      exec ${./scripts/build-with-target.sh} "$@"
    '';
  };
```

---

## Step 6: Update devShells

**Modify shellHook to mention dual-target support**:

```nix
devShells.default = pkgs.mkShell {
  buildInputs = [ /* ... keep existing ... */ ];
  
  shellHook = ''
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  TheRockBuilder v6.1+ Dual-Target Development Shell      ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "🎯 Available Targets:"
    echo "   gfx110x (RDNA3)    - RX 7900/7800/7700 series (DEFAULT)"
    echo "   gfx1151 (Strix)    - Ryzen AI Max+ 395"
    echo ""
    echo "🏗️  Build Commands (gfx110x):"
    echo "   build-rocm-110x    - Build ROCm core for RDNA3"
    echo "   build-pytorch-110x - Build PyTorch for RDNA3"
    echo "   build-all-110x     - Full AI stack for RDNA3"
    echo ""
    echo "🏗️  Build Commands (gfx1151):"
    echo "   build-rocm-1151    - Build ROCm core for Strix Halo"
    echo "   build-pytorch-1151 - Build PyTorch for Strix Halo"
    echo "   build-all-1151     - Full AI stack for Strix Halo"
    echo ""
    echo "🔧 Universal Build Tool:"
    echo "   build-with-target <target> <component>"
    echo "   Example: build-with-target gfx110x pytorch-rocm"
    echo ""
    echo "See TARGETS.md for detailed usage guide"
    echo ""
    
    # Target-specific aliases
    alias build-rocm-110x='nix build .#rocm-core-gfx110x'
    alias build-pytorch-110x='nix build .#pytorch-rocm-gfx110x'
    alias build-all-110x='nix build .#ai-stack-gfx110x'
    
    alias build-rocm-1151='nix build .#rocm-core-gfx1151'
    alias build-pytorch-1151='nix build .#pytorch-rocm-gfx1151'
    alias build-all-1151='nix build .#ai-stack-gfx1151'
    
    # Keep existing aliases for backward compat (point to gfx110x)
    alias build-rocm='nix build .#rocm-core-gfx110x'
    alias build-pytorch='nix build .#pytorch-rocm-gfx110x'
    alias build-all='nix build .#ai-stack-gfx110x'
    
    # ... rest of shellHook ...
  '';
};
```

---

## Step 7: Update policy/rocm-policy.json

**File**: `policy/rocm-policy.json`

**Add gfx110X targets to allowed list**:

```json
{
  "version": "1.0",
  "gpu_targets": {
    "pass_a": {
      "allowed": [
        "gfx1151",
        "gfx900",
        "gfx906",
        "gfx908",
        "gfx90a",
        "gfx1030",
        "gfx1100",
        "gfx1101",
        "gfx1102",
        "gfx1103"
      ],
      "forbidden": ["gfx803", "gfx900:xnack-"]
    }
  }
}
```

---

## Complete Example: Minimal Working flake.nix

For reference, here's a minimal working example showing the key structure:

```nix
{
  description = "TheRockBuilder v6.1+ - Dual-Target AMD ROCm AI Stack";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Import target configuration
        targetLib = import ./lib/targets.nix;
        
        # Helper to create target-specific pkgs
        mkTargetPkgs = targetName: let
          target = targetLib.targets.${targetName};
          targetOverlay = import ./rocm-overlay.nix { inherit target; };
        in import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default targetOverlay ];
          config = { allowUnfree = true; allowBroken = true; };
        };
        
        # Create pkgs for each target
        pkgs-gfx110x = mkTargetPkgs "gfx110x";
        pkgs-gfx1151 = mkTargetPkgs "gfx1151";
        pkgs = pkgs-gfx110x;  # Default
        
        # Build packages for a target
        mkTargetPackages = pkgsTarget: targetName: {
          "rocm-core-${targetName}" = /* ... */;
          "pytorch-rocm-${targetName}" = /* ... */;
          "ai-stack-${targetName}" = /* ... */;
        };
        
        gfx110xPkgs = mkTargetPackages pkgs-gfx110x "gfx110x";
        gfx1151Pkgs = mkTargetPackages pkgs-gfx1151 "gfx1151";
        
      in {
        packages = {
          default = gfx110xPkgs."ai-stack-gfx110x";
          
          # All gfx110x packages
          inherit (gfx110xPkgs) ai-stack-gfx110x rocm-core-gfx110x pytorch-rocm-gfx110x;
          
          # All gfx1151 packages
          inherit (gfx1151Pkgs) ai-stack-gfx1151 rocm-core-gfx1151 pytorch-rocm-gfx1151;
          
          # Aliases (point to gfx110x)
          ai-stack = gfx110xPkgs."ai-stack-gfx110x";
          rocm-core = gfx110xPkgs."rocm-core-gfx110x";
        };
      }
    ) // {
      overlays.default = /* ... NVIDIA isolation ... */;
    };
}
```

---

## Validation Checklist

After modifications:

```bash
# 1. Check syntax
nix flake check

# 2. Verify targets exist
nix eval .#lib.targets --apply 'builtins.attrNames'
# Expected: [ "gfx110x" "gfx1151" ]

# 3. List all packages
nix flake show
# Should see both -gfx110x and -gfx1151 variants

# 4. Test build (quick)
nix build .#rocm-core-gfx110x --dry-run
nix build .#rocm-core-gfx1151 --dry-run

# 5. Verify they're different
nix path-info .#rocm-core-gfx110x
nix path-info .#rocm-core-gfx1151
# Store paths must be different!

# 6. Run full validation
./scripts/validate-targets.sh
```

---

## Testing Both Targets

```bash
# Build ROCm for both targets
nix build .#rocm-core-gfx110x
nix build .#rocm-core-gfx1151

# Build PyTorch for both
nix build .#pytorch-rocm-gfx110x
nix build .#pytorch-rocm-gfx1151

# Build complete stacks
nix build .#ai-stack-gfx110x
nix build .#ai-stack-gfx1151

# Verify independence
./tools/validate-gfx110x.sh $(nix build --print-out-paths .#ai-stack-gfx110x)
```

---

## Estimated Timeline

| Phase | Task | Duration |
|-------|------|----------|
| 1 | Modify flake.nix (Steps 1-2) | 1 hour |
| 2 | Update rocm-overlay.nix (Step 3) | 1 hour |
| 3 | Create mkTargetPackages (Step 4) | 2 hours |
| 4 | Update packages block (Step 5) | 1 hour |
| 5 | Testing & validation | 2 hours |
| **Total** | **Implementation** | **7 hours** |
| **Build** | First full build (both targets) | **16-24 hours** |

---

## Troubleshooting

### "Target not found"
```bash
# Check if target exists
nix eval .#lib.targets.gfx110x --raw
```

### "Hash mismatch"
```bash
# Update source hash
nix-prefetch-url <URL>
# Copy new hash to flake.nix
```

### "Different store paths expected"
```bash
# Verify AMDGPU_TARGETS differ
nix eval .#lib.targets.gfx110x.rocmTargets --raw
nix eval .#lib.targets.gfx1151.rocmTargets --raw
```

---

**Next Steps**: 
1. Backup current flake.nix: `cp flake.nix flake.nix.backup`
2. Apply modifications from Steps 1-6
3. Run validation checklist
4. Test with `nix build .#rocm-core-gfx110x`

**See Also**:
- [TARGETS.md](TARGETS.md) - User guide for target selection
- [lib/targets.nix](lib/targets.nix) - Target configuration reference
- [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) - Full implementation status
