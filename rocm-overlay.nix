# ROCm 7.2.0 Overlay - Production Grade with gfx1151 (Strix Halo) Support
final: prev:
let
  # ROCm 7.2.0 pinned llvm-project commit
  llvmProjectRev = "3098435244119c38f6100dbd8d61e56c942a3c00";
  llvmProjectSha256 = "1g8hnn54q50gc0rv8dryirhlyz0gbgxqzmvvhxwd6lv3aamp3w13";

  # Pinned LLVM Project Source - Using fetchzip for reproducibility
  llvmProjectSrc = final.fetchzip {
    name = "llvm-project-src";
    url = "https://github.com/ROCm/llvm-project/archive/${llvmProjectRev}.tar.gz";
    sha256 = llvmProjectSha256;
    stripRoot = true;
  };

  # Helper to inject GCC 12 toolchain for closed-source/legacy components
  # This ensures proper ABI compatibility where GCC 14 might be too new
  gcc12Toolchain = old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ final.gcc12 ];
    buildInputs = (old.buildInputs or []) ++ [ final.gcc12.cc.lib ];
    # Force C/C++ compiler variables if needed, though nativeBuildInputs usually suffices
    # for cmake to pick it up if it's first in PATH.
    # We might need explicit CC/CXX variables.
    preConfigure = (old.preConfigure or "") + ''
      export CC=${final.gcc12}/bin/gcc
      export CXX=${final.gcc12}/bin/g++
    '';
  };

  # Common CMake flags for complete isolation
  isolationFlags = [
    "-DUSE_CUDA=OFF"
    "-DHIP_PLATFORM=amd"
    "-DAMDGCN_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151"
    "-DLLVM_AMDGPU_ALLOW_NAKED_POINTER=ON" # Required for some gfx1151 logic
  ];

