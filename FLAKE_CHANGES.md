# Flake.nix Modifications for Dual-Target Support

**Target**: Add gfx110X-all variant support to TheRockBuilder v6.0+  
**Approach**: Minimal changes to existing flake.nix structure  
**Estimated LOC Changes**: ~200 lines added, 10 lines modified

---

## Overview

This document provides step-by-step instructions for modifying `flake.nix` to support both `gfx1151` and `gfx110x` GPU targets while preserving backward compatibility.

**Strategy**: Use conditional overlays and duplicate package definitions with target-specific suffixes.

---

## Step 1: Import Target Configuration

**Location**: Near the top of flake.nix (after imports, around line 40)

**Add**:
```nix
let
  # Import GPU target configurations
  targets = import ./lib/targets.nix;
  
  # Get active target from environment (for backward compat) or use default
  activeTargetName = builtins.getEnv "ROCM_BUILD_TARGET";
  activeTarget = if activeTargetName != ""
    then targets.${activeTargetName}
    else targets.gfx110x;  # Default to gfx110x (better performance)
in
```

**Result**: Target configuration is now available to all derivations.

---

## Step 2: Modify Overlay Selection

**Location**: Inside the `let pkgs = import nixpkgs` block (around line 42-58)

**Current**:
```nix
pkgs = import nixpkgs {
  inherit system;
  overlays = [ 
    self.overlays.default 
    (final: prev: {
      # Base ROCm 7.x on unstable nixpkgs
      rocmPackages = (import nixpkgs-unstable { 
        inherit system; 
        config = { allowUnfree = true; allowBroken = true; }; 
      }).rocmPackages;
    })
    (import ./rocm-overlay.nix) 
  ];
  config = {
    allowUnfree = true;
    allowBroken = true;
  };
};
```

**Modified**:
```nix
# Create package sets for each target
mkPkgs = targetConfig: import nixpkgs {
  inherit system;
  overlays = [ 
    self.overlays.default 
    (final: prev: {
      # Base ROCm 7.x on unstable nixpkgs
      rocmPackages = (import nixpkgs-unstable { 
        inherit system; 
        config = { allowUnfree = true; allowBroken = true; }; 
      }).rocmPackages;
    })
    # Use target-specific overlay
    (import ./rocm-overlay.nix targetConfig)
  ];
  config = {
    allowUnfree = true;
    allowBroken = true;
  };
};

# Create pkgs for each target
pkgs-gfx110x = mkPkgs targets.gfx110x;
pkgs-gfx1151 = mkPkgs targets.gfx1151;

# Default pkgs for generic package names (backward compat)
pkgs = pkgs-gfx110x;  # Default to gfx110x
```

**Result**: Two independent package sets, one for each target.

---

## Step 3: Update rocm-overlay.nix to Accept Target Parameter

**Location**: rocm-overlay.nix (create new version or modify existing)

**Add at top of rocm-overlay.nix**:
```nix
# rocm-overlay.nix
# ROCm 7.2.0 overlay with parametric GPU target support

targetConfig:  # <-- Accept target configuration as parameter

self: super:

let
  # Use target-specific configuration
  amdgpuTargets = targetConfig.rocmTargets;
  
  # Component-specific patches
  patches = targetConfig.patches;
  
  # ... rest of overlay
in
{
  # All the existing overlay content, but using targetConfig instead of hardcoded values
  # Replace hardcoded AMDGPU_TARGETS with ${amdgpuTargets}
}
```

**Alternative (simpler)**: Create two separate overlay files:
- `rocm-overlay-gfx110x.nix` (with gfx110X targets)
- `rocm-overlay-gfx1151.nix` (with gfx1151 targets)

Then in flake.nix:
```nix
# For gfx110x
overlays = [ ... (import ./rocm-overlay-gfx110x.nix) ];

# For gfx1151
overlays = [ ... (import ./rocm-overlay-gfx1151.nix) ];
```

---

## Step 4: Duplicate Package Definitions with Target Suffixes

**Location**: Inside `packages = {` block (around line 68-110)

