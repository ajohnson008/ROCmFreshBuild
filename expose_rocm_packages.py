import sys

with open('flake.nix', 'r') as f:
    lines = f.readlines()

# Find targetPackages definition
start_idx = -1
for i, line in enumerate(lines):
    if 'targetPackages = {' in line:
        start_idx = i + 1
        break

if start_idx == -1:
    print("Could not find targetPackages")
    sys.exit(1)

new_lines = [
    "              # Direct exposure of ROCm libraries for the build driver\n",
    "              migraphx = pkgs.rocmPackages.migraphx;\n",
    "              miopen = pkgs.rocmPackages.miopen;\n",
    "              rccl = pkgs.rocmPackages.rccl;\n",
    "              rocblas = pkgs.rocmPackages.rocblas;\n",
    "              rocfft = pkgs.rocmPackages.rocfft;\n",
    "              rocprim = pkgs.rocmPackages.rocprim;\n",
    "              rocrand = pkgs.rocmPackages.rocrand;\n",
    "              rocsparse = pkgs.rocmPackages.rocsparse;\n",
    "              rocsolver = pkgs.rocmPackages.rocsolver;\n",
    "              rocthrust = pkgs.rocmPackages.rocthrust;\n",
    "              hipblas = pkgs.rocmPackages.hipblas;\n",
    "              hipcub = pkgs.rocmPackages.hipcub;\n",
    "              hipfft = pkgs.rocmPackages.hipfft;\n",
    "              hiprand = pkgs.rocmPackages.hiprand;\n",
    "              hipsparse = pkgs.rocmPackages.hipsparse;\n",
    "              hipsolver = pkgs.rocmPackages.hipsolver;\n",
    "              composable_kernel = pkgs.rocmPackages.composable_kernel;\n",
    "              hipify = pkgs.rocmPackages.hipify;\n",
    "              rocm-smi = pkgs.rocmPackages.rocm-smi;\n",
    "              amdsmi = pkgs.rocmPackages.amdsmi;\n",
    "              hip = pkgs.hip;\n",
    "              rocm-llvm = pkgs.rocm-llvm;\n",
    "              rocm-device-libs = pkgs.rocm-device-libs;\n",
    "              rocminfo = pkgs.rocminfo;\n",
]

lines[start_idx:start_idx] = new_lines

with open('flake.nix', 'w') as f:
    f.writelines(lines)
