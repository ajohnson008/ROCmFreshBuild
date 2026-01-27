# ROCm 7.2.0 on AMD Strix Halo (gfx1151) - Runtime Limitations

## Status Overview (Jan 27 2026)

**Build Status**: ✅ SUCCESS
**Runtime Status**: ⚠️ EXPERIMENTAL / UNSTABLE

All components in this stack are compiled with explicit `-DAMDGCN_TARGETS=gfx1151` (and compatible fallbacks). However, as of ROCm 7.2.0, the Strix Halo architecture (gfx1151) is not fully supported by the runtime stack, particularly regarding unified memory management and topology detection.

## Known Critical Issues

### 1. Unified Memory Corruption
*   **Symptom**: Silent data corruption or `HSA_STATUS_ERROR_MEMORY_FAULT` during large tensor operations.
*   **Cause**: ROCm HSA runtime assumes discrete VRAM (dGPU) behavior. Strix Halo uses LPDDR5X as unified memory. The current runtime memory allocators may not correctly handle cache coherency for this architecture.
*   **Workaround**:
    *   Set `HSA_ENABLE_SDMA=0`
    *   Set `HSA_DISABLE_GWS=1`
    *   Available VRAM is effectively system RAM, but allocation limits may apply.

### 2. vLLM Tensor Parallelism
*   **Symptom**: vLLM fails to initialize with `ValueError: Rank ...` or hangs.
*   **Cause**: RCCL (ROCm Communication Collectives Library) lacks a topology definition for gfx1151, causing it to fail ring setup.
*   **Workaround**: Tensor parallelism is **DISABLED**. Run vLLM with `--tensor-parallel-size 1`.

### 3. Kernel Launch Failures
*   **Symptom**: `hipErrorNoBinaryForGpu`
*   **Cause**: Some libraries (especially older or closed-source ones like MIOpen) may strictly check for `gfx1103` or `gfx1100` binaries and fail to load `gfx1151` code even if present, or `gfx1151` code is missing from specific pre-built kernels.
*   **Workaround**: The build injects `LLVM_AMDGPU_ALLOW_NAKED_POINTER=ON` and forces fallback targets (`gfx1103`, `gfx1100`) to maximize compatibility.

## Support Policy

This build is provided for **development and testing only**. Do not use for production inference. Full production support for Strix Halo is expected in ROCm 7.3 (Q1 2026).
