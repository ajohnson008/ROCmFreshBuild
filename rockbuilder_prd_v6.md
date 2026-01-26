# TheRockBuilder PRD v6.0: Production-Grade Nix Reconstruction with Advanced Safety Systems

**Project Code**: THE_ROCK_BUILDER_REBOOT  
**Target Platform**: AMD Strix Halo (gfx1151) on GMKtec EVO-X2  
**Build Platform**: AMD Threadripper 3960X (24C/48T, 64GB RAM, RTX 3080 Ti)  
**Build System**: Nix Flakes (Nix 2.31.2+)  
**Version**: 6.0 (Supersedes v5.0)  
**Document Date**: January 26, 2026

---

## 1. Executive Summary

TheRockBuilder v6.0 is a **production-hardened, air-gapped AI infrastructure build system** designed to compile a bit-for-bit reproducible AI stack for AMD Strix Halo architecture. This version introduces:

- **Quad-Layer NVIDIA Isolation**: Prevents any CUDA contamination from builder's RTX 3080 Ti
- **Integrated llama.cpp**: Optimized local inference alongside vLLM production stack
- **Advanced Safety Systems**: Pre-flight validation, build checkpointing, and intelligent error recovery
- **Threadripper Optimization**: Parallel builds utilizing all 48 threads with memory-aware scheduling
- **Graduated Complexity**: Six-stage build progression with independent validation at each level

Unlike v5.0's pure focus on reproducibility, v6.0 emphasizes **developer experience, build safety, and operational resilience** while maintaining strict reproducibility guarantees.

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

### 2.4 AI Stack Versions
- **ROCm**: 7.2.0
- **PyTorch**: 2.10.0 (ROCm backend only)
- **vLLM**: 0.14.0
- **llama.cpp**: Commit a33e6a0d (January 2025, ROCm 6.2+ support branch)

### 2.5 Quantization Standards
- **Primary**: Q4_K_M (optimal for 64-128GB VRAM)
- **High Quality**: Q5_K_M (for smaller models)
- **Maximum Quality**: Q8_0 (near-fp16, critical tasks only)

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
flake.nix (lines 1-50):      Inputs, system boilerplate
flake.nix (lines 51-200):    Core derivations (GCC, ROCm, PyTorch, vLLM)
flake.nix (lines 201-350):   llama.cpp derivations
flake.nix (lines 351-500):   Tooling (orchestrator, SBOM, scanners)
flake.nix (lines 501-700):   Safety systems (validators, auditors)
flake.nix (lines 701-900):   Outputs (packages, devShells, apps)
flake.nix (lines 901-1000):  Tests and verification
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

## 4. Component Specifications

### 4.1 Core AI Stack

#### 4.1.1 ROCm 7.2.0
**Requirements**:
- GCC 14.2.1 (strict dependency)
- No CUDA headers in include path
- HIP runtime for gfx1151

**Validation**:
- `/opt/rocm/bin/rocminfo` shows gfx1151
- `hipcc --version` reports 7.2.0
- No symbols matching `cuda*` in any .so file

#### 4.1.2 PyTorch 2.10.0 (ROCm Backend)
**Build Configuration**:
```
USE_CUDA=0
USE_ROCM=1
PYTORCH_ROCM_ARCH=gfx1151
BUILD_CAFFE2=0              # Reduce build time
BUILD_TEST=0                # Skip tests during build
```

**Memory Requirements**:
- Peak build: ~45GB RAM
- Orchestrator must throttle concurrent jobs

**Validation**:
```python
import torch
assert torch.version.hip == "7.2.0"
assert not torch.cuda.is_available()  # Must be False
assert torch.cuda.get_device_name(0) == "gfx1151"  # ROCm device
```

#### 4.1.3 vLLM 0.14.0
**Purpose**: Batched inference, production API server

**Optimizations**:
- Max batch size: 128 (unified memory advantage)
- KV cache: 64GB allocation
- Continuous batching enabled

#### 4.1.4 llama.cpp (ROCm/HIP Backend)
**Purpose**: Local inference, interactive use, quantized models

**Build Variants**:
1. **llama-server**: HTTP API, batch processing focus
2. **llama-cli**: Interactive shell, low-latency focus
3. **llama-quantize**: Model conversion utilities

**Backend Selection**:
- Use ROCm/HIP (not CLBlast/OpenCL)
- Static link ROCm libraries to avoid runtime deps

**Optimizations**:
```
CMAKE_BUILD_TYPE=Release
LLAMA_HIPBLAS=ON
LLAMA_NATIVE=ON              # Native CPU optimizations
AMDGPU_TARGETS=gfx1151
```

**Context Length**:
- Default: 32k tokens
- Extended: 128k tokens (utilizing full 128GB)

**Model Loading**:
- mmap enabled (zero-copy from disk)
- Huge pages support
- Pre-warm weights on first load

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
**Output**: `rockbuilder-bundle-v6.0.tar.zst`

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

## 5. Six-Stage Build Progression

**Philosophy**: Graduated complexity with independent validation at each stage.

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
- ROCm 7.2.0 derivation
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

### Stage 3: Python + PyTorch (Lines 351-550)
**Components**:
- Python 3.11 environment
- PyTorch 2.10.0 with ROCm backend
- Build orchestrator (basic version)
- Memory monitoring

**Validation**:
- PyTorch imports successfully
- `torch.version.hip == "7.2.0"`
- No OOM kills during build
- Symbol scanner passes

**Duration**: ~4 hours
**Lines of Code**: ~200 additional

### Stage 4: AI Stack Integration (Lines 551-750)
**Components**:
- vLLM 0.14.0
- llama.cpp (server + cli)
- Model management utilities
- Integration tests

