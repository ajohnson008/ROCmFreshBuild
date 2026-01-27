# ROCm 7.2.0 Overlay - Integrated overrideScope
final: prev: {
  rocmPackages = prev.rocmPackages.overrideScope (finalScope: prevScope: {
    # 1. Shared ROCm 7.2.0 LLVM Source
    llvm-src = final.fetchgit {
      name = "rocm-llvm-src";
      url = "https://github.com/ROCm/llvm-project";
      rev = "3098435244119c38f6100dbd8d61e56c942a3c00";
      sha256 = "1g8hnn54q50gc0rv8dryirhlyz0gbgxqzmvvhxwd6lv3aamp3w13";
      fetchSubmodules = true;
    };

    # 2. Core Components using modern LLVM from unstable
    # Note: We must use .override to change the stdenv, as it's a fixed argument to the derivation function.
    rocm-runtime = (prevScope.rocm-runtime.override {
      stdenv = finalScope.rocmClangStdenv;
    }).overrideAttrs (old: {
      version = "7.2.0";
      src = final.fetchgit {
        name = "rocm-runtime-src";
        url = "https://github.com/ROCm/ROCR-Runtime";
        rev = "51e6956eb97475f6139c6cf88b51fbebea4c987b";
        sha256 = "sha256-6xELKQ/uqAoorsCR/H7d8iNK7LsVNsW2DRRZo5cU7UM=";
        fetchSubmodules = true;
      };
      sourceRoot = "rocm-runtime-src";
      # Add numactl for numa.h header (needed by libhsakmt/src/fmm.c)
      buildInputs = (old.buildInputs or []) ++ [ final.numactl ];
      patches = [];
      postPatch = "";
      # Help the internal clang calls find device libs
      cmakeFlags = (old.cmakeFlags or []) ++ [
        "-DCMAKE_PREFIX_PATH=${finalScope.rocm-device-libs}"
        "-DROCM_DEVICE_LIB_DIR=${finalScope.rocm-device-libs}/lib"
        "-DCMAKE_C_FLAGS=-I${final.numactl}/include"
        "-DCMAKE_CXX_FLAGS=-I${final.numactl}/include"
      ];
      # Manual injection of device lib path for the bitcode compiler calls
      preConfigure = (old.preConfigure or "") + ''
        # Patch the blit kernel CMakeLists.txt to add device lib path to clang invocation
        substituteInPlace runtime/hsa-runtime/image/blit_src/CMakeLists.txt \
          --replace-fail \
            '"-O2 -x cl -Xclang -finclude-default-header -cl-denorms-are-zero -cl-std=CL2.0' \
            '"-O2 --rocm-device-lib-path=${finalScope.rocm-device-libs}/lib -x cl -Xclang -finclude-default-header -cl-denorms-are-zero -cl-std=CL2.0'
      '';
      postInstall = (old.postInstall or "") + ''
        if [[ "$out" == *"6.0.2"* ]]; then
          echo "❌ GUARDRAIL FAILED: ROCm 6.0.2 detected in output path: $out"
          exit 1
        fi
      '';
    });

    hip-common = prevScope.hip-common.overrideAttrs (old: {
      version = "7.2.0";
      src = final.fetchgit {
        url = "https://github.com/ROCm/HIP";
        rev = "rocm-7.2.0";
        sha256 = "sha256-eQ+jHc6MlZePPIwJQMB8NKiEcE26i83+U21vKgfGFFM=";
        fetchSubmodules = true;
      };
    });

    clr = (prevScope.clr.override {
      stdenv = finalScope.rocmClangStdenv;
    }).overrideAttrs (old: {
      version = "7.2.0";
      src = final.fetchgit {
        url = "https://github.com/ROCm/clr";
        rev = "rocm-7.2.0";
        sha256 = "sha256-zz2O4Qsl1zXMC25L714azsFR2PROAvdpjgKhRolmt1w=";
        fetchSubmodules = true;
      };
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ final.git ];
      patches = [];
      postPatch = "patchShebangs .";
      cmakeFlags = (old.cmakeFlags or []) ++ [
        "-DCMAKE_PREFIX_PATH=${finalScope.rocm-device-libs}"
      ];
      postInstall = (old.postInstall or "") + ''
        if [[ "$out" == *"6.0.2"* ]]; then
          echo "❌ GUARDRAIL FAILED: ROCm 6.0.2 detected in output path: $out"
          exit 1
        fi
      '';
    });

    rocm-comgr = prevScope.rocm-comgr.overrideAttrs (old: {
      version = "7.2.0";
    });

    rocm-device-libs = prevScope.rocm-device-libs.overrideAttrs (old: {
      version = "7.2.0";
    });
  });

  # Project into top-level for flake.nix accessibility
  rocm-cmake = final.rocmPackages.rocm-cmake;
  rocm-runtime = final.rocmPackages.rocm-runtime;
  clr = final.rocmPackages.clr;
  rocm-comgr = final.rocmPackages.rocm-comgr;
  rocm-device-libs = final.rocmPackages.rocm-device-libs;

  # Phase 4: Strix Halo Runtime Wrapper (to be used in devShell)
  rocmShellHook = "shellHook = ''
        export LLAMA_HIP_UMA=ON
        export HSA_XNACK=1
        export HSA_OVERRIDE_GFX_VERSION=11.5.1
        
        # Tuning: HugePages
        if [ -w /sys/kernel/mm/transparent_hugepage/enabled ]; then
            echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
        fi
      '';";
}
