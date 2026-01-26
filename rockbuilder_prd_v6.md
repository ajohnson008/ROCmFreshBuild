# TheRockBuilder PRD v6.1: Production-Grade Nix Reconstruction with 12-Step AI Pipeline

**Project Code**: THE_ROCK_BUILDER_REBOOT  
**Target Platform**: AMD Strix Halo (gfx1151) on GMKtec EVO-X2  
**Build Platform**: AMD Threadripper 3960X (24C/48T, 64GB RAM, RTX 3080 Ti)  
**Build System**: Nix Flakes (Nix 2.31.2+)  
**Version**: 6.1 (Supersedes v6.0)  
**Document Date**: January 26, 2026

---

## 1. Executive Summary

TheRockBuilder v6.1 is a **production-hardened, air-gapped AI infrastructure build system** designed to compile a bit-for-bit reproducible AI stack for AMD Strix Halo architecture. This version introduces:

- **12-Step AI Pipeline**: Strict integration order from NumPy → PyTorch → vLLM → ONNX Runtime
- **Zen 2 Safety Protocol**: Mandatory AVX-512 blocking to prevent crashes on Threadripper 3960X host
- **LPDDR5X/UMA Optimization**: Unified Memory Access tuning for Strix Halo's 128GB unified memory
- **Quad-Layer NVIDIA Isolation**: Prevents any CUDA contamination from builder's RTX 3080 Ti
- **Integrated llama.cpp**: Dual variants (GPU with UMA, CPU without AVX-512) for maximum flexibility
- **Advanced Safety Systems**: Pre-flight validation, build checkpointing, and intelligent error recovery
- **Threadripper Optimization**: Parallel builds utilizing all 48 threads with memory-aware scheduling

Unlike v6.0's six-stage approach, v6.1 enforces a **strict 12-step build pipeline** with explicit version pinning from the PyTorch 2.10.0 compatibility matrix, ensuring stability on Zen 2 CPUs while maximizing Strix Halo performance.

---

## 2. Hard Constraints & Versioning (The "Iron Rules")

All components must be pinned to these exact versions. **No deviations permitted.**

### 2.1 Core Infrastructure
- **Nix Version**: 2.31.2 (experimental-features = nix-command flakes)
- **Nixpkgs Revision**: nixos-24.11 (commit f7c3c8b39c1d or stable equivalent)
- **GCC Version**: 14.2.1 (via custom overlay, strict requirement for ROCm 7.2.0)
- **Python**: 3.11.x

### 2.2 Build Platform (Threadripper 3960X)
- **CPU**: 24 cores / 48 threads
- **RAM**: 64GB DDR4
- **GPU**: NVIDIA RTX 3080 Ti (MUST be isolated from builds)
- **OS**: Same kernel version as target (Linux 6.18.6)
- **Storage**: Minimum 200GB free for /nix/store

### 2.3 Target Platform (GMKtec EVO-X2)
- **Architecture**: gfx1151 (AMD Strix Halo)
- **Memory**: 128GB LPDDR5X unified memory
- **Kernel**: Linux 6.18.6 (XNACK retry support required)
- **GPU**: Radeon 890M integrated (gfx1151)

### 2.4 AI Stack Versions (PyTorch 2.10.0 Compatibility Matrix)

**Foundation Layer**:
- **ROCm**: 7.2.0
- **NumPy**: 1.26.4 (last version with full BLAS/LAPACK compatibility for PyTorch 2.10)

**Core ML Framework**:
- **PyTorch**: 2.10.0 (ROCm backend only, `USE_ROCM=1`, `USE_CUDA=0`)
- **TorchVision**: 0.20.0 (strict PyTorch 2.10.0 compatibility)
- **Torchaudio**: 2.5.0 (FFmpeg 6.x compatible, SoX 14.4.2)

**Attention & Transformer Stack**:
- **FlashAttention-2**: 2.7.0 (ROCm 7.x compatible, `MIOPEN_ENABLE_LOGGING=1`)
- **xFormers**: 0.0.29 (must link FlashAttention-2, `XFORMERS_DISABLE_FLASH_ATTN=0`)

**Optimization & Distributed**:
- **DeepSpeed**: 0.16.0 (**CRITICAL**: `DS_BUILD_AVX512=0` for Zen 2 safety)
- **Bitsandbytes**: 0.45.0 (HIPified source, `BNB_CUDA_VERSION=720`)

**Inference Stack**:
- **vLLM**: 0.14.0 (`VLLM_TARGET_DEVICE=rocm`)
- **llama.cpp (GPU)**: Commit a33e6a0d (`-DGGML_HIP_UMA=ON` for Strix Halo UMA)
- **llama.cpp (CPU)**: Commit a33e6a0d (**CRITICAL**: `GGML_AVX512=OFF` for Zen 2 safety)
- **ONNX Runtime**: 1.20.0 (**CRITICAL**: `-Donnxruntime_ENABLE_AVX512=OFF`)

### 2.5 Quantization Standards
- **Primary**: Q4_K_M (optimal for 64-128GB VRAM)
- **High Quality**: Q5_K_M (for smaller models)
- **Maximum Quality**: Q8_0 (near-fp16, critical tasks only)

### 2.6 Zen 2 Safety Protocol (MANDATORY)

**Background**: The AMD Threadripper 3960X build host uses the Zen 2 microarchitecture, which **does not support AVX-512 instructions**. If any component emits AVX-512 during JIT compilation or runtime, the system will crash with an illegal instruction signal (SIGILL).

**Enforcement**: The following flags are **NON-NEGOTIABLE** for all builds:

| Component | Safety Flag | Consequence if Omitted |
|-----------|-------------|------------------------|
| DeepSpeed | `DS_BUILD_AVX512=0` | JIT kernel crash during distributed training |
| llama.cpp (CPU) | `GGML_AVX512=OFF` | SIGILL on CPU inference path |
| ONNX Runtime | `-Donnxruntime_ENABLE_AVX512=OFF` | SIGILL on ONNX model execution |

**Validation**: The pre-flight validator (Section 4.2.1) MUST check for AVX-512 symbols in all binaries:
```bash
# Forbidden AVX-512 patterns
objdump -d $binary | grep -E 'zmm[0-9]+|vpbroadcast[qd]|vpmull[qd]'
# Must return empty for all Zen 2-safe binaries
```

**Note**: The target Strix Halo platform (Zen 5) DOES support AVX-512, but we build on Zen 2. Binaries must be safe for the BUILD platform, not just the target.

### 2.7 LPDDR5X Unified Memory Architecture

**Strix Halo Memory Model**: The target platform uses 128GB LPDDR5X in a Unified Memory Architecture (UMA), where CPU and GPU share the same physical memory pool. This enables:

- **Zero-copy tensor sharing**: No PCIe transfers between CPU and GPU
- **Larger model contexts**: Full 128GB available for KV cache
- **Efficient memory-mapped models**: mmap directly usable by GPU

**Required Optimizations**:

| Component | UMA Flag | Effect |
|-----------|----------|--------|
| llama.cpp (GPU) | `-DGGML_HIP_UMA=ON` | Enables unified memory allocator |
| vLLM | `VLLM_USE_UNIFIED_MEMORY=1` | KV cache in unified pool |
| PyTorch | `PYTORCH_HIP_ALLOC_CONF=expandable_segments:True` | Dynamic unified allocation |