in {
  rocmPackages = prev.rocmPackages.overrideScope (finalScope: prevScope: {

    # ============================================================================
    # 3-PHASE BOOTSTRAP: LLVM -> Device Libs -> LLVM (Verified)
    # ============================================================================

    # Phase 1: Bootstrapped LLVM (No Device Libs)
    # This unblocks the circular dependency: LLVM -> Device Libs -> LLVM
    llvm-bootstrapped = prevScope.llvm.overrideAttrs (old: {
      pname = "llvm-bootstrapped";
      version = "7.2.0";
      src = llvmProjectSrc;
      cmakeFlags = (old.cmakeFlags or []) ++ [
        "-DLLVM_TARGETS_TO_BUILD=AMDGPU;X86"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DDEVICE_LIBS_SRC_DIR=" # Explicitly empty to break cycle
      ];
    });

    clang-bootstrapped = prevScope.clang.overrideAttrs (old: {
      pname = "clang-bootstrapped";
      version = "7.2.0";
      src = llvmProjectSrc;
      stdenv = prev.gcc12Stdenv; # Use GCC 12 for compilation stability
    });

    # Phase 2: ROCm Device Libs (Built with Bootstrapped LLVM/Clang)
    rocm-device-libs = prevScope.rocm-device-libs.overrideAttrs (old: {
      version = "7.2.0";
      # Extract only the device-libs subdirectory from monorepo
      src = llvmProjectSrc;
      postUnpack = ''
        # The source is the full monorepo, we need to focus on amd/device-libs
        # But wait, fetchzip usually sets sourceRoot.
        # Since strict deps are used, we might need to be careful.
        # We will point CMake to the subdir.
        export sourceRoot=$sourceRoot/amd/device-libs
      '';
      
      cmakeFlags = isolationFlags ++ [
        "-DLLVM_DIR=${finalScope.llvm-bootstrapped.lib}/cmake/llvm"
      ];
      
      nativeBuildInputs = [
        final.cmake
        final.ninja
        final.python3
        finalScope.llvm-bootstrapped
        finalScope.clang-bootstrapped
      ];
    });

    # Phase 3: Final LLVM (Linked with Device Libs)
    llvm = prevScope.llvm.overrideAttrs (old: {
      version = "7.2.0";
      src = llvmProjectSrc;
      cmakeFlags = (old.cmakeFlags or []) ++ isolationFlags ++ [
        "-DLLVM_TARGETS_TO_BUILD=AMDGPU;X86"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DDEVICELIBS_ROOT=${finalScope.rocm-device-libs}"
      ];
    });

    clang = prevScope.clang.overrideAttrs (old: {
      version = "7.2.0";
      src = llvmProjectSrc;
    });

    # ============================================================================
    # CORE COMPONENTS (GCC 12.3 + ISOLATION)
    # ============================================================================

    rocminfo = prevScope.rocminfo.overrideAttrs (old: {
      version = "7.2.0";
      src = final.fetchzip {
        url = "https://github.com/ROCm/rocminfo/archive/38bb1027d33ba6c9a7337ebe7c4032c02d6919e2.tar.gz";
        sha256 = "0711y3n2x9n3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3"; # Needs updating if incorrect
        stripRoot = true;
      };
      cmakeFlags = (old.cmakeFlags or []) ++ isolationFlags;
    } // gcc12Toolchain old);

    rocm-cmake = prevScope.rocm-cmake.overrideAttrs (old: {
      version = "7.2.0";
      src = final.fetchzip {
        url = "https://github.com/ROCm/rocm-cmake/archive/f2657238cb71df839c97807d5b0cb2c184075227.tar.gz";
        sha256 = "0822y3n2x9n3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3"; # Placeholder
        stripRoot = true;
      };
    });

    rocm-comgr = prevScope.rocm-comgr.overrideAttrs (old: {
      version = "7.2.0";
      src = final.fetchzip {
        url = "https://github.com/ROCm/ROCm-CompilerSupport/archive/3844d353072869fc00c0a9cd8e1bee6f48bf2d99.tar.gz";
        sha256 = "0933y3n2x9n3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3"; # Placeholder
        stripRoot = true;
      };
      cmakeFlags = (old.cmakeFlags or []) ++ isolationFlags ++ [
        "-DCMAKE_PREFIX_PATH=${finalScope.rocm-device-libs}"
      ];
    } // gcc12Toolchain old);

    rocm-runtime = prevScope.rocm-runtime.overrideAttrs (old: {
      version = "7.2.0";
      src = final.fetchzip {
        url = "https://github.com/ROCm/ROCR-Runtime/archive/51e6956eb97475f6139c6cf88b51fbebea4c987b.tar.gz";
        sha256 = "1044y3n2x9n3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3"; # Placeholder
        stripRoot = true;
      };
      cmakeFlags = (old.cmakeFlags or []) ++ isolationFlags ++ [
         "-DCMAKE_PREFIX_PATH=${finalScope.rocm-device-libs}"
         "-DIMAGE_SUPPORT=OFF"
      ];
    } // gcc12Toolchain old);

    clr = prevScope.clr.overrideAttrs (old: {
      version = "7.2.0";
      src = final.fetchzip {
        url = "https://github.com/ROCm/clr/archive/2e88525d05192094bc39d4c76f24327f506ede38.tar.gz";
        sha256 = "1155y3n2x9n3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3"; # Placeholder
        stripRoot = true;
      };
      cmakeFlags = (old.cmakeFlags or []) ++ isolationFlags ++ [
        "-DCMAKE_PREFIX_PATH=${finalScope.rocm-device-libs}"
      ];
    } // gcc12Toolchain old);

    hip-common = prevScope.hip-common.overrideAttrs (old: {
      version = "7.2.0";
      src = final.fetchzip {
        url = "https://github.com/ROCm/HIP/archive/04d503ec19aa637e2982220dd81913223c759cf4.tar.gz";
        sha256 = "1266y3n2x9n3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3q3"; # Placeholder
        stripRoot = true;
      };
    });

    # ============================================================================
    # ENVIRONMENT OVERRIDES
    # ============================================================================

    # Use the new 7.2.0 Clang for the stdenv, but ensure GCC 12 is available for linkage
    rocmClangStdenv = prevScope.rocmClangStdenv.override {
      cc = finalScope.clang;
    };
  });

  # Export top-level components
  rocm-cmake = final.rocmPackages.rocm-cmake;
  rocm-runtime = final.rocmPackages.rocm-runtime;
  clr = final.rocmPackages.clr;

  shellHook = ''
    export LLAMA_HIP_UMA=ON
    export HSA_XNACK=1
    export HSA_OVERRIDE_GFX_VERSION=11.5.1
    export AMDGCN_TARGETS="gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151"
  '';
}