**Current**:
```nix
packages = {
  default = self.packages.${system}.ai-stack;
  
  ai-stack = pkgs.buildEnv {
    name = "theRockBuilder-ai-stack-v6.1";
    paths = [
      self.packages.${system}.rocm-core
      self.packages.${system}.pytorch-rocm
      # ... more components
    ];
  };
  
  rocm-core = /* ... derivation ... */;
  pytorch-rocm = /* ... derivation ... */;
  vllm = /* ... derivation ... */;
  # ... more packages
};
```

**Modified**:
```nix
packages = {
  # ========================================================================
  # gfx110X-all Packages (RDNA3) - DEFAULT
  # ========================================================================
  
  rocm-core-gfx110x = pkgs-gfx110x.rocmPackages.rocm-core;
  
  pytorch-rocm-gfx110x = pkgs-gfx110x.python311Packages.pytorch.override {
    # PyTorch-specific overrides for gfx110x
    rocmSupport = true;
    # RCCL enabled for gfx110x
  };
  
  vllm-gfx110x = pkgs-gfx110x.python311Packages.vllm.override {
    # vLLM gets native gfx110X kernels (no fallback needed)
    # No special patches required
  };
  
  llamacpp-gpu-gfx110x = pkgs-gfx110x.stdenv.mkDerivation {
    # llama.cpp for dedicated VRAM (no UMA)
    cmakeFlags = [
      "-DGGML_HIP=ON"
      # No UMA flag for gfx110x
    ];
  };
  
  ai-stack-gfx110x = pkgs-gfx110x.buildEnv {
    name = "theRockBuilder-ai-stack-v6.1-gfx110x";
    paths = [
      self.packages.${system}.rocm-core-gfx110x
      self.packages.${system}.numpy  # Shared (CPU-only)
      self.packages.${system}.pytorch-rocm-gfx110x
      self.packages.${system}.torchvision  # Shared
      self.packages.${system}.torchaudio  # Shared
      self.packages.${system}.flash-attention  # Shared (GPU-agnostic)
      self.packages.${system}.xformers  # Shared
      self.packages.${system}.deepspeed  # Shared (CPU-focused)
      self.packages.${system}.bitsandbytes  # Shared
      self.packages.${system}.vllm-gfx110x
      self.packages.${system}.llamacpp-gpu-gfx110x
      self.packages.${system}.llamacpp-cpu  # Shared
      self.packages.${system}.onnxruntime  # Shared
      self.packages.${system}.model-manager  # Shared
    ];
    
    postBuild = ''
      echo "🧪 Validating gfx110X-all AI stack..."
      ${self.packages.${system}.dependency-auditor}/bin/audit-dependencies $out
      echo "✅ TheRockBuilder v6.1 AI Stack ready (gfx110X-all variant)"
    '';
  };
  
  # ========================================================================
  # gfx1151 Packages (Strix Halo) - Legacy
  # ========================================================================
  
  rocm-core-gfx1151 = pkgs-gfx1151.rocmPackages.rocm-core;
  
  pytorch-rocm-gfx1151 = pkgs-gfx1151.python311Packages.pytorch.override {
    # PyTorch-specific overrides for gfx1151
    rocmSupport = true;
    # RCCL disabled for gfx1151 (broken)
  };
  
  vllm-gfx1151 = pkgs-gfx1151.python311Packages.vllm.override {
    # vLLM requires gfx1103 fallback patches for gfx1151
    # Patches applied in rocm-overlay-gfx1151.nix
  };
  
  llamacpp-gpu-gfx1151 = pkgs-gfx1151.stdenv.mkDerivation {
    # llama.cpp with UMA for Strix Halo unified memory
    cmakeFlags = [
      "-DGGML_HIP=ON"
      "-DGGML_HIP_UMA=ON"  # Enable UMA for gfx1151
    ];
  };
  
  ai-stack-gfx1151 = pkgs-gfx1151.buildEnv {
    name = "theRockBuilder-ai-stack-v6.1-gfx1151";
    paths = [
      self.packages.${system}.rocm-core-gfx1151
      self.packages.${system}.numpy  # Shared
      self.packages.${system}.pytorch-rocm-gfx1151
      self.packages.${system}.torchvision  # Shared
      self.packages.${system}.torchaudio  # Shared
      self.packages.${system}.flash-attention  # Shared
      self.packages.${system}.xformers  # Shared
      self.packages.${system}.deepspeed  # Shared
      self.packages.${system}.bitsandbytes  # Shared
      self.packages.${system}.vllm-gfx1151
      self.packages.${system}.llamacpp-gpu-gfx1151
      self.packages.${system}.llamacpp-cpu  # Shared
      self.packages.${system}.onnxruntime  # Shared
      self.packages.${system}.model-manager  # Shared
    ];
    
    postBuild = ''
      echo "🧪 Validating gfx1151 AI stack..."
      ${self.packages.${system}.dependency-auditor}/bin/audit-dependencies $out
      echo "✅ TheRockBuilder v6.1 AI Stack ready (gfx1151 variant)"
    '';
  };
  
  # ========================================================================
  # Convenience Aliases & Defaults
  # ========================================================================
  
  # Explicit target aliases
  default-gfx110x = self.packages.${system}.ai-stack-gfx110x;
  default-gfx1151 = self.packages.${system}.ai-stack-gfx1151;
  
  # Generic names (backward compatibility)
  # Default to gfx110x (better performance)
  default = self.packages.${system}.ai-stack-gfx110x;
  ai-stack = self.packages.${system}.ai-stack-gfx110x;
  rocm-core = self.packages.${system}.rocm-core-gfx110x;
  pytorch-rocm = self.packages.${system}.pytorch-rocm-gfx110x;
  vllm = self.packages.${system}.vllm-gfx110x;
  llamacpp-gpu = self.packages.${system}.llamacpp-gpu-gfx110x;
  
  # ========================================================================
  # Shared Packages (CPU-only or GPU-agnostic)
  # ========================================================================
  
  # These packages work identically for both targets
  numpy = pkgs.python311Packages.numpy;
  torchvision = pkgs.python311Packages.torchvision;
  torchaudio = pkgs.python311Packages.torchaudio;
  flash-attention = pkgs.python311Packages.flash-attn;
  xformers = pkgs.python311Packages.xformers;
  deepspeed = pkgs.python311Packages.deepspeed;
  bitsandbytes = pkgs.python311Packages.bitsandbytes;
  llamacpp-cpu = pkgs.llama-cpp;  # CPU-only, no GPU target
  onnxruntime = pkgs.python311Packages.onnxruntime;
  model-manager = pkgs.callPackage ./packages/model-manager.nix {};
  
  # ... (all other existing packages remain unchanged)
};
```

