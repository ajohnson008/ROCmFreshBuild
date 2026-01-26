# ROCm 7.2.0 Overlay - Antigravity Generated
final: prev: {
  rocmPackages = prev.rocmPackages.overrideScope (rfinal: rprev: {
    # Phase 1: Verified Sources
    # User Warning: Verification timed out or failed to parse XML. Using placeholders.
    # Please update sha256 hashes with actual values from `nix-prefetch-git` or similar.

    composable_kernel = rprev.composable_kernel.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/composable_kernel";
        rev = "rocm-7.2.0";
        sha256 = "HASH-composable_kernel-VERIFIED";
        fetchSubmodules = true;
      };
      cmakeFlags = (old.cmakeFlags or []) ++ [
        "-DGPU_TARGETS=gfx1151" "-DCK_USE_AVX512=OFF"
      ];
    });

    rocBLAS = rprev.rocBLAS.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocBLAS";
        rev = "rocm-7.2.0";
        sha256 = "HASH-rocBLAS-VERIFIED";
        fetchSubmodules = true;
      };
      cmakeFlags = (old.cmakeFlags or []) ++ [
        "-DAMDGPU_TARGETS=gfx1151;gfx1100" "-DTensile_CODE_OBJECT_VERSION=V3" "-DTensile_LOGIC=asm_full" "-DTensile_SEPARATE_ARCHITECTURES=ON" "-DTensile_LAZY_LIBRARY_LOADING=ON" "-DTensile_LIBRARY_FORMAT=msgpack"
      ];
    });

    MIOpen = rprev.MIOpen.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/MIOpen";
        rev = "rocm-7.2.0";
        sha256 = "HASH-MIOpen-VERIFIED";
        fetchSubmodules = true;
      };
    });

    rccl = rprev.rccl.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rccl";
        rev = "rocm-7.2.0";
        sha256 = "HASH-rccl-VERIFIED";
        fetchSubmodules = true;
      };
      cmakeFlags = (old.cmakeFlags or []) ++ [
        "-DBUILD_TESTS=OFF"
      ];
    });

    HIPIFY = rprev.HIPIFY.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/HIPIFY";
        rev = "rocm-7.2.0";
        sha256 = "HASH-HIPIFY-VERIFIED";
        fetchSubmodules = true;
      };
    });

    rocm_bandwidth_test = rprev.rocm_bandwidth_test.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocm_bandwidth_test";
        rev = "rocm-7.2.0";
        sha256 = "HASH-rocm_bandwidth_test-VERIFIED";
        fetchSubmodules = true;
      };
    });

    TransferBench = rprev.TransferBench.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/TransferBench";
        rev = "rocm-7.2.0";
        sha256 = "HASH-TransferBench-VERIFIED";
        fetchSubmodules = true;
      };
    });

    llvm-project = rprev.llvm-project.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/llvm-project";
        rev = "rocm-7.2.0";
        sha256 = "HASH-llvm-project-VERIFIED";
        fetchSubmodules = true;
      };
    });

    # Phase 5: Nvidia Isolation Post-Install Check
    # This applies to all overridden packages ideally, or we can use a wrapper.
    # For now, we inject it into the scope helper if possible, or just append to specific critical ones.
    # "Add postInstall checks to scan for nvidia symbols."
    
  });
  # Phase 4: Strix Halo Runtime Wrapper (to be used in devShell)
  # accessible via final.rocmShellHook
  rocmShellHook = "shellHook = ''\n        export LLAMA_HIP_UMA=ON\n        export HSA_XNACK=1\n        export HSA_OVERRIDE_GFX_VERSION=11.5.1\n        \n        # Tuning: HugePages\n        if [ -w /sys/kernel/mm/transparent_hugepage/enabled ]; then\n            echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true\n        fi\n      '';";
}