**Validation**:
- vLLM runs simple inference
- llama-server responds to HTTP requests
- Both use ROCm backend
- No CUDA symbols anywhere

**Duration**: ~2 hours
**Lines of Code**: ~200 additional

### Stage 5: Safety & Tooling (Lines 751-950)
**Components**:
- Enhanced build orchestrator
- SBOM generator with CVE auditing
- Reproducibility tests
- Pre-flight validator
- All four NVIDIA isolation layers

**Validation**:
- Reproducibility test passes (3 identical builds)
- SBOM generates without errors
- CVE report created
- All safety checks pass

**Duration**: ~1 hour
**Lines of Code**: ~200 additional

### Stage 6: DevShell + Deployment (Lines 951-1100)
**Components**:
- Complete devShell with aliases
- Offline bundle creator
- Documentation generation
- Systemd service templates
- Final integration tests

**Validation**:
- Bundle creation completes
- Installer script tested in VM
- All devShell aliases work
- Full system test passes

**Duration**: ~1 hour
**Lines of Code**: ~150 additional

**Total**: ~1100 lines, ~11 hours build time (first build), ~3 hours (cached rebuilds)

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

### 7.1 Unit Tests (Per Component)

**GCC 14.2.1**:
- Version verification
- C++20 feature compilation test
- ROCm compatibility test

**ROCm 7.2.0**:
- `rocminfo` output parsing
- HIP runtime initialization
- gfx1151 detection

**PyTorch 2.10.0**:
- Import test
- ROCm backend verification
- Simple tensor operation on GPU

**vLLM 0.14.0**:
- Server startup
- Simple completion request
- Batch processing test

**llama.cpp**:
- Model loading (GGUF format)
- Single inference
- HTTP API test

### 7.2 Integration Tests

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

- ✅ Completes all 6 stages without manual intervention
- ✅ No NVIDIA contamination detected in any binary
- ✅ Bit-for-bit reproducible (3 builds, identical hashes)
- ✅ No OOM kills during build (on 64GB system)
- ✅ Build time < 10 hours (first build, no cache)
- ✅ Build time < 3 hours (with partial cache)

### 9.2 Safety Systems

- ✅ Pre-flight validator catches 100% of known issues before build
- ✅ Dependency auditor detects all NVIDIA packages in graph
- ✅ Binary scanner finds 100% of contaminated binaries
- ✅ Build orchestrator prevents OOM (tested under memory pressure)
- ✅ Reproducibility test passes 10/10 runs

### 9.3 AI Stack Functionality

- ✅ PyTorch recognizes gfx1151 via ROCm backend
- ✅ vLLM serves completions via HTTP API
- ✅ llama.cpp loads and runs GGUF models
- ✅ All components use ROCm (no CPU fallback)
- ✅ Memory usage within expected bounds

### 9.4 Deployment

- ✅ Offline bundle installs on target system without internet
- ✅ All systemd services start successfully
- ✅ Inference workloads run at expected performance
- ✅ SBOM generated with < 5 Critical CVEs

### 9.5 Developer Experience

- ✅ VS Code tasks work for all stages
- ✅ Error messages are actionable and specific
- ✅ Failed builds can be debugged interactively
- ✅ Rollback to previous stage takes < 5 minutes
- ✅ Documentation answers common questions

---

## 10. Risk Management

### 10.1 Known Risks

**Risk**: PyTorch build OOM kills on 64GB system  
**Mitigation**: Build orchestrator throttles to 1 job max for PyTorch  
**Fallback**: Documentation for building on system with 128GB RAM

**Risk**: GCC 14.2.1 not in nixpkgs 24.11  
**Mitigation**: Custom overlay pins exact version from upstream  
**Fallback**: Document manual bootstrap from source

**Risk**: NVIDIA contamination slips through all 4 layers  
**Mitigation**: Binary scanner as final gate, fails build  
**Fallback**: Manual inspection of binaries, rebuild from clean state

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

## 11. Future Enhancements (Post-v6.0)

### 11.1 Planned for v6.1
- **Multi-GPU Support**: Build for systems with multiple Strix Halo chips
- **Model Registry**: Centralized GGUF model management with automatic quantization
- **Monitoring Dashboard**: Web UI showing build progress, memory usage, errors

### 11.2 Research Items
- **Distributed Builds**: Nix remote builders to parallelize across multiple machines
- **Incremental Builds**: Cache intermediate compilation artifacts, not just final outputs
- **Cross-Compilation**: Build on x86_64 for aarch64 AMD chips

---

## 12. Appendix

### 12.1 Glossary

- **gfx1151**: AMD GPU architecture identifier for Strix Halo
- **XNACK**: Memory page retry mechanism for unified memory architectures
- **GTT**: Graphics Translation Table, GPU memory management
- **PSI**: Pressure Stall Information, Linux kernel memory pressure metrics
- **NAR**: Nix Archive, serialized package format for store paths
- **SBOM**: Software Bill of Materials, security inventory
- **GGUF**: GPT-Generated Unified Format, llama.cpp model format

### 12.2 References

- Nix Manual: https://nixos.org/manual/nix/stable/
- ROCm Documentation: https://rocm.docs.amd.com/
- PyTorch ROCm Guide: https://pytorch.org/get-started/locally/#linux-rocm
- llama.cpp ROCm Backend: https://github.com/ggerganov/llama.cpp/discussions/1627

### 12.3 Version History

- **v5.0**: Initial pure Nix implementation
- **v6.0**: Added quad-layer isolation, llama.cpp, safety systems, Threadripper optimization

---

**Document Control**  
**Author**: System Architect  
**Reviewed By**: AI Safety Team, Build Engineering  
**Approval Date**: January 26, 2026  
**Next Review**: March 2026 or upon architectural changes