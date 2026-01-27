# lib/targets.nix
# GPU Target Configuration Abstraction for TheRockBuilder v6.0+
# 
# This module provides centralized configuration for multiple GPU target variants.
# Each target includes AMDGPU_TARGETS flags, optimization settings, and metadata.

{
  # =============================================================================
  # RDNA 3 GPU Family (gfx110X-all) - DEFAULT
  # =============================================================================
  # Covers: RX 7900 XTX, 7900 XT, 7800 XT, 7700 XT, 7600
  # Performance: 2-6X faster kernels than gfx1151
  # Status: Stable, full RCCL support, native vLLM kernels
  # =============================================================================
  gfx110x = {
    # Package naming
    name = "gfx110x";
    displayName = "gfx110X-all";
    description = "RDNA 3 GPU Family (RX 7900/7800/7700 series)";
    
    # GPU target flags for ROCm compilation
    # Includes all RDNA3 variants for maximum compatibility
    rocmTargets = "gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1101;gfx1102;gfx1103";
    rocmTargetsShort = "gfx110X-all";  # For display purposes
    
    # CMake flags for ROCm build system
    cmakeFlags = [
      "-DAMDGPU_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1101;gfx1102;gfx1103"
      "-DAMDGCN_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1101;gfx1102;gfx1103"
      "-DGCN_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1101;gfx1102;gfx1103"
    ];
    
    # Environment variables for runtime
    envVars = {
      AMDGPU_TARGETS = "gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1101;gfx1102;gfx1103";
      HIP_PLATFORM = "amd";
      # No UMA-specific flags needed (dedicated VRAM)
    };
    
    # Component-specific patches/workarounds
    patches = {
      pytorch = {
        enableRCCL = true;  # RCCL works on RDNA3
        additionalFlags = [];
      };
      vllm = {
        # No gfx1103 fallback needed - native gfx110X kernels exist
        disableGfx1103Fallback = true;
        enableRCCL = true;
      };
      llamacpp = {
        # Dedicated VRAM - no UMA optimizations needed
        enableUMA = false;
      };
    };
    
    # Validation expectations
    validation = {
      expectedGpuPattern = "gfx11[0-3][0-9]";  # Regex for rocminfo
      bitcodePattern = "gfx110[0-3]";          # Regex for LLVM bitcode
      minVramGB = 8;                           # Minimum VRAM for this target
    };
    
    # Hardware examples
    hardwareExamples = [
      "AMD Radeon RX 7900 XTX (24GB)"
      "AMD Radeon RX 7900 XT (20GB)"
      "AMD Radeon RX 7800 XT (16GB)"
      "AMD Radeon RX 7700 XT (12GB)"
      "AMD Radeon RX 7600 (8GB)"
    ];
    
    # Performance characteristics
    performance = {
      kernelSpeedVsGfx1151 = "2-6x faster";
      recommendedForDistributed = true;
      recommendedForProduction = true;
    };
    
    # Build system metadata
    defaultTarget = true;  # Make this the default variant
    stable = true;
    experimental = false;
  };
  
  # =============================================================================
  # AMD Strix Halo (gfx1151) - LEGACY
  # =============================================================================
  # Covers: Ryzen AI Max+ (Radeon 890M integrated)
  # Memory: Unified Memory Architecture (UMA) with LPDDR5X
  # Status: Stable but slower kernels, requires workarounds
  # =============================================================================
  gfx1151 = {
    # Package naming
    name = "gfx1151";
    displayName = "gfx1151";
    description = "AMD Strix Halo (Ryzen AI Max+ with Radeon 890M)";
    
    # GPU target flags - includes gfx1151 explicitly
    rocmTargets = "gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151";
    rocmTargetsShort = "gfx1151";
    
    # CMake flags
    cmakeFlags = [
      "-DAMDGPU_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151"
      "-DAMDGCN_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151"
      "-DGCN_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151"
      "-DLLVM_AMDGPU_ALLOW_NAKED_POINTER=true"  # Required for experimental gfx1151
    ];
    
    # Environment variables - UMA-specific tuning
    envVars = {
      AMDGPU_TARGETS = "gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151";
      HIP_PLATFORM = "amd";
      HSA_OVERRIDE_GFX_VERSION = "11.5.1";
      # UMA stability flags for Strix Halo
      HSA_ENABLE_SDMA = "0";  # Disable SDMA for unified memory stability
      HSA_DISABLE_GWS = "1";  # Disable Global Wave Sync
    };
    
    # Component-specific patches/workarounds
    patches = {
      pytorch = {
        enableRCCL = false;  # RCCL broken for gfx1151
        additionalFlags = [
          "-DUSE_RCCL=OFF"
        ];
      };
      vllm = {
        # vLLM 0.14.0 lacks gfx1151 kernels - force gfx1103 fallback
        disableGfx1103Fallback = false;
        enableRCCL = false;
        patchCommands = [
          "substituteInPlace cmake/ROCM.cmake --replace 'gfx1151' 'gfx1103' || true"
          "substituteInPlace CMakeLists.txt --replace 'find_package(RCCL)' '# find_package(RCCL)'"
        ];
      };
      llamacpp = {
        # Enable UMA for unified memory on Strix Halo
        enableUMA = true;
        additionalFlags = [
          "-DGGML_HIP_UMA=ON"
        ];
      };
    };
    
    # Validation expectations
    validation = {
      expectedGpuPattern = "(gfx1151|gfx1103)";  # May report as gfx1103
      bitcodePattern = "gfx1151";
      minVramGB = 16;  # Unified memory - needs significant RAM
    };
    
    # Hardware examples
    hardwareExamples = [
      "GMKtec EVO-X2 (Ryzen AI Max+ 395, 128GB unified)"
      "ASUS ROG Flow Z13 (Ryzen AI Max+)"
      "Framework Laptop 16 (Ryzen AI Max+ module)"
    ];
    
    # Performance characteristics
    performance = {
      kernelSpeedVsGfx1151 = "baseline";
      recommendedForDistributed = false;  # RCCL disabled
      recommendedForProduction = false;   # Use gfx110x instead
    };
    
    # Build system metadata
    defaultTarget = false;  # Not the default (gfx110x is faster)
    stable = true;
    experimental = true;  # gfx1151 is experimental ROCm target
  };
  
  # =============================================================================
  # Helper Functions
  # =============================================================================
  
  # Get target by name (with fallback to default)
  getTarget = targetName: targets:
    if builtins.hasAttr targetName targets
    then builtins.getAttr targetName targets
    else targets.gfx110x;  # Default to gfx110x
  
  # Get default target
  getDefault = targets:
    if targets.gfx110x.defaultTarget
    then targets.gfx110x
    else targets.gfx1151;
  
  # List all available targets
  listTargets = targets:
    builtins.attrNames targets;
  
  # Validate target name
  isValidTarget = targetName: targets:
    builtins.hasAttr targetName targets;
}
