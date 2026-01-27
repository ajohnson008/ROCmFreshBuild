#!/usr/bin/env bash
set -e

prefetch() {
    name=$1
    url=$2
    echo "Prefetching $name from $url..."
    hash=$(nix-prefetch-url --unpack "$url" 2>/dev/null)
    echo "$name: $hash"
}

prefetch "llvm-project" "https://github.com/ROCm/llvm-project/archive/3098435244119c38f6100dbd8d61e56c942a3c00.tar.gz"
prefetch "rocminfo" "https://github.com/ROCm/rocminfo/archive/38bb1027d33ba6c9a7337ebe7c4032c02d6919e2.tar.gz"
prefetch "rocm-cmake" "https://github.com/ROCm/rocm-cmake/archive/f2657238cb71df839c97807d5b0cb2c184075227.tar.gz"
prefetch "rocm-comgr" "https://github.com/ROCm/ROCm-CompilerSupport/archive/3844d353072869fc00c0a9cd8e1bee6f48bf2d99.tar.gz"
prefetch "rocm-runtime" "https://github.com/ROCm/ROCR-Runtime/archive/51e6956eb97475f6139c6cf88b51fbebea4c987b.tar.gz"
prefetch "clr" "https://github.com/ROCm/clr/archive/2e88525d05192094bc39d4c76f24327f506ede38.tar.gz"
prefetch "hip-common" "https://github.com/ROCm/HIP/archive/04d503ec19aa637e2982220dd81913223c759cf4.tar.gz"