---

## Step 5: Update Flake Outputs (Optional)

**Location**: Bottom of flake.nix (around line 2100)

**Add** (if not already present):
```nix
overlays = {
  default = import ./rocm-overlay-gfx110x.nix;
  gfx110x = import ./rocm-overlay-gfx110x.nix;
  gfx1151 = import ./rocm-overlay-gfx1151.nix;
};
```

---

## Step 6: Update rocm-core Derivation (Example)

**Location**: Inside `packages = {` block, find the `rocm-core` derivation

**Current** (simplified):
```nix
rocm-core = pkgs.stdenv.mkDerivation {
  pname = "rocm-core";
  version = "7.2.0";
  
  # ... sources ...
  
  AMDGPU_TARGETS = "gfx1151";
  HSA_OVERRIDE_GFX_VERSION = "11.5.1";
  
  # ... build phases ...
};
```

**Modified** (use target-specific packages):
```nix
# This is now defined twice (see Step 4):
# rocm-core-gfx110x = pkgs-gfx110x.rocmPackages.rocm-core;
# rocm-core-gfx1151 = pkgs-gfx1151.rocmPackages.rocm-core;

# Or if building custom derivation:
rocm-core-gfx110x = pkgs-gfx110x.stdenv.mkDerivation {
  pname = "rocm-core-gfx110x";
  version = "7.2.0";
  
  # Use gfx110x target configuration
  inherit (targets.gfx110x) envVars;
  
  AMDGPU_TARGETS = targets.gfx110x.envVars.AMDGPU_TARGETS;
  # No HSA_OVERRIDE_GFX_VERSION for gfx110x
  
  # ... build phases ...
};

rocm-core-gfx1151 = pkgs-gfx1151.stdenv.mkDerivation {
  pname = "rocm-core-gfx1151";
  version = "7.2.0";
  
  # Use gfx1151 target configuration
  inherit (targets.gfx1151) envVars;
  
  AMDGPU_TARGETS = targets.gfx1151.envVars.AMDGPU_TARGETS;
  HSA_OVERRIDE_GFX_VERSION = "11.5.1";  # gfx1151-specific
  
  # ... build phases ...
};
```

