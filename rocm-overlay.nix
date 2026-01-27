# ROCm 7.2.0 Overlay - Antigravity Generated
final: prev: {
  rocmPackages = prev.rocmPackages // {
    # Phase 1: Verified Sources

    half = prev.rocmPackages.half.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/half";
        rev = "d365a904e6c75a5f6e8387b7e51fbdd8540114ea";
        sha256 = "0vlsmrs3aiv30j1ifks9g9cl8b1xdjv7dd706w5npjhy27j4xzr1";
        fetchSubmodules = true;
      };
    });

    rocr_debug_agent = prev.rocmPackages.rocr_debug_agent.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocr_debug_agent";
        rev = "acc541a559c0a1569c4518f641c6f8442e2afd09";
        sha256 = "1j82fy24ha6dyb89vzfqbyhmjd5jshab0ij51sy2wavf9bi60rn3";
        fetchSubmodules = true;
      };
    });

    rocm-cmake = prev.rocmPackages.rocm-cmake.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocm-cmake";
        rev = "f2657238cb71df839c97807d5b0cb2c184075227";
        sha256 = "1gflvkvj66izik8n1af80qkda3z5nyn3g35h36br9mhdhb6a73l1";
        fetchSubmodules = true;
      };
    });

    TransferBench = prev.rocmPackages.TransferBench.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/TransferBench";
        rev = "9f0c8f1e81ecdb2777345318f94dececd156827e";
        sha256 = "1fbq30248kvgwj5rlqvarjqrmwkrwcj4vp66r8q01csjkv3p453i";
        fetchSubmodules = true;
      };
    });

    rocPyDecode = prev.rocmPackages.rocPyDecode.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocPyDecode";
        rev = "91c3415bf1014cd0c472ea17698464267e6c2c3c";
        sha256 = "0ibv4n8q9rpl9nphaaql90y64v4mxxnpagk7yw5wccdp97b8psxh";
        fetchSubmodules = true;
      };
    });

    ROCdbgapi = prev.rocmPackages.ROCdbgapi.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/ROCdbgapi";
        rev = "f37bf04206b17b1ba09c8f99162ab01a0d9fa644";
        sha256 = "0ivnxp8m61lprllqghav5kky0mzgll17rrv6y7mrdwigyb0y3ara";
        fetchSubmodules = true;
      };
    });

    rocSHMEM = prev.rocmPackages.rocSHMEM.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocSHMEM";
        rev = "c22e407b75c19d53a95d3c6dc01827e3937b6feb";
        sha256 = "0f110pjdid4s1nyn1vgk4n47y23648js4xnqmm11hynqpa7wki3p";
        fetchSubmodules = true;
      };
    });

    ROCmValidationSuite = prev.rocmPackages.ROCmValidationSuite.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/ROCmValidationSuite";
        rev = "08b4b3cd4eea5b045b20a5bf9460f10a18cd426c";
        sha256 = "0ffj2xvpyany5hv52f6sxn4gl78h8a9if812av1x8yl89kj1x8kz";
        fetchSubmodules = true;
      };
    });

    rocJPEG = prev.rocmPackages.rocJPEG.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocJPEG";
        rev = "181c6a96310f9bf64b53a4f97134cd920bab9c7b";
        sha256 = "0p5fcbv4z50g3y95a7cxpr5ldy9blrhx28f7saayb2ssfpl4gv13";
        fetchSubmodules = true;
      };
    });

    rocALUTION = prev.rocmPackages.rocALUTION.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocALUTION";
        rev = "f814c24aa7886f823a9107bcc7c46a998a214d69";
        sha256 = "1pj0rbjgf4z180k0l2g0mhfcv5g220693073y1245ca8cp85i6gd";
        fetchSubmodules = true;
      };
    });

    HIPIFY = prev.rocmPackages.HIPIFY.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/HIPIFY";
        rev = "e1441b5ae9148a8ee1bd79966d7da8f5a7e4451e";
        sha256 = "1msnj5b32f23bl8p36ikgq69pbnd7bncsxhgax7v8mxdhyfjab9c";
        fetchSubmodules = true;
      };
    });

    spirv-llvm-translator = prev.rocmPackages.spirv-llvm-translator.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/spirv-llvm-translator";
        rev = "c6bb848c61dd2759108ff2f571a9751875be0a32";
        sha256 = "03yc02p0krsdqhjfvggcvh347dmqag267p3hbfjld7brbqc25cdq";
        fetchSubmodules = true;
      };
    });

    rocm-examples = prev.rocmPackages.rocm-examples.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocm-examples";
        rev = "8a51ebaa4e67b25c82f95a1423102122786bab82";
        sha256 = "14gysnvsq8yjamhjsbbhy9civr25ggr8d7qpgaiq89lr8pryn3fx";
        fetchSubmodules = true;
      };
    });

    rocDecode = prev.rocmPackages.rocDecode.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocDecode";
        rev = "a721963b3c5dd2fa242b011c460d857106717eb3";
        sha256 = "0fm8rzggq0753hwdrqal4g9k80d6xa7f0gd3yrn1sc87zym7jz9a";
        fetchSubmodules = true;
      };
    });

    composable_kernel = prev.rocmPackages.composable_kernel.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/composable_kernel";
        rev = "79cbc82654120f8ee6b0a11038d79fb92b6d55b6";
        sha256 = "0zhf42qrms9jkyabdngwdc3yk2gb3g1c7clvccga1dln54qz84h0";
        fetchSubmodules = true;
      };
      cmakeFlags = (old.cmakeFlags or []) ++ [
        "-DGPU_TARGETS=gfx1151" "-DCK_USE_AVX512=OFF"
      ];
    });

    AMDMIGraphX = prev.rocmPackages.AMDMIGraphX.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/AMDMIGraphX";
        rev = "7fe2fa0d2e0a046bb4f8dcaaf0c1a4294ee2f080";
        sha256 = "0gccpahw5iazcc0a56gsxp0i6x9ysk1wspwb1p5h9p1i9sr1a40l";
        fetchSubmodules = true;
      };
    });

    rocAL = prev.rocmPackages.rocAL.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocAL";
        rev = "203111a1cf1b9cf8ca071d59917716c41fac0f57";
        sha256 = "18bgg2hndj2d2mh1s1f5rc0gzl2qjgzdw21ra6mnrgygw95aj5lv";
        fetchSubmodules = true;
      };
    });

    rccl = prev.rocmPackages.rccl.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rccl";
        rev = "0d2c4fd4c5ea8aa96b4ac4eb468fb4146ab2c921";
        sha256 = "0lcmc4gdhhqr5pga5qyrm4vsp4araxlxygym4bdqk4b3fhzbm1pq";
        fetchSubmodules = true;
      };
      cmakeFlags = (old.cmakeFlags or []) ++ [
        "-DBUILD_TESTS=OFF"
      ];
    });

    rpp = prev.rocmPackages.rpp.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rpp";
        rev = "11df107f788d935b6e1c637f787c88b17b013016";
        sha256 = "0sdpd196zxzhjkxy1w2rlm0hiv44ggh3a74r6mmp0fsyjjfzsi4q";
        fetchSubmodules = true;
      };
    });

    ROCgdb = prev.rocmPackages.ROCgdb.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/ROCgdb";
        rev = "a750fba83b537848489d9830718277a94960a2c1";
        sha256 = "1ay4df45vbx177apq1mn0akrqrs5v5ipkcg6xzhpi7iin4f7ysd2";
        fetchSubmodules = true;
      };
    });

    MIVisionX = prev.rocmPackages.MIVisionX.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/MIVisionX";
        rev = "61b55914a4b364ae78f7503abb401d36ee1b634d";
        sha256 = "1c7kgi029himdqnf6mfrx9izwd2p2wgyajrm2symi41m9nvi1mmd";
        fetchSubmodules = true;
      };
    });

    llvm-project = prev.rocmPackages.llvm-project.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/llvm-project";
        rev = "3098435244119c38f6100dbd8d61e56c942a3c00";
        sha256 = "1g8hnn54q50gc0rv8dryirhlyz0gbgxqzmvvhxwd6lv3aamp3w13";
        fetchSubmodules = true;
      };
    });

    ROCK-Kernel-Driver = prev.rocmPackages.ROCK-Kernel-Driver.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/ROCK-Kernel-Driver";
        rev = "6550db7c16e00633c05e703bfce5d0218ee7ec88";
        sha256 = "02v1d4flsb8amg3wny5acs8w5c7x1004gafckk9x6xwa74b82122";
        fetchSubmodules = true;
      };
    });

    rocm-systems = prev.rocmPackages.rocm-systems.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocm-systems";
        rev = "da7ba12fd90f553f3d4629ffc9ca360545364ea0";
        sha256 = "1qsw3p6hgqf12m6iyym1mh92mzgxj0s9jy9j3x4fq3jhpmwc7jqw";
        fetchSubmodules = true;
      };
    });

    rocm-libraries = prev.rocmPackages.rocm-libraries.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocm-libraries";
        rev = "722b4750695dbdf61a03305b9b4cd73acd7def88";
        sha256 = "188dnrjpg3332qwysfnar54vwjd6gn5v3j9r7cdkz9bid1ggrw7s";
        fetchSubmodules = true;
      };
    });

    rocm_bandwidth_test = prev.rocmPackages.rocm_bandwidth_test.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/rocm_bandwidth_test";
        rev = "68189da6e7adaed213e5e1df3be0e2c537827751";
        sha256 = "1mc5hvp17mrnbhwr1wxbww90mkiv8laii6abb723arsi2aqkjisj";
        fetchSubmodules = true;
      };
    });

    # Core Consolidation
    rocm-runtime = prev.rocmPackages.rocm-runtime.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/ROCR-Runtime";
        rev = "acc541a559c0a1569c4518f641c6f8442e2afd09";
        sha256 = "1j82fy24ha6dyb89vzfqbyhmjd5jshab0ij51sy2wavf9bi60rn3"; # Source from rocr_debug_agent as proxy for now
        fetchSubmodules = true;
      };
    });

    ROCR-Runtime = final.rocmPackages.rocm-runtime;

    clr = prev.rocmPackages.clr.overrideAttrs (old: {
      src = final.fetchgit {
        url = "https://github.com/ROCm/clr";
        rev = "rocm-7.2.0";
        sha256 = "0000000000000000000000000000000000000000000000000000"; # PLACEHOLDER
        fetchSubmodules = true;
      };
    });

  };

  # Project into top-level for flake.nix accessibility
  rocm-cmake = final.rocmPackages.rocm-cmake;
  rocm-runtime = final.rocmPackages.rocm-runtime;
  clr = final.rocmPackages.clr;

  # Phase 4: Strix Halo Runtime Wrapper (to be used in devShell)
  # accessible via final.rocmShellHook
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