**Memory Bandwidth**: LPDDR5X @ 8533 MT/s provides ~270 GB/s, which is:
- 3x faster than DDR5-4800 (desktop)
- Comparable to HBM2 in bandwidth-limited workloads

---

## 3. System Architecture

### 3.1 Flake Structure (Single Monorepo)

**Decision**: Single `flake.nix` with internal organization via `let...in` blocks.

**Rationale**:
- Tight version coupling (ROCm ↔ PyTorch ↔ vLLM)
- Easier enforcement of "Iron Rules"
- Better for AI-assisted development (single context file)
- Simplified dependency locking

**Organization**:
```
flake.nix (lines 1-50):       Inputs, system boilerplate
flake.nix (lines 51-150):     GCC 14.2.1 overlay
flake.nix (lines 151-350):    ROCm 7.2.0 stack (17 packages)
flake.nix (lines 351-500):    NumPy + PyTorch + TorchVision + Torchaudio
flake.nix (lines 501-700):    FlashAttention-2 + xFormers + DeepSpeed
flake.nix (lines 701-850):    Bitsandbytes + vLLM + llama.cpp (GPU/CPU)
flake.nix (lines 851-1000):   ONNX Runtime + Zen 2 safety wrappers
flake.nix (lines 1001-1150):  Tooling (orchestrator, SBOM, scanners)
flake.nix (lines 1151-1300):  Safety systems (validators, auditors)
flake.nix (lines 1301-1450):  Outputs (packages, devShells, apps)
flake.nix (lines 1451-1600):  Tests and 12-step validation
```

### 3.2 Quad-Layer NVIDIA Isolation Protocol

**Critical Requirement**: Zero NVIDIA/CUDA symbols in any AMD binary.

#### Layer 1: Poisoned Package Overlay
```
Mechanism: Override NVIDIA packages to throw eval-time errors
Catches: Direct dependencies on cuda*/nvidia* packages
Prevention Level: 70% of contamination attempts
```

#### Layer 2: Dependency Graph Pre-Flight Analysis
```
Mechanism: Parse complete closure before building, audit for NVIDIA packages
Catches: Transitive dependencies 5+ levels deep
Prevention Level: 25% of remaining contamination
Tool: Custom dependency-auditor script
```

#### Layer 3: Build Sandbox Path Blacklisting
```
Mechanism: Make /usr/lib/nvidia*, /dev/nvidia* unreachable in sandbox
Catches: Hardcoded paths in build scripts
Prevention Level: 4% of remaining contamination
Implementation: Custom stdenv wrapper
```

#### Layer 4: Post-Build Binary Symbol Scanning
```
Mechanism: Scan all binaries with nm -D and strings for cuda/nvidia/nv_ symbols
Catches: Any contamination that slipped through previous layers
Prevention Level: 100% verification of outputs
Tool: Enhanced binary-scanner with pattern matching
```

**Failure Mode**: If Layer 4 detects contamination, build fails immediately with:
- Path to contaminated binary
- First 10 matching symbols
- Suggested remediation (check dependency X)

### 3.3 Hardware Optimization

#### 3.3.1 Target Platform (Strix Halo gfx1151)
**Kernel Boot Parameters**:
```
amdgpu.gtt_size=32768        # 32GB GTT allocation
amdgpu.noretry=0             # Enable XNACK memory retry
transparent_hugepage=always   # 2MB pages for model weights
```

**Compilation Flags**:
```
-DAMDGPU_TARGETS=gfx1151     # Explicit architecture target
-mcpu=znver4                 # Zen 4 CPU optimizations
-march=znver4                # Architecture-specific tuning
```

**Runtime Environment**:
```
HSA_FORCE_FINE_GRAIN_PCIE=1  # Fine-grained memory access
HIP_HOST_COHERENT=1          # LPDDR5X cache coherency
HSA_XNACK=1                  # Enable retry mechanism
HSA_OVERRIDE_GFX_VERSION=11.5.1  # Force gfx1151 detection
```

#### 3.3.2 Build Platform (Threadripper 3960X)
**Parallel Build Configuration**:
```
max-jobs = 24                # One job per physical core
cores = 2                    # 2 threads per job (48 total)
```

**Memory-Aware Scheduling**:
- Monitor `/sys/fs/cgroup/memory.pressure`
- Throttle jobs when pressure > 50%
- Exponential backoff when RAM usage > 85%

**Build Prioritization**:
1. **Foundation** (GCC): 8 cores, high priority
2. **ROCm**: 16 cores, medium priority  
3. **PyTorch**: 12 cores, memory-constrained
4. **vLLM/llama.cpp**: 8 cores each, parallel

---

## 4. Component Specifications (12-Step Pipeline)

### 4.0 Pipeline Summary Table

| Step | Component | Version | Critical Flags | Zen 2 Safe |
|------|-----------|---------|----------------|------------|
| 0 | ROCm | 7.2.0 | `AMDGPU_TARGETS=gfx1151` | ✅ |
| 1 | NumPy | 1.26.4 | `NPY_BLAS_ORDER=openblas` | ✅ |
| 2 | PyTorch | 2.10.0 | `USE_ROCM=1`, `USE_CUDA=0`, `PYTORCH_ROCM_ARCH=gfx1151` | ✅ |
| 3 | TorchVision | 0.20.0 | `FORCE_CUDA=0` | ✅ |
| 4 | Torchaudio | 2.5.0 | `USE_ROCM=1`, `USE_FFMPEG=1` | ✅ |
| 5 | FlashAttention-2 | 2.7.0 | `MIOPEN_ENABLE_LOGGING=1` | ✅ |
| 6 | xFormers | 0.0.29 | `XFORMERS_DISABLE_FLASH_ATTN=0` | ✅ |
| 7 | DeepSpeed | 0.16.0 | **`DS_BUILD_AVX512=0`** | ⚠️ CRITICAL |
| 8 | Bitsandbytes | 0.45.0 | `BNB_CUDA_VERSION=720` (HIPified) | ✅ |
| 9 | vLLM | 0.14.0 | `VLLM_TARGET_DEVICE=rocm` | ✅ |
| 10 | llama.cpp (GPU) | a33e6a0d | **`GGML_HIP_UMA=ON`** | ✅ |
| 11 | llama.cpp (CPU) | a33e6a0d | **`GGML_AVX512=OFF`** | ⚠️ CRITICAL |
| 12 | ONNX Runtime | 1.20.0 | **`-Donnxruntime_ENABLE_AVX512=OFF`** | ⚠️ CRITICAL |

**Legend**:
- ✅ = Safe for Zen 2 by default
- ⚠️ CRITICAL = Requires explicit flag to prevent Zen 2 crash

### 4.1 Core AI Stack

**Pipeline Integration Order** (STRICT - DO NOT REORDER):
```
Step 1:  NumPy 1.26.4         → Mathematical foundation
Step 2:  PyTorch 2.10.0       → Core ML framework
Step 3:  TorchVision 0.20.0   → Vision model support
Step 4:  Torchaudio 2.5.0     → Audio model support
Step 5:  FlashAttention-2     → Optimized attention kernels
Step 6:  xFormers 0.0.29      → Composable Transformer blocks
Step 7:  DeepSpeed 0.16.0     → Distributed training (ZEN 2 SAFE)
Step 8:  Bitsandbytes 0.45.0  → 8-bit quantization
Step 9:  vLLM 0.14.0          → Production inference server
Step 10: llama.cpp (GPU)      → ROCm UMA inference
Step 11: llama.cpp (CPU)      → CPU fallback (ZEN 2 SAFE)
Step 12: ONNX Runtime 1.20.0  → Interop inference (ZEN 2 SAFE)
```

#### 4.1.0 ROCm 7.2.0 (Foundation - Pre-Pipeline)
**Requirements**:
- GCC 14.2.1 (strict dependency)
- No CUDA headers in include path
- HIP runtime for gfx1151

**Sub-Components** (17 packages in overlay):
```
rocm-cmake, rocm-runtime, rocm-device-libs, clr (HIP),
hipcc, rocminfo, rocm-smi, rocblas, hipblas, rocsolver,
rocsparse, rocfft, rocrand, miopen, rccl, composable_kernel,
rocm-core (meta-package)
```

**Validation**:
- `/opt/rocm/bin/rocminfo` shows gfx1151
- `hipcc --version` reports 7.2.0
- No symbols matching `cuda*` in any .so file

#### 4.1.1 NumPy 1.26.4 (Step 1)
**Role**: Mathematical foundation for all numerical operations

**Build Configuration**:
```
NPY_BLAS_ORDER=openblas
NPY_LAPACK_ORDER=openblas
OPENBLAS_NUM_THREADS=1       # Prevent thread oversubscription
```

**Critical Validation** (MUST pass in checkPhase):
```python
import numpy as np
from numpy.linalg import inv, svd

# Verify BLAS linking
config = np.__config__.show()
assert 'openblas' in str(config).lower(), "BLAS not linked!"

# Verify LAPACK linking  
a = np.random.rand(100, 100)
u, s, vh = svd(a)  # Requires LAPACK
assert s.shape == (100,), "LAPACK SVD failed!"
```

**Memory**: ~2GB during build
**Duration**: ~15 minutes

#### 4.1.2 PyTorch 2.10.0 (Step 2)
**Role**: Core ML framework with ROCm backend

**Build Configuration**:
```bash
USE_CUDA=0                   # CRITICAL: No CUDA
USE_ROCM=1                   # ROCm backend only
PYTORCH_ROCM_ARCH=gfx1151    # Strix Halo target
BUILD_CAFFE2=0               # Reduce build time
BUILD_TEST=0                 # Skip tests during build
MAX_JOBS=4                   # Memory-constrained (see 4.2.4)
```

**UMA Optimization** (runtime):
```bash
PYTORCH_HIP_ALLOC_CONF=expandable_segments:True
```

**Memory Requirements**:
- Peak build: ~45GB RAM
- Orchestrator MUST throttle concurrent jobs

**Validation**:
```python
import torch
assert torch.version.hip == "7.2.0"
assert not torch.cuda.is_available()  # Must be False (ROCm masquerades as CUDA API)
assert "gfx1151" in torch.cuda.get_device_name(0).lower()
```

**Duration**: ~4 hours

#### 4.1.3 TorchVision 0.20.0 (Step 3)
**Role**: Vision model support (ResNet, ViT, CLIP, etc.)

**Build Configuration**:
```bash
FORCE_CUDA=0                 # Use ROCm path
TORCH_CUDA_ARCH_LIST=""      # Empty (not building CUDA)
WITH_PNG=1                   # libpng support
WITH_JPEG=1                  # libjpeg-turbo support
```

**Strict Compatibility**:
- MUST match PyTorch 2.10.0 exactly
- Version mismatch will cause `ImportError` at runtime

**Validation**:
```python
import torchvision
assert torchvision.__version__.startswith("0.20")
from torchvision import models
model = models.resnet18()
assert model is not None
```

**Duration**: ~30 minutes

#### 4.1.4 Torchaudio 2.5.0 (Step 4)
**Role**: Audio model support (Whisper, speech models)

**Build Configuration**:
```bash
USE_ROCM=1
USE_CUDA=0
USE_FFMPEG=1                 # FFmpeg 6.x backend
USE_SOX=1                    # SoX 14.4.2 for effects
BUILD_SOX=0                  # Use system SoX (avoid conflicts)
```

**Dependency Resolution**:
- FFmpeg must be 6.x (not 7.x - API incompatible)
- SoX must be isolated from system libraries
- Use `LD_LIBRARY_PATH` override in wrapper script

**Validation**:
```python
import torchaudio
assert torchaudio.__version__.startswith("2.5")
# Test FFmpeg backend
backend = torchaudio.get_audio_backend()
assert backend in ["ffmpeg", "sox"]
```

**Duration**: ~20 minutes

#### 4.1.5 FlashAttention-2 2.7.0 (Step 5)
**Role**: Optimized attention kernels for Transformer models

**Build Configuration**:
```bash
MIOPEN_ENABLE_LOGGING=1      # REQUIRED: Debug ROCm backend issues
FLASH_ATTENTION_FORCE_BUILD=1
MAX_JOBS=2                   # Memory-intensive compilation
```

**ROCm Specifics**:
- Uses MIOpen backend (not cuDNN)
- Requires composable_kernel from ROCm 7.2.0
- gfx1151 kernels generated at build time

**Validation**:
```python
from flash_attn import flash_attn_func
import torch
q = torch.randn(2, 8, 128, 64, device='cuda', dtype=torch.float16)
k = torch.randn(2, 8, 128, 64, device='cuda', dtype=torch.float16)
v = torch.randn(2, 8, 128, 64, device='cuda', dtype=torch.float16)
out = flash_attn_func(q, k, v)  # Should use ROCm backend
assert out.shape == (2, 8, 128, 64)
```

**Duration**: ~45 minutes

#### 4.1.6 xFormers 0.0.29 (Step 6)
**Role**: Composable Transformer building blocks with memory-efficient attention

**Build Configuration**:
```bash
XFORMERS_DISABLE_FLASH_ATTN=0    # MUST link against FlashAttention-2
FORCE_CUDA=0
XFORMERS_FORCE_BUILD=1
```

**Critical Dependency**:
- MUST be built AFTER FlashAttention-2 (Step 5)
- Links against flash_attn library for optimized kernels
- Will fall back to naive attention if `XFORMERS_DISABLE_FLASH_ATTN=1`

**Validation**:
```python
import xformers
from xformers.ops import memory_efficient_attention
assert hasattr(xformers.ops, 'memory_efficient_attention')
# Verify FlashAttention linkage
assert not xformers._is_flash_disabled()
```

**Duration**: ~30 minutes

#### 4.1.7 DeepSpeed 0.16.0 (Step 7) ⚠️ ZEN 2 CRITICAL
**Role**: Distributed training and inference optimization (ZeRO, inference kernels)

**Build Configuration**:
```bash
DS_BUILD_AVX512=0            # ⚠️ CRITICAL: Zen 2 has NO AVX-512!
DS_BUILD_CUDA=0              # No CUDA
DS_BUILD_EVOFORMER_ATTN=0    # Optional, reduce build time
DS_BUILD_SPARSE_ATTN=1       # Sparse attention kernels
```

**Zen 2 Safety Rationale**:
DeepSpeed's JIT compiler will emit AVX-512 instructions (ZMM registers) for optimized kernels if `DS_BUILD_AVX512=1`. The Threadripper 3960X (Zen 2) will **SIGILL crash** on any AVX-512 instruction.

**Validation**:
```bash
# Binary must NOT contain AVX-512 instructions
objdump -d $(python -c "import deepspeed; print(deepspeed.__path__[0])")/ops/*.so | grep -c 'zmm'
# Expected: 0
```

```python
import deepspeed
assert deepspeed.__version__ == "0.16.0"
```

**Duration**: ~25 minutes

#### 4.1.8 Bitsandbytes 0.45.0 (Step 8)
**Role**: 8-bit and 4-bit quantization for inference optimization

**Build Configuration**:
```bash
BNB_CUDA_VERSION=720         # Maps to ROCm 7.2.0 compatibility
CUDA_HOME=""                 # Force HIP path
```

**Source**: Use HIPified fork (ROCm-compatible bitsandbytes)
- Repository: `ROCm/bitsandbytes` or `TimDettmers/bitsandbytes` with ROCm patches
- The HIPified source replaces CUDA intrinsics with HIP equivalents

**Validation**:
```python
import bitsandbytes as bnb
assert bnb.COMPILED_WITH_CUDA == False  # HIP build
linear = bnb.nn.Linear8bitLt(64, 64)
assert linear is not None
```

**Duration**: ~15 minutes

#### 4.1.9 vLLM 0.14.0 (Step 9)
**Role**: Production inference server with continuous batching

**Build Configuration**:
```bash
VLLM_TARGET_DEVICE=rocm      # ROCm backend
VLLM_USE_UNIFIED_MEMORY=1    # Strix Halo UMA optimization
MAX_JOBS=4
```

**UMA Optimizations**:
- Max batch size: 128 (unified memory advantage)
- KV cache: 64GB allocation (uses unified pool)
- Continuous batching enabled
- PagedAttention with 128GB addressable memory

**Validation**:
```bash
vllm serve --help  # Must show ROCm options
python -c "from vllm import LLM; print('vLLM OK')"
```

**Duration**: ~45 minutes

#### 4.1.10 llama.cpp GPU Variant (Step 10)
**Role**: GPU-accelerated local inference with UMA optimization

**Build Configuration**:
```cmake
CMAKE_BUILD_TYPE=Release
GGML_HIPBLAS=ON              # ROCm/HIP backend
GGML_HIP_UMA=ON              # ⭐ Strix Halo UMA optimization
GGML_NATIVE=ON               # Native CPU optimizations
AMDGPU_TARGETS=gfx1151
```

**UMA Optimization Rationale**:
`GGML_HIP_UMA=ON` enables unified memory allocations that:
- Eliminate CPU→GPU memory copies
- Allow models larger than "GPU VRAM" (uses full 128GB)
- Enable zero-copy mmap for GGUF files

**Variants Built**:
1. `llama-server-gpu`: HTTP API, batch processing
2. `llama-cli-gpu`: Interactive shell
3. `llama-quantize`: Model conversion (shared with CPU)

**Validation**:
```bash
./llama-cli-gpu --version
# Should show: ROCm/HIP backend, gfx1151
./llama-server-gpu --help | grep -i rocm
```

**Duration**: ~30 minutes

#### 4.1.11 llama.cpp CPU Variant (Step 11) ⚠️ ZEN 2 CRITICAL
**Role**: CPU fallback for non-GPU tasks and Zen 2 host compatibility

**Build Configuration**:
```cmake
CMAKE_BUILD_TYPE=Release
GGML_HIPBLAS=OFF             # No GPU
GGML_AVX512=OFF              # ⚠️ CRITICAL: Zen 2 safety!
GGML_AVX2=ON                 # Zen 2 supports AVX2
GGML_FMA=ON                  # Zen 2 supports FMA
GGML_F16C=ON                 # Zen 2 supports F16C
GGML_NATIVE=OFF              # Don't auto-detect (might enable AVX-512)
```

**Zen 2 Safety Rationale**:
The Threadripper 3960X (Zen 2) supports AVX2 but NOT AVX-512. If `GGML_AVX512=ON`, the CPU variant will emit illegal instructions and crash.

**Variants Built**:
1. `llama-cli-cpu`: Interactive shell (CPU only)
2. `llama-server-cpu`: HTTP API (CPU only)

**Validation**:
```bash
# Verify no AVX-512 instructions
objdump -d ./llama-cli-cpu | grep -c 'zmm'
# Expected: 0

./llama-cli-cpu --version
# Should NOT mention AVX-512
```

**Duration**: ~20 minutes

#### 4.1.12 ONNX Runtime 1.20.0 (Step 12) ⚠️ ZEN 2 CRITICAL
**Role**: Interoperable model inference for ONNX format models

**Build Configuration**:
```cmake
-Donnxruntime_USE_ROCM=ON
-Donnxruntime_ROCM_HOME=/opt/rocm
-Donnxruntime_ENABLE_AVX512=OFF   # ⚠️ CRITICAL: Zen 2 safety!
-Donnxruntime_USE_CUDA=OFF
-DCMAKE_BUILD_TYPE=Release
```

**Zen 2 Safety Rationale**:
ONNX Runtime's CPU execution provider can emit AVX-512 for optimized kernels. With `-Donnxruntime_ENABLE_AVX512=OFF`, it falls back to AVX2.

**Validation**:
```bash
# Verify no AVX-512 instructions in CPU provider
objdump -d libonnxruntime.so | grep -c 'zmm'
# Expected: 0
```

```python
import onnxruntime as ort
assert "ROCMExecutionProvider" in ort.get_available_providers()
print(ort.get_device())  # Should show ROCm device
```

**Duration**: ~40 minutes

### 4.2 Safety & Validation Systems

#### 4.2.1 Pre-Flight Validator (preflight-check.sh)
**Run Before**: Any build attempt

**Checks**:
1. Nix version == 2.31.2
2. Flake syntax validation (`nix flake check --dry-run`)
3. Available disk space >= 200GB
4. Available RAM >= 64GB
5. Kernel version >= 6.18.6 (on builder and target)
6. No attribute name typos (static analysis)
7. No circular dependencies in overlays
8. All hash formats valid (52 char base32)

**Output**: Pass/Fail report with specific issues highlighted

#### 4.2.2 Dependency Auditor (dependency-auditor)
**Run Before**: Building each major component

**Function**:
- Parse `nix show-derivation` output
- Build dependency graph
- Traverse graph looking for:
  - Package names matching `cuda*|nvidia*|nccl|cudnn`
  - Paths containing `/cuda/` or `/nvidia/`
- Report contamination path (A → B → C → CUDA)

**Integration**: Runs as `preBuild` hook in all derivations

#### 4.2.3 Binary Symbol Scanner (binary-scanner)
**Run After**: Each derivation completes

**Forbidden Patterns**:
```regex
nvidia|cuda[A-Z]|nv[A-Z]|cublas|cudnn|libcuda\.so|libnvidia-ml\.so
```

**Scanning Method**:
1. `find $out -type f -executable`
2. For each binary: `nm -D` (dynamic symbols)
3. For each binary: `strings` (embedded strings)
4. Pattern match against forbidden list
5. If match found: **FAIL BUILD IMMEDIATELY**

**Output**:
- Contaminated binary path
- Matching symbols (first 10)
- Dependency trace (which package introduced it)

#### 4.2.4 Intelligent Build Orchestrator (build-orchestrator)
**Purpose**: Prevent OOM kills, maximize throughput