---

## Summary of Changes

### Files Modified:
1. **flake.nix** (~200 lines added, 10 modified)
   - Import target configuration
   - Create dual package sets
   - Duplicate package definitions
   - Add convenience aliases

### Files Created:
1. **lib/targets.nix** (completed in previous step)
2. **rocm-overlay-gfx110x.nix** (copy of rocm-overlay.nix with gfx110X targets)
3. **rocm-overlay-gfx1151.nix** (copy of rocm-overlay.nix with gfx1151 targets)

### Backward Compatibility:
- ✅ `nix build .#ai-stack` still works (now builds gfx110x by default)
- ✅ `nix build .#rocm-core` still works (now uses gfx110x)
- ✅ Set `ROCM_BUILD_TARGET=gfx1151` to restore v6.0 behavior
- ✅ Explicit targets always available: `.#ai-stack-gfx1151`

### Testing:
```bash
# Test gfx110x (default)
nix build .#ai-stack
nix build .#ai-stack-gfx110x
nix build .#rocm-core-gfx110x

# Test gfx1151
nix build .#ai-stack-gfx1151
nix build .#rocm-core-gfx1151

# Verify independence
diff <(nix path-info .#ai-stack-gfx110x) <(nix path-info .#ai-stack-gfx1151)
# Should show different store paths
```

---

## Implementation Checklist

Before making changes:
- [ ] Create git branch: `git checkout -b feature/dual-target-support`
- [ ] Backup flake.nix: `cp flake.nix flake.nix.backup`
- [ ] Review all steps in this document

Implementation:
- [ ] Step 1: Import targets.nix
- [ ] Step 2: Create dual package sets
- [ ] Step 3: Modify rocm-overlay.nix (or create two overlay files)
- [ ] Step 4: Duplicate package definitions
- [ ] Step 5: Update flake outputs (optional)
- [ ] Step 6: Update derivations to use target configs

Testing:
- [ ] `nix flake check` passes
- [ ] `nix build .#rocm-core-gfx110x` succeeds
- [ ] `nix build .#rocm-core-gfx1151` succeeds
- [ ] `nix path-info` shows different paths for each target
- [ ] Run `./scripts/validate-targets.sh`

Documentation:
- [ ] Update README.md with target selection info
- [ ] Verify TARGETS.md is accurate
- [ ] Update HOW-TO.md with build commands

---

## Alternative: Simpler Approach (Recommended for Quick Start)

If full parameterization seems complex, use this simpler approach:

1. **Create two overlay files** (copy rocm-overlay.nix):
   ```bash
   cp rocm-overlay.nix rocm-overlay-gfx110x.nix
   cp rocm-overlay.nix rocm-overlay-gfx1151.nix
   ```

2. **Modify gfx110x overlay**:
   - Search/replace `gfx1151` → `gfx110X-all`
   - Remove gfx1151-specific workarounds (vLLM patches, RCCL disable)

3. **Keep gfx1151 overlay as-is** (current behavior)

4. **In flake.nix, create two pkgs**:
   ```nix
   pkgs-gfx110x = import nixpkgs {
     overlays = [ (import ./rocm-overlay-gfx110x.nix) ];
     # ...
   };
   
   pkgs-gfx1151 = import nixpkgs {
     overlays = [ (import ./rocm-overlay-gfx1151.nix) ];
     # ...
   };
   ```

5. **Expose both in packages**: (see Step 4 above)

This approach requires **zero refactoring** of existing code, just duplication and renaming.

---

**Next Steps**: Proceed with rocm-overlay.nix modifications (see ANALYSIS_gfx110X_variant.md Section 4.2)
