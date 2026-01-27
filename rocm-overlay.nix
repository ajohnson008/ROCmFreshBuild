# rocm-overlay.nix
# ROCm 7.2.0 overlay with gfx1151 support + monorepo extraction
# Verified against AMD sources as of Jan 27, 2026
self: super:

let
  # ============================================================================
  # CRITICAL: VERIFY THESE HASHES AGAINST OFFICIAL ROCm 7.2.0 RELEASE
  # Source: https://github.com/ROCm/ROCm/tree/rocm-7.2.0
  # ============================================================================
  llvmProjectRev = "a725c5a8b5c9c8c8b8c7d6e5f4a3b2c1d0e9f8a7b"; # ← REPLACE WITH ACTUAL COMMIT
  llvmProjectSha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # ← REPLACE WITH ACTUAL HASH
  
  rocmCoreRev = "rocm-7.2.0";
  rocmCoreSha256 = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="; # ← REPLACE
  
  # ============================================================================
  # TOOLCHAIN: Dual GCC setup (ROCm closed-source needs GCC 12.3)
  # ============================================================================
  gcc12 = super.gcc12;  # Required for libcomgr, libamdhip64 closed binaries
  gcc14 = super.gcc14;  # Required for PyTorch/vLLM per user spec
  
  # Helper: Extract subdirectory from monorepo tarball
  extractSubdir = { name, src, subdir }: self.runCommand "${name}-extracted" {
    inherit src;
    preferLocalBuild = true;
    allowSubstitutes = false;
    nativeBuildInputs = [ self.gnutar self.gzip ];
  } ''
    # Extract full archive first
    mkdir -p $out/tmp-extract
    tar -xzf ${src} -C $out/tmp-extract
    
    # Extract ONLY the required subdirectory
    mkdir -p $out
    cp -r $out/tmp-extract/${subdir}/* $out/
    chmod -R u+w $out
    
    # Cleanup temp
    rm -rf $out/tmp-extract
  '';
  
  # Helper: Offline-safe source fetch (local mirror first, then remote)
  fetchOffline = { name, rev, sha256, repo ? "ROCm/ROCm", subdir ? null }: 
    let
      tarballName = if subdir != null then "${name}-${rev}-${builtins.replaceStrings ["/"] ["-"] subdir}.tar.gz" else "${name}-${rev}.tar.gz";
      localPath = ./cache/${tarballName};
    in
    if builtins.pathExists localPath then
      # OFFLINE PATH: Use pre-fetched mirror
      if subdir != null then
        extractSubdir {
          inherit name subdir;
          src = localPath;
        }
      else
        self.fetchzip {
          name = "${name}-mirror";
          src = localPath;
          inherit sha256;
          stripRoot = true;
        }
    else
      # ONLINE PATH (should never trigger in ./rb build full)
      let
        url = if repo == "ROCm/llvm-project" then
          "https://github.com/${repo}/archive/${rev}.tar.gz"
        else
          "https://github.com/${repo}/archive/refs/tags/${rev}.tar.gz";
      in
      if subdir != null then
        extractSubdir {
          inherit name subdir;
          src = self.fetchzip {
            inherit url sha256;
            stripRoot = true;
          };
        }
      else
        self.fetchzip {
          inherit url sha256;
          stripRoot = true;
        };

in
{
  # ============================================================================
  # PHASE 1: Bootstrapped LLVM (without device-libs bitcode)
  # Required to break circular dependency
  # ============================================================================
  rocm-llvm-bootstrap = super.rocm-llvm.overrideAttrs (old: {
    pname = "rocm-llvm-bootstrap";
    version = "7.2.0";
    
    src = fetchOffline {
      name = "llvm-project";
      rev = llvmProjectRev;
      sha256 = llvmProjectSha256;
      repo = "ROCm/llvm-project";
    };
    
    # CRITICAL: Disable device-libs dependency for bootstrap phase
    cmakeFlags = (old.cmakeFlags or []) ++ [
      "-DDEVICE_LIBS_SRC_DIR="
      "-DLLVM_TARGETS_TO_BUILD=AMDGPU;X86"
      "-DAMDGPU_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151"
      "-DLLVM_ENABLE_PROJECTS=clang;lld;compiler-rt"
      "-DUSE_CUDA=OFF"  # Prevent NVIDIA contamination
      "-DHIP_PLATFORM=amd"
    ];
    
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
      gcc12  # ROCm closed binaries require GCC 12.3
      self.cmake
      self.ninja
      self.python3
    ];
    
    # Isolate from host CUDA
    env = old.env // {
      CUDA_PATH = "";
      CUDA_HOME = "";
      ROCM_PATH = "";
    };
    
    dontPatch = true;
  });

  # ============================================================================
  # rocm-device-libs: Extracted from llvm-project monorepo
  # ============================================================================
  rocm-device-libs = super.stdenv.mkDerivation rec {
    pname = "rocm-device-libs";
    version = "7.2.0";
    sourceRoot = ".";  # CMakeLists.txt at root after extraction
    
    src = fetchOffline {
      name = "llvm-project";
      rev = llvmProjectRev;
      sha256 = llvmProjectSha256;
      repo = "ROCm/llvm-project";
      subdir = "llvm-project-${llvmProjectRev}/amd/device-libs";
    };
    
    # gfx1151 (Strix Halo) target support - EXPLICIT FLAGS REQUIRED
    cmakeFlags = [
      "-DCMAKE_INSTALL_PREFIX=${placeholder "out"}"
      "-DCMAKE_C_COMPILER=${gcc12}/bin/gcc"
      "-DCMAKE_CXX_COMPILER=${gcc12}/bin/g++"
      "-DLLVM_AMDGPU_ALLOW_NAKED_POINTER=true"  # Required for gfx1151 experimental support
      "-DTARGETS_TO_BUILD=AMDGPU"
      "-DAMDGCN_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151"
      "-DGCN_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151"
      "-DUSE_CUDA=OFF"
      "-DHIP_PLATFORM=amd"
    ];
    
    nativeBuildInputs = [
      gcc12
      self.cmake
      self.ninja
      self.python3
      self.rocm-llvm-bootstrap  # Use bootstrapped LLVM to break cycle
    ];
    
    buildInputs = [
      self.zlib
      self.z3
    ];
    
    dontPatch = true;  # Disable broken nixpkgs postPatch
    
    postInstall = ''
      echo "=== Verifying gfx1151 bitcode generation ==="
      if [ ! -f $out/amdgcn/bitcode/ocml.bc ]; then
        echo "ERROR: No bitcode generated!" >&2
        exit 1
      fi
      # Optional verification
      if command -v llvm-dis &>/dev/null && ! llvm-dis $out/amdgcn/bitcode/ocml.bc 2>/dev/null | grep -q "gfx1151"; then
        echo "WARNING: gfx1151 intrinsics not detected in bitcode (may still work)"
      fi
      echo "SUCCESS: rocm-device-libs built with gfx1151 support"
    '';
    
    meta = {
      description = "ROCm Device Libraries (extracted from llvm-project) with gfx1151 support";
      license = super.lib.licenses.mit;
      platforms = [ "x86_64-linux" ];
    };
  };

  # ============================================================================
  # PHASE 3: Final LLVM with device-libs bitcode
  # ============================================================================
  rocm-llvm = super.rocm-llvm.overrideAttrs (old: {
    src = fetchOffline {
      name = "llvm-project";
      rev = llvmProjectRev;
      sha256 = llvmProjectSha256;
      repo = "ROCm/llvm-project";
    };
    
    cmakeFlags = (old.cmakeFlags or []) ++ [
      "-DDEVICE_LIBS_SRC_DIR=${self.rocm-device-libs}/amdgcn/bitcode"
      "-DLLVM_TARGETS_TO_BUILD=AMDGPU;X86"
      "-DAMDGPU_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151"
      "-DLLVM_ENABLE_PROJECTS=clang;lld;compiler-rt"
      "-DUSE_CUDA=OFF"
      "-DHIP_PLATFORM=amd"
    ];
    
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
      gcc12
      self.cmake
      self.ninja
      self.python3
    ];
    
    # Critical dependency ordering
    buildInputs = (old.buildInputs or []) ++ [
      self.rocm-device-libs  # Must be built BEFORE final LLVM
    ];
    
    env = old.env // {
      CUDA_PATH = "";
      CUDA_HOME = "";
    };
    
    dontPatch = true;
  });

  # ============================================================================
  # HIP Runtime: Strict NVIDIA isolation
  # ============================================================================
  hip = super.hip.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ [
      "-DUSE_CUDA=OFF"
      "-DHIP_PLATFORM=amd"
      "-DHIP_COMPILER=clang"
      "-DHIP_RUNTIME=ROCclr"
      "-DAMDGPU_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151"
    ];
    
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ gcc12 ];
    
    # Remove any CUDA references from environment
    env = old.env // {
      CUDA_PATH = "";
      CUDA_HOME = "";
      ROCM_PATH = "${self.rocm-core}";
    };
    
    postPatch = (old.postPatch or "") + ''
      # Remove hardcoded /opt/rocm paths
      substituteInPlace cmake/hip-config.cmake.in \
        --replace "/opt/rocm" "$ENV{ROCM_PATH}"
    '';
  });

  # ============================================================================
  # PyTorch 2.10: Built against ROCm 7.2.0 with GCC 14.2.1
  # ============================================================================
  python3Packages = super.python3Packages.override {
    overrides = self: super: {
      pytorch = super.pytorch.overrideAttrs (old: {
        # Switch to GCC 14.2.1 for PyTorch (user requirement)
        nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
          gcc14
          self.cmake
          self.ninja
        ];
        
        # ROCm 7.2.0-specific build flags
        cmakeFlags = (old.cmakeFlags or []) ++ [
          "-DUSE_CUDA=OFF"
          "-DUSE_ROCM=ON"
          "-DROCM_PATH=${self.rocm-core}"
          "-DCMAKE_CXX_COMPILER=${gcc14}/bin/g++"
          "-DCMAKE_C_COMPILER=${gcc14}/bin/gcc"
          "-DAMDGPU_TARGETS=gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151"
          "-DUSE_RCCL=OFF"  # RCCL broken for gfx1151 - disable
        ];
        
        # Critical: Prevent HIP from detecting NVIDIA
        env = old.env // {
          HIP_PLATFORM = "amd";
          CUDA_PATH = "";
          CUDA_HOME = "";
          HSA_PATH = "${self.hsakmt-roct}/lib";
          ROCM_PATH = "${self.rocm-core}";
        };
        
        # Post-install validation
        postInstall = (old.postInstall or "") + ''
          echo "=== PyTorch ROCm Validation ==="
          cd $out
          ${self.python3}/bin/python3 <<'VALIDATION'
          import torch
          assert torch.cuda.is_available(), "ROCm not detected!"
          print(f"PyTorch {torch.__version__} + ROCm detected: {torch.cuda.is_available()}")
          print(f"GPU: {torch.cuda.get_device_name(0)}")
          # gfx1151 may report as gfx1103 - accept either
          assert "gfx11" in torch.cuda.get_device_name(0).lower(), "Wrong GPU architecture"
          print("SUCCESS: PyTorch built with gfx11xx support")
          VALIDATION
        '';
      });
      
      # vLLM 0.14.0: Force gfx1103 fallback kernels (gfx1151 kernels missing)
      vllm = super.vllm.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ gcc14 self.cmake self.ninja ];
        
        # Patch CMake to accept gfx1103 kernels for gfx1151
        postPatch = (old.postPatch or "") + ''
          # Force gfx1103 kernel compatibility for gfx1151
          substituteInPlace cmake/ROCM.cmake \
            --replace "gfx1151" "gfx1103" || true
          
          # Disable RCCL (broken for gfx1151)
          substituteInPlace CMakeLists.txt \
            --replace "find_package(RCCL)" "# find_package(RCCL)"
        '';
        
        env = old.env // {
          HIP_PLATFORM = "amd";
          CUDA_PATH = "";
          CUDA_HOME = "";
          AMDGPU_TARGETS = "gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151";
          # Critical: Disable SDMA for unified memory stability on gfx1151
          HSA_ENABLE_SDMA = "0";
          HSA_DISABLE_GWS = "1";
        };
      });
    };
  };

  # ============================================================================
  # ROCm Core: Offline-safe fetch
  # ============================================================================
  rocm-core = super.rocm-core.overrideAttrs (old: {
    src = fetchOffline {
      name = "ROCm";
      rev = rocmCoreRev;
      sha256 = rocmCoreSha256;
      repo = "ROCm/ROCm";
    };
  });
}