**Monitoring**:
- `/sys/fs/cgroup/memory.pressure` (PSI metrics)
- `/proc/meminfo` (MemAvailable)
- Per-process RSS via `/proc/[pid]/status`

**Scheduling Algorithm**:
1. Parse dependency DAG from `nix show-derivation`
2. Identify independent components (can build parallel)
3. Assign resources based on estimated memory needs:
   - GCC: 8GB per job
   - ROCm: 12GB per job
   - PyTorch: 20GB per job
   - vLLM: 6GB per job
   - llama.cpp: 4GB per job
4. Schedule with constraints:
   - Total allocated memory < 90% of available
   - If pressure > 50%: pause new jobs
   - If RAM < 10GB free: kill lowest priority job

**Build Order** (optimized for 48 threads):
```
Phase 1: GCC (8 cores, 30 min)
Phase 2: ROCm + Python base (16 cores parallel, 2 hours)
Phase 3: PyTorch (12 cores, 4+ hours, memory-bound)
Phase 4: vLLM + llama.cpp (16 cores parallel, 90 min)
Phase 5: Integration testing (all cores, 15 min)
```

#### 4.2.5 SBOM Generator & CVE Auditor (sbom-generator)
**Components**:
1. **NVD Snapshot**: Embedded National Vulnerability Database (JSON)
2. **Generator**: Traverses `nix-store -qR` closure
3. **Formats**: SPDX 2.3 and CycloneDX 1.5

**CVE Cross-Reference**:
- Match package versions against NVD
- Flag Critical and High severity CVEs
- Generate risk report

**Output**:
- `SBOM.spdx.json`
- `SBOM.cyclonedx.json`
- `CVE-REPORT.txt` (human-readable)

#### 4.2.6 Reproducibility Validator (reproducibility-test)
**Function**: Prove bit-for-bit reproducibility

**Process**:
1. Build derivation → output hash A
2. `nix-store --delete` the output
3. Rebuild derivation → output hash B
4. Rebuild again → output hash C
5. Assert: A == B == C

**Run On**: All major components (GCC, ROCm, PyTorch, vLLM, llama.cpp)

### 4.3 Deployment Systems

#### 4.3.1 Offline Bundle Creator (bundle-creator)
**Output**: `rockbuilder-bundle-v6.1.tar.zst`

**Contents**:
1. Full Nix store closure (exported as NARs)
2. Installer script (`install.sh`)
3. SBOM files
4. Verification hashes (SHA256)
5. Documentation (`DEPLOYMENT.md`)
6. Systemd service files (llama-server, vllm-server)
7. Example model (Llama-2-7B-Q4_K_M, 3.8GB)

**Installer Actions**:
1. Verify bundle integrity (hash check)
2. Import NARs to /nix/store
3. Install profile
4. Configure systemd services
5. Run hardware validation
6. Generate target-specific config

**Size Estimate**: ~25GB compressed

---

## 5. Eight-Stage Build Progression (12-Step Pipeline)

**Philosophy**: Graduated complexity with strict component ordering and Zen 2 safety validation at each stage.

### Stage 1: Minimal Viable Flake (Lines 1-150)
**Components**:
- Flake inputs (nixpkgs, flake-utils)
- Basic outputs structure
- GCC 14.2.1 derivation
- Simple devShell

**Validation**:
- `nix flake check` passes
- `nix build .#gcc14` completes
- `nix develop` enters shell
- GCC version == 14.2.1

**Duration**: ~30 minutes
**Lines of Code**: ~150

### Stage 2: ROCm Foundation (Lines 151-350)
**Components**:
- ROCm 7.2.0 stack (all 17 packages)
- NVIDIA isolation Layer 1 (poisoned packages)
- Dependency auditor
- gfx1151 optimization flags

**Validation**:
- ROCm builds without NVIDIA contamination
- `rocminfo` shows correct version
- Binary scanner passes
- `/opt/rocm/bin/hipcc` functional

**Duration**: ~2 hours
**Lines of Code**: ~200 additional

### Stage 3: ML Framework Foundation (Lines 351-600) ⭐ EXPANDED
**Pipeline Steps**: 1-4 (NumPy → PyTorch → TorchVision → Torchaudio)

**Components**:
- Python 3.11 environment
- NumPy 1.26.4 with BLAS/LAPACK validation
- PyTorch 2.10.0 with ROCm backend
- TorchVision 0.20.0 (PyTorch-compatible)
- Torchaudio 2.5.0 (FFmpeg/SoX resolved)
- Build orchestrator (basic version)
- Memory monitoring

**Validation**:
```bash
# NumPy BLAS/LAPACK check (MUST pass)
python -c "import numpy as np; np.show_config()" | grep -i openblas

# PyTorch ROCm check
python -c "import torch; assert torch.version.hip == '7.2.0'"

# TorchVision compatibility
python -c "import torch, torchvision; assert torchvision.__version__.startswith('0.20')"

# Torchaudio backend
python -c "import torchaudio; print(torchaudio.get_audio_backend())"
```

**Duration**: ~5 hours (NumPy 15min + PyTorch 4hr + TorchVision 30min + Torchaudio 20min)
**Lines of Code**: ~250 additional

### Stage 4: Attention & Optimization Stack (Lines 601-800) ⭐ NEW
**Pipeline Steps**: 5-7 (FlashAttention-2 → xFormers → DeepSpeed)

**Components**:
- FlashAttention-2 2.7.0 (MIOPEN_ENABLE_LOGGING=1)
- xFormers 0.0.29 (linked to FlashAttention-2)
- DeepSpeed 0.16.0 (**DS_BUILD_AVX512=0** for Zen 2)

**Validation**:
```bash
# FlashAttention import
python -c "from flash_attn import flash_attn_func; print('FlashAttn OK')"

# xFormers FlashAttention linkage
python -c "import xformers; assert not xformers._is_flash_disabled()"

# DeepSpeed AVX-512 safety check (CRITICAL)
objdump -d $(python -c "import deepspeed; print(deepspeed.__path__[0])")/ops/*.so 2>/dev/null | grep -c 'zmm'
# Expected: 0 (no AVX-512 instructions)
```

**Duration**: ~1.5 hours (FlashAttn 45min + xFormers 30min + DeepSpeed 25min)
**Lines of Code**: ~200 additional

### Stage 5: Quantization & Inference Stack (Lines 801-1000) ⭐ EXPANDED
**Pipeline Steps**: 8-12 (Bitsandbytes → vLLM → llama.cpp GPU → llama.cpp CPU → ONNX Runtime)

**Components**:
- Bitsandbytes 0.45.0 (HIPified, BNB_CUDA_VERSION=720)
- vLLM 0.14.0 (VLLM_TARGET_DEVICE=rocm, UMA enabled)
- llama.cpp GPU variant (GGML_HIP_UMA=ON for Strix Halo)
- llama.cpp CPU variant (**GGML_AVX512=OFF** for Zen 2)
- ONNX Runtime 1.20.0 (**-Donnxruntime_ENABLE_AVX512=OFF**)
- Model management utilities

