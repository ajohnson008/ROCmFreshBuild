{
  description = "pinned-rocm - small flake that records ROcm project commit pins for rocm-7.2.0";

  outputs = { self, ... }: {
    # Expose a simple attribute set with repo, rev and tarball url information
    pins = {
      rocm-systems = {
        repo = "ROCm/rocm-systems";
        rev = "da7ba12fd90f553f3d4629ffc9ca360545364ea0";
        url = "https://github.com/ROCm/rocm-systems/archive/da7ba12fd90f553f3d4629ffc9ca360545364ea0.tar.gz";
      };
      rocm-cmake = {
        repo = "ROCm/rocm-cmake";
        rev = "f2657238cb71df839c97807d5b0cb2c184075227";
        url = "https://github.com/ROCm/rocm-cmake/archive/f2657238cb71df839c97807d5b0cb2c184075227.tar.gz";
      };
      ROCR-Runtime = {
        repo = "ROCm/ROCR-Runtime";
        rev = "51e6956eb97475f6139c6cf88b51fbebea4c987b";
        url = "https://github.com/ROCm/ROCR-Runtime/archive/51e6956eb97475f6139c6cf88b51fbebea4c987b.tar.gz";
      };
      clr = {
        repo = "ROCm/clr";
        rev = "2e88525d05192094bc39d4c76f24327f506ede38";
        url = "https://github.com/ROCm/clr/archive/2e88525d05192094bc39d4c76f24327f506ede38.tar.gz";
      };
      llvm-project = {
        repo = "ROCm/llvm-project";
        rev = "3098435244119c38f6100dbd8d61e56c942a3c00";
        url = "https://github.com/ROCm/llvm-project/archive/3098435244119c38f6100dbd8d61e56c942a3c00.tar.gz";
      };
    };

    # Also expose an example target to allow `nix flake check` if desired
    defaultPackage.x86_64-linux = builtins.throw "This flake only provides pin metadata (use .pins).";
  };
}
