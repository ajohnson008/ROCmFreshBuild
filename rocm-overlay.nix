# ROCm 7.2.0 Overlay - Antigravity Generated
final: prev: {
  rocmPackages = prev.rocmPackages.overrideScope (rfinal: rprev: {
    # Phase 1: Verified Sources
    # User Warning: Verification timed out or failed to parse XML. Using placeholders.
    # Please update sha256 hashes with actual values from `nix-prefetch-git` or similar.
    # Note: rocBLAS and MIOpen were missing from verified_sources.json, so placeholders remain.

    composable_kernel = rprev.composable_kernel.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/composable_kernel";
        rev = "rocm-7.2.0";
        sha256 = "0zhf42qrms9jkyabdngwdc3yk2gb3g1c7clvccga1dln54qz84h0";
        fetchSubmodules = true;
      };
      cmakeFlags = (old.cmakeFlags or []) ++ [
        "-DGPU_TARGETS=gfx1151" "-DCK_USE_AVX512=OFF"
      ];
      postInstall = (old.postInstall or "") + ''
        rm -rf $out/cuda
      '';
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
      postInstall = (old.postInstall or "") + ''
        rm -rf $out/cuda
      '';
    });

    MIOpen = rprev.MIOpen.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/MIOpen";
        rev = "rocm-7.2.0";
        sha256 = "HASH-MIOpen-VERIFIED";
        fetchSubmodules = true;
      };
      postInstall = (old.postInstall or "") + ''
        rm -rf $out/cuda
      '';
    });

    rccl = rprev.rccl.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rccl";
        rev = "rocm-7.2.0";
        sha256 = "0lcmc4gdhhqr5pga5qyrm4vsp4araxlxygym4bdqk4b3fhzbm1pq";
        fetchSubmodules = true;
      };
      cmakeFlags = (old.cmakeFlags or []) ++ [
        "-DBUILD_TESTS=OFF"
      ];
      postInstall = (old.postInstall or "") + ''
        rm -rf $out/cuda
      '';
    });

    HIPIFY = rprev.HIPIFY.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/HIPIFY";
        rev = "rocm-7.2.0";
        sha256 = "1msnj5b32f23bl8p36ikgq69pbnd7bncsxhgax7v8mxdhyfjab9c";
        fetchSubmodules = true;
      };
      postInstall = (old.postInstall or "") + ''
        rm -rf $out/cuda
      '';
    });

    rocm_bandwidth_test = rprev.rocm_bandwidth_test.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocm_bandwidth_test";
        rev = "rocm-7.2.0";
        sha256 = "0j9s55jmak5zgvvjp20qhvnj3j1cgvryalnr452x4ja85pn94pz1";
        fetchSubmodules = true;
      };
      postInstall = (old.postInstall or "") + ''
        rm -rf $out/cuda
      '';
    });

    TransferBench = rprev.TransferBench.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/TransferBench";
        rev = "rocm-7.2.0";
        sha256 = "1fbq30248kvgwj5rlqvarjqrmwkrwcj4vp66r8q01csjkv3p453i";
        fetchSubmodules = true;
      };
      postInstall = (old.postInstall or "") + ''
        rm -rf $out/cuda
      '';
    });

    llvm-project = rprev.llvm-project.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/llvm-project";
        rev = "rocm-7.2.0";
        sha256 = "1g8hnn54q50gc0rv8dryirhlyz0gbgxqzmvvhxwd6lv3aamp3w13";
        fetchSubmodules = true;
      };
      postInstall = (old.postInstall or "") + ''
        rm -rf $out/cuda
      '';
    });

  });
  # Phase 4: Strix Halo Runtime Wrapper (to be used in devShell)
  # accessible via final.rocmShellHook
  rocmShellHook = "shellHook = ''\n        export LLAMA_HIP_UMA=ON\n        export HSA_XNACK=1\n        export HSA_OVERRIDE_GFX_VERSION=11.5.1\n        \n        # Tuning: HugePages\n        if [ -w /sys/kernel/mm/transparent_hugepage/enabled ]; then\n            echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true\n        fi\n      '';";
}