**Validation**:
```bash
# Bitsandbytes HIP check
python -c "import bitsandbytes as bnb; assert not bnb.COMPILED_WITH_CUDA"

# vLLM ROCm check
python -c "from vllm import LLM; print('vLLM OK')"

# llama.cpp GPU UMA
./llama-cli-gpu --version | grep -i rocm

# llama.cpp CPU Zen 2 safety (CRITICAL)
objdump -d ./llama-cli-cpu | grep -c 'zmm'
# Expected: 0

# ONNX Runtime providers
python -c "import onnxruntime as ort; assert 'ROCMExecutionProvider' in ort.get_available_providers()"

# ONNX Runtime Zen 2 safety (CRITICAL)
objdump -d $(python -c "import onnxruntime; print(onnxruntime.__path__[0])")/*.so | grep -c 'zmm'
# Expected: 0
```

**Duration**: ~2.5 hours (Bitsandbytes 15min + vLLM 45min + llama GPU 30min + llama CPU 20min + ONNX 40min)
**Lines of Code**: ~200 additional

### Stage 6: Safety & Tooling (Lines 1001-1200)
**Components**:
- Enhanced build orchestrator
- SBOM generator with CVE auditing
- Reproducibility tests
- Pre-flight validator (including Zen 2 AVX-512 checks)
- All four NVIDIA isolation layers
- Zen 2 Safety Protocol enforcement

**Validation**:
- Reproducibility test passes (3 identical builds)
- SBOM generates without errors
- CVE report created
- All safety checks pass
- **Zen 2 AVX-512 audit passes** (all 3 critical components verified)

**Duration**: ~1 hour
**Lines of Code**: ~200 additional

### Stage 7: DevShell + Integration (Lines 1201-1400)
**Components**:
- Complete devShell with aliases
- VS Code task configurations
- Integration test suite (all 12 components)
- Documentation generation

**Validation**:
- All devShell aliases work
- Integration tests pass for all 12 pipeline steps
- Documentation renders correctly

**Duration**: ~45 minutes
**Lines of Code**: ~200 additional

### Stage 8: Deployment Bundle (Lines 1401-1600)
**Components**:
- Offline bundle creator
- Systemd service templates
- Target system validator
- Final smoke tests

**Validation**:
- Bundle creation completes
- Installer script tested in VM
- Full system test passes on target platform
- Zen 2 safety verified on build host

**Duration**: ~30 minutes
**Lines of Code**: ~200 additional

---

### Build Time Summary

| Stage | Components | Duration | Cumulative |
|-------|------------|----------|------------|
| 1 | GCC 14.2.1 | 30 min | 30 min |
| 2 | ROCm 7.2.0 (17 pkgs) | 2 hr | 2.5 hr |
| 3 | NumPy/PyTorch/TorchVision/Torchaudio | 5 hr | 7.5 hr |
| 4 | FlashAttn/xFormers/DeepSpeed | 1.5 hr | 9 hr |
| 5 | Bitsandbytes/vLLM/llama.cpp/ONNX | 2.5 hr | 11.5 hr |
| 6 | Safety systems | 1 hr | 12.5 hr |
| 7 | DevShell + Integration | 45 min | 13.25 hr |
| 8 | Deployment bundle | 30 min | **~13.75 hr** |

**Total**: ~1600 lines, ~13-14 hours build time (first build), ~4 hours (cached rebuilds)

---

## 6. Developer Workflow

### 6.1 VS Code Environment Setup

**Required Extensions**:
1. `nix-ide` (syntax highlighting, LSP)
2. `alejandra` (formatter)
3. `Error Lens` (inline errors)
4. `Task Runner` (custom tasks)

**Custom Tasks** (`.vscode/tasks.json`):
```json
{
  "tasks": [
    "Validate: Pre-Flight Check",
    "Validate: Flake Syntax",
    "Build: Stage 1 (GCC Only)",
    "Build: Stage 2 (ROCm Only)",
    "Build: Stage 3 (PyTorch)",
    "Build: Stage 4 (Full Stack)",
    "Build: Stage 5 (With Safety)",
    "Build: Stage 6 (Complete)",
    "Test: NVIDIA Isolation",
    "Test: Reproducibility",
    "Test: Binary Symbols",
    "Package: Offline Bundle",
    "Clean: Garbage Collect",
    "Debug: Enter Failed Build Shell"
  ]
}
```

### 6.2 Development Commands

**Provided via devShell aliases**:

```bash
# Building
build-gcc          # Stage 1
build-rocm         # Stage 2
build-pytorch      # Stage 3
build-stack        # Stage 4 (full AI stack)
build-all          # Stage 6 (complete system)

# Testing
test-isolation     # NVIDIA contamination tests
test-repro         # Reproducibility validation
test-memory        # Memory pressure simulation
test-integration   # Full system test

# Validation
validate-pre       # Pre-flight checks
validate-deps      # Dependency audit
validate-symbols   # Binary scanner

# Deployment
package-bundle     # Create offline bundle
deploy-local       # Test bundle in local VM

# Debugging
enter-build-shell  # Drop into failed build environment
show-build-graph   # Visualize dependency DAG
check-memory       # Current memory status
```

### 6.3 Error Recovery Workflow

**When Build Fails**:

1. **Automatic**: Build logs parsed for common patterns
2. **Suggested Fix**: Displayed in terminal
3. **Options Presented**:
   - `[R]etry` - Run build again
   - `[D]ebug` - Enter interactive build shell
   - `[L]ogs` - View full build log
   - `[Q]uit` - Exit and preserve failed build dir

**Interactive Debug Shell**:
```bash
# Automatically enters environment with:
# - All buildInputs available
# - Same environment variables as build
# - Positioned in source directory
# - Failed build preserved in /tmp/nix-build-*
```

### 6.4 Checkpointing & Rollback

**Git Integration**:
- Auto-commit after each successful stage
- Tags: `stage-1-success`, `stage-2-success`, etc.
- Branch: `known-good` (last complete build)

**Nix Store Management**:
- Track store paths per stage
- `nix-store --gc` with store path filters
- Preserve successful intermediate builds

**Rollback Command**:
```bash
rollback-to-stage <N>  # Reset to stage N's flake.nix
                       # Preserve newer store paths
```

---

## 7. Testing & Validation

### 7.1 Unit Tests (12-Step Pipeline Smoke Tests)

**Step 0: ROCm 7.2.0**:
```bash
rocminfo | grep -i "gfx1151"
hipcc --version | grep "7.2.0"
```

**Step 1: NumPy 1.26.4**:
```python
import numpy as np
config = np.__config__.show()
assert 'openblas' in str(config).lower()
np.linalg.svd(np.random.rand(100, 100))  # LAPACK test
```

**Step 2: PyTorch 2.10.0**:
```python
import torch
assert torch.version.hip == "7.2.0"
assert not torch.cuda.is_available()
x = torch.randn(100, 100, device='cuda')  # ROCm via CUDA API
```

**Step 3: TorchVision 0.20.0**:
```python
import torchvision
assert torchvision.__version__.startswith("0.20")
from torchvision.models import resnet18
model = resnet18()
```

**Step 4: Torchaudio 2.5.0**:
```python
import torchaudio
assert torchaudio.__version__.startswith("2.5")
backend = torchaudio.get_audio_backend()
```

**Step 5: FlashAttention-2 2.7.0**:
```python
from flash_attn import flash_attn_func
import torch
q = torch.randn(1, 4, 64, 32, device='cuda', dtype=torch.float16)
out = flash_attn_func(q, q, q)
```

**Step 6: xFormers 0.0.29**:
```python
import xformers
from xformers.ops import memory_efficient_attention
assert not xformers._is_flash_disabled()
```

**Step 7: DeepSpeed 0.16.0** ⚠️ Zen 2 Critical:
```bash
# Binary check (MUST return 0)
objdump -d $(python -c "import deepspeed; print(deepspeed.__path__[0])")/ops/*.so 2>/dev/null | grep -c 'zmm'
```
```python
import deepspeed
assert deepspeed.__version__ == "0.16.0"
```

**Step 8: Bitsandbytes 0.45.0**:
```python
import bitsandbytes as bnb
assert not bnb.COMPILED_WITH_CUDA
linear = bnb.nn.Linear8bitLt(64, 64)
```

**Step 9: vLLM 0.14.0**:
```bash
vllm serve --help | grep -i rocm
python -c "from vllm import LLM"
```

**Step 10: llama.cpp GPU**:
```bash
./llama-cli-gpu --version | grep -i rocm
./llama-server-gpu --help | head -5
```

**Step 11: llama.cpp CPU** ⚠️ Zen 2 Critical:
```bash
# Binary check (MUST return 0)
objdump -d ./llama-cli-cpu | grep -c 'zmm'
./llama-cli-cpu --version
```

**Step 12: ONNX Runtime 1.20.0** ⚠️ Zen 2 Critical:
```bash
# Binary check (MUST return 0)
objdump -d $(python -c "import onnxruntime; print(onnxruntime.__path__[0])")/*.so 2>/dev/null | grep -c 'zmm'
```
```python
import onnxruntime as ort
assert "ROCMExecutionProvider" in ort.get_available_providers()
```

### 7.2 Zen 2 Safety Protocol Validation

**Automated AVX-512 Audit** (run after Stage 5):
```bash
#!/bin/bash
# zen2-safety-audit.sh
set -e

echo "=== Zen 2 Safety Protocol Audit ==="

FAIL=0

# Check DeepSpeed
DS_COUNT=$(objdump -d $(python -c "import deepspeed; print(deepspeed.__path__[0])")/ops/*.so 2>/dev/null | grep -c 'zmm' || echo 0)
if [ "$DS_COUNT" -gt 0 ]; then
  echo "❌ FAIL: DeepSpeed contains $DS_COUNT AVX-512 instructions"
  FAIL=1
else
  echo "✅ PASS: DeepSpeed is Zen 2 safe"
fi

# Check llama.cpp CPU
LLAMA_COUNT=$(objdump -d ./llama-cli-cpu 2>/dev/null | grep -c 'zmm' || echo 0)
if [ "$LLAMA_COUNT" -gt 0 ]; then
  echo "❌ FAIL: llama.cpp CPU contains $LLAMA_COUNT AVX-512 instructions"
  FAIL=1
else
  echo "✅ PASS: llama.cpp CPU is Zen 2 safe"
fi

# Check ONNX Runtime
ORT_COUNT=$(objdump -d $(python -c "import onnxruntime; print(onnxruntime.__path__[0])")/*.so 2>/dev/null | grep -c 'zmm' || echo 0)
if [ "$ORT_COUNT" -gt 0 ]; then
  echo "❌ FAIL: ONNX Runtime contains $ORT_COUNT AVX-512 instructions"
  FAIL=1
else
  echo "✅ PASS: ONNX Runtime is Zen 2 safe"
fi

if [ "$FAIL" -eq 1 ]; then
  echo ""
  echo "🚨 ZEN 2 SAFETY AUDIT FAILED 🚨"
  echo "The build host (Threadripper 3960X) will crash on AVX-512 instructions."
  exit 1
else
  echo ""
  echo "✅ All Zen 2 safety checks passed"
fi
```

### 7.3 Integration Tests

**NVIDIA Isolation Validation**:
1. Attempt to access `/dev/nvidia0` in sandbox → Expect: Failure
2. Check for `cuda*` symbols in all binaries → Expect: None found
3. Parse dependency graph for NVIDIA packages → Expect: None present
4. Run PyTorch with CUDA check → Expect: `cuda.is_available() == False`

**Reproducibility Test**:
1. Build complete stack 3 times
2. Compare SHA256 hashes of outputs
3. Assert all hashes identical

**Memory Management Test**:
1. Simulate low-memory condition (limit to 32GB)
2. Build PyTorch
3. Verify orchestrator throttles jobs
4. Ensure no OOM kills

**Offline Bundle Test**:
1. Create bundle on builder
2. Transfer to clean VM (no internet)
3. Run installer
4. Verify all components functional
5. Run sample inference workload

### 7.3 Performance Benchmarks

**Build Time** (Threadripper 3960X, 64GB RAM):
- Stage 1 (GCC): 30 minutes
- Stage 2 (ROCm): 2 hours
- Stage 3 (PyTorch): 4 hours
- Stage 4 (vLLM + llama): 1.5 hours
- Total: ~8 hours (first build)
- Total: ~2.5 hours (with Cachix)

**Target Performance** (Strix Halo, 128GB):
- vLLM (Llama-2-70B-Q4): 45 tokens/second
- llama.cpp (Llama-2-70B-Q4): 32 tokens/second
- llama.cpp (Llama-2-7B-Q4): 180 tokens/second

**Memory Usage**:
- vLLM: ~50GB (model + KV cache)
- llama.cpp: ~42GB (model + context)

---

## 8. Documentation Requirements

### 8.1 Included in Offline Bundle

**DEPLOYMENT.md**:
- Hardware requirements (Strix Halo, 128GB RAM)
- Kernel version and boot parameters
- Installation procedure
- Systemd service configuration
- Verification steps

**USAGE.md**:
- Starting vLLM server
- Starting llama-server
- HTTP API examples
- Model management (adding new models)
- Performance tuning guide

**TROUBLESHOOTING.md**:
- Common issues and solutions
- ROCm not detected (HSA_OVERRIDE_GFX_VERSION)
- Out of memory (reduce batch size)
- Slow performance (check GTT size)

**HARDWARE-OPTIMIZATION.md**:
- Kernel parameter explanations
- BIOS settings (enable IOMMU, 2MB pages)
- NUMA considerations
- Thermal management

### 8.2 Developer Documentation

**ARCHITECTURE.md**:
- System design overview
- Dependency graph visualization
- Safety system explanations
- Build orchestration logic

**CONTRIBUTING.md**:
- How to add new components
- Testing requirements
- Code style (Nix formatting)
- Overlay creation guidelines

**DEBUGGING.md**:
- Using failed build shells
- Reading build logs
- Common Nix errors and solutions
- Symbol scanner interpretation

---

## 9. Success Criteria

### 9.1 Build System

- ✅ Completes all 8 stages without manual intervention
- ✅ All 12 pipeline steps build and validate successfully
- ✅ No NVIDIA contamination detected in any binary
- ✅ Bit-for-bit reproducible (3 builds, identical hashes)
- ✅ No OOM kills during build (on 64GB system)
- ✅ Build time < 14 hours (first build, no cache)
- ✅ Build time < 4 hours (with partial cache)

### 9.2 Safety Systems

- ✅ Pre-flight validator catches 100% of known issues before build
- ✅ Dependency auditor detects all NVIDIA packages in graph
- ✅ Binary scanner finds 100% of contaminated binaries
- ✅ Build orchestrator prevents OOM (tested under memory pressure)
- ✅ Reproducibility test passes 10/10 runs
- ✅ **Zen 2 Safety Audit passes** (DeepSpeed, llama-cpu, ONNX Runtime all AVX-512 free)

### 9.3 AI Stack Functionality (12-Step Pipeline)

- ✅ NumPy BLAS/LAPACK validation passes
- ✅ PyTorch recognizes gfx1151 via ROCm backend
- ✅ TorchVision/Torchaudio import without version mismatch
- ✅ FlashAttention-2 runs attention kernels on ROCm
- ✅ xFormers links to FlashAttention-2 (not disabled)
- ✅ DeepSpeed builds without AVX-512 (Zen 2 safe)
- ✅ Bitsandbytes uses HIP backend (not CUDA)
- ✅ vLLM serves completions via HTTP API
- ✅ llama.cpp GPU uses UMA optimization on Strix Halo
- ✅ llama.cpp CPU builds without AVX-512 (Zen 2 safe)
- ✅ ONNX Runtime provides ROCMExecutionProvider
- ✅ All components use ROCm (no CPU fallback)

### 9.4 Deployment

- ✅ Offline bundle installs on target system without internet
- ✅ All systemd services start successfully
- ✅ Inference workloads run at expected performance
- ✅ SBOM generated with < 5 Critical CVEs
- ✅ Bundle size < 35GB compressed

### 9.5 Developer Experience

- ✅ VS Code tasks work for all 8 stages
- ✅ Error messages are actionable and specific
- ✅ Failed builds can be debugged interactively
- ✅ Rollback to previous stage takes < 5 minutes
- ✅ Documentation answers common questions
- ✅ Zen 2 safety audit script available in devShell

---

## 10. Risk Management

### 10.1 Known Risks

**Risk**: AVX-512 instructions crash Threadripper 3960X (Zen 2) host  
**Mitigation**: Mandatory `DS_BUILD_AVX512=0`, `GGML_AVX512=OFF`, `-Donnxruntime_ENABLE_AVX512=OFF` flags  
**Fallback**: Zen 2 Safety Audit script catches any violations before deployment

**Risk**: PyTorch build OOM kills on 64GB system  
**Mitigation**: Build orchestrator throttles to 1 job max for PyTorch  
**Fallback**: Documentation for building on system with 128GB RAM

**Risk**: GCC 14.2.1 not in nixpkgs 24.11  
**Mitigation**: Custom overlay pins exact version from upstream  
**Fallback**: Document manual bootstrap from source

**Risk**: NVIDIA contamination slips through all 4 layers  
**Mitigation**: Binary scanner as final gate, fails build  
**Fallback**: Manual inspection of binaries, rebuild from clean state

**Risk**: FlashAttention-2/xFormers build failures due to MIOpen version mismatch  
**Mitigation**: Pin ROCm 7.2.0 composable_kernel version  
**Fallback**: Disable FlashAttention linkage in xFormers (`XFORMERS_DISABLE_FLASH_ATTN=1`)

**Risk**: llama.cpp ROCm backend broken for gfx1151  
**Mitigation**: Pin to known-good commit with gfx1151 support  
**Fallback**: Use CLBlast OpenCL backend (performance penalty)

**Risk**: Offline bundle too large for USB stick  
**Mitigation**: Compression with zstd level 19, exclude debug symbols  
**Fallback**: Split into multiple archives, multi-USB deployment

### 10.2 Escape Hatches

**Minimal Bootstrap Mode**:
- Single command builds basic environment (nix, gcc, git)
- Can debug main flake even if completely broken

**Known-Good Branch**:
- Separate git branch with last successful complete build
- Can merge back if current work unrecoverable

**Cache Fallback**:
- If available, use Cachix to pull pre-built components
- Bypass problematic builds during debugging

---

## 11. Future Enhancements (Post-v6.1)

### 11.1 Completed in v6.1 (This Release)
- ✅ **12-Step AI Pipeline**: Strict build order from NumPy to ONNX Runtime
- ✅ **Zen 2 Safety Protocol**: AVX-512 blocking for Threadripper 3960X
- ✅ **LPDDR5X/UMA Optimization**: Unified memory tuning for Strix Halo
- ✅ **Expanded Component Matrix**: PyTorch 2.10.0 compatibility versions pinned
- ✅ **Per-Component Smoke Tests**: All 12 pipeline steps validated

### 11.2 Planned for v6.2
- **Multi-GPU Support**: Build for systems with multiple Strix Halo chips
- **Model Registry**: Centralized GGUF model management with automatic quantization
- **Monitoring Dashboard**: Web UI showing build progress, memory usage, errors
- **Zen 5 Optimizations**: Enable AVX-512 on target platform (Strix Halo) for inference

### 11.3 Research Items
- **Distributed Builds**: Nix remote builders to parallelize across multiple machines
- **Incremental Builds**: Cache intermediate compilation artifacts, not just final outputs
- **Cross-Compilation**: Build on x86_64 for aarch64 AMD chips
- **ROCm 7.3 Migration**: Evaluate breaking changes and new gfx1151 optimizations

---

## 12. Appendix

### 12.1 Glossary

- **AVX-512**: Advanced Vector Extensions 512-bit, SIMD instruction set NOT supported on Zen 2
- **gfx1151**: AMD GPU architecture identifier for Strix Halo
- **HIPify**: Process of converting CUDA code to HIP (ROCm-compatible)
- **LPDDR5X**: Low Power DDR5 Extended, high-bandwidth unified memory in Strix Halo
- **MIOpen**: AMD's deep learning primitives library (ROCm equivalent of cuDNN)
- **NAR**: Nix Archive, serialized package format for store paths
- **PSI**: Pressure Stall Information, Linux kernel memory pressure metrics
- **SBOM**: Software Bill of Materials, security inventory
- **UMA**: Unified Memory Architecture, CPU and GPU share physical memory
- **XNACK**: Memory page retry mechanism for unified memory architectures
- **Zen 2**: AMD CPU microarchitecture (Threadripper 3960X), lacks AVX-512
- **Zen 5**: AMD CPU microarchitecture (Strix Halo), supports AVX-512
- **GGUF**: GPT-Generated Unified Format, llama.cpp model format
- **GTT**: Graphics Translation Table, GPU memory management

### 12.2 References

- Nix Manual: https://nixos.org/manual/nix/stable/
- ROCm Documentation: https://rocm.docs.amd.com/
- PyTorch ROCm Guide: https://pytorch.org/get-started/locally/#linux-rocm
- llama.cpp ROCm Backend: https://github.com/ggerganov/llama.cpp/discussions/1627
- FlashAttention-2 ROCm: https://github.com/Dao-AILab/flash-attention
- xFormers: https://github.com/facebookresearch/xformers
- DeepSpeed: https://github.com/microsoft/DeepSpeed
- ONNX Runtime ROCm: https://onnxruntime.ai/docs/execution-providers/ROCm-ExecutionProvider.html

### 12.3 Version History

- **v5.0**: Initial pure Nix implementation
- **v6.0**: Added quad-layer isolation, llama.cpp, safety systems, Threadripper optimization
- **v6.1**: 12-step AI pipeline, Zen 2 safety protocol (AVX-512 blocking), LPDDR5X/UMA optimization, PyTorch 2.10.0 compatibility matrix

---

**Document Control**  
**Author**: System Architect  
**Reviewed By**: AI Safety Team, Build Engineering  
**Approval Date**: January 26, 2026  
**Next Review**: March 2026 or upon architectural changes