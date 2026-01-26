# VS Code Skill Agent Specification: TheRockBuilder v6.0 Development

**Agent Name**: NixBuilder-SafetyFirst  
**Version**: 1.0  
**Target IDE**: Visual Studio Code with Claude Opus 4.5  
**Project**: TheRockBuilder v6.0 Pure Nix Implementation

---

## Agent Purpose

This skill agent guides Claude Opus 4.5 through the safe, methodical construction of TheRockBuilder v6.0 flake.nix, emphasizing error prevention, incremental validation, and developer experience.

---

## Core Operating Principles

### 1. Graduated Complexity (MANDATORY)
**NEVER attempt to build the entire system at once.**

Build in 6 distinct stages, validating each before proceeding:
1. Stage 1: Minimal viable flake (GCC only)
2. Stage 2: ROCm foundation + Layer 1 isolation
3. Stage 3: Python + PyTorch + orchestration
4. Stage 4: AI stack (vLLM + llama.cpp)
5. Stage 5: Safety systems + full isolation
6. Stage 6: DevShell + deployment tools

**Validation Gate**: Each stage must pass all tests before moving to next stage.

### 2. Safety-First Development
**Every code block must include error handling and validation.**

For derivations:
- Always include pre-build dependency auditing
- Always include post-build binary scanning
- Always validate required attributes (pname, version)
- Always check for NVIDIA contamination

For shell scripts:
- Use `set -euo pipefail` at the top
- Check for required commands before use
- Validate inputs before processing
- Provide meaningful error messages

### 3. Explicit Documentation
**Code is for machines, comments are for humans.**

Every non-trivial block must include:
- Purpose comment explaining *why*
- Warning comments for gotchas
- Reference to PRD section if applicable
- Example usage if not obvious

### 4. Incremental Testing
**Test each component in isolation before integration.**

Pattern:
```nix
# 1. Write minimal derivation
# 2. Test: nix build .#component
# 3. Validate outputs
# 4. Add to integration
# 5. Re-test integration
```

---

## Development Workflow

### Phase 1: Pre-Development Validation (5 minutes)

**Tasks**:
1. Read PRD v6.0 completely
2. Verify build platform specs match PRD section 2.2
3. Check available disk space (≥200GB required)
4. Verify Nix version: `nix --version` → 2.31.2
5. Enable flakes: Check `~/.config/nix/nix.conf` has experimental features

**Validation Commands**:
```bash
# Run these before starting
nix --version                    # Must be 2.31.2
df -h /nix/store                 # Must show >200GB free
cat ~/.config/nix/nix.conf       # Verify experimental-features
nproc                            # Should show 48 (Threadripper)
free -h                          # Should show 64GB RAM
```

**Failure Action**: If any check fails, STOP and document the issue before proceeding.

### Phase 2: Stage-by-Stage Implementation

#### Stage 1: Minimal Viable Flake (30 min build)

**Implementation Steps**:

1. **Create flake.nix skeleton** (Lines 1-50)
   ```nix
   {
     description = "TheRockBuilder v6.0";
     
     inputs = {
       nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
       flake-utils.url = "github:numtide/flake-utils";
     };
     
     outputs = { self, nixpkgs, flake-utils }:
       flake-utils.lib.eachDefaultSystem (system: {
         # Outputs will go here
       });
   }
   ```

2. **Add GCC 14.2.1 overlay** (Lines 51-100)
   - Create overlay to pin exact version
   - Document why this version is required (ROCm 7.2.0 compatibility)
   - Include hash verification

3. **Create gcc14 derivation** (Lines 101-150)
   - Use standard stdenv.mkDerivation
   - Set version, src, buildInputs
   - Include simple post-install test

4. **Validate Stage 1**:
   ```bash
   # Test flake structure
   nix flake show
   
   # Dry run
   nix build .#gcc14 --dry-run
   
   # Actual build
   nix build .#gcc14
   
   # Verify output
   ./result/bin/gcc --version   # Should show 14.2.1
   ```

**Success Criteria**:
- Flake evaluates without errors
- GCC builds successfully
- Version verification passes
- No warnings in build log

**On Failure**:
- Read build log: `nix log .#gcc14`
- Check common issues:
  - Wrong hash → Use `nix-prefetch-url`
  - Missing dependency → Add to buildInputs
  - Syntax error → Use `nix flake check`

#### Stage 2: ROCm Foundation (2 hour build)

**Implementation Steps**:

1. **Create NVIDIA isolation Layer 1** (Lines 151-200)
   ```nix
   # Poisoned package overlay
   overlays = [
     (final: prev: {
       cudatoolkit = throw "NVIDIA contamination: cudatoolkit blocked";
       cudaPackages = throw "NVIDIA contamination: cudaPackages blocked";
       # ... more poison pills
     })
   ];
   ```

2. **Create dependency-auditor utility** (Lines 201-250)
   - Shell script that parses `nix show-derivation`
   - Searches for cuda/nvidia patterns
   - Fails build if found

3. **Create ROCm 7.2.0 derivation** (Lines 251-350)
   - Use GCC 14.2.1 from Stage 1
   - Set AMDGPU_TARGETS=gfx1151
   - Include gfx1151-specific flags
   - Add dependency auditor as preBuild hook

4. **Validate Stage 2**:
   ```bash
   # Pre-flight dependency check
   nix show-derivation .#rocm | grep -i cuda
   # Should output nothing
   
   # Build
   nix build .#rocm
   
   # Verify ROCm
   ./result/bin/rocminfo
   # Should show gfx1151 support
   
   # Check for NVIDIA symbols
   nm -D ./result/lib/*.so | grep -i nvidia
   # Should output nothing
   ```

**Success Criteria**:
- ROCm builds without NVIDIA dependencies
- rocminfo shows correct version
- No cuda/nvidia symbols in binaries
- Dependency auditor passes

#### Stage 3: Python + PyTorch (4+ hour build)

**CRITICAL: Memory Management Required**

**Implementation Steps**:

1. **Create build-orchestrator** (Lines 351-450)
   - Python script monitoring memory pressure
   - Reads /sys/fs/cgroup/memory.pressure
   - Implements exponential backoff
   - Schedules jobs to prevent OOM

2. **Create Python 3.11 environment** (Lines 451-500)
   - Isolated from host Python
   - PYTHONNOUSERSITE=1
   - Custom package overrides (no torch from PyPI)

3. **Create PyTorch 2.10.0 derivation** (Lines 501-650)
   - USE_CUDA=0, USE_ROCM=1
   - Depends on ROCm from Stage 2
   - Uses build orchestrator for scheduling
   - Includes memory-aware build flags

4. **Validate Stage 3**:
   ```bash
   # Monitor memory during build
   watch -n 1 free -h    # In separate terminal
   
   # Build with orchestrator
   nix build .#pytorch
   
   # Test PyTorch
   nix shell .#pytorch -c python << EOF
   import torch
   print(f"ROCm: {torch.version.hip}")
   print(f"CUDA available: {torch.cuda.is_available()}")
   # Should print: ROCm: 7.2.0, CUDA available: False
   EOF
   ```

**Success Criteria**:
- No OOM kills during build
- PyTorch imports successfully
- ROCm backend detected
- CUDA explicitly not available

**On Memory Issues**:
- Reduce max-jobs in nix.conf
- Increase backoff threshold in orchestrator
- Consider building with cores=1 (slower but safer)

#### Stage 4: AI Stack Integration (2 hour build)

**Implementation Steps**:

1. **Create vLLM 0.14.0 derivation** (Lines 651-750)
   - Depends on PyTorch from Stage 3
   - ROCm backend configuration
   - Batch size optimizations for unified memory

2. **Create llama.cpp derivations** (Lines 751-900)
   - Three variants: server, cli, quantize
   - ROCm/HIP backend (not CLBlast)
   - Static link ROCm libraries
   - gfx1151 optimizations

3. **Create model management utilities** (Lines 901-950)
   - GGUF model loader
   - Quantization wrapper scripts
   - Model cache management

4. **Validate Stage 4**:
   ```bash
   # Build all AI components
   nix build .#vllm
   nix build .#llama-server
   nix build .#llama-cli
   
   # Test vLLM
   nix shell .#vllm -c python -c "import vllm; print(vllm.__version__)"
   
   # Test llama.cpp
   ./result/bin/llama-cli --version
   ./result/bin/llama-server --version
   
   # Verify ROCm backend
   strings ./result/bin/llama-server | grep -i rocm
   # Should show ROCm library references
   ```

**Success Criteria**:
- All components build successfully
- vLLM and llama.cpp use ROCm backend
- No CUDA contamination in any binary
- Model management tools functional

#### Stage 5: Safety Systems (1 hour)

**Implementation Steps**:

1. **Enhance binary-scanner** (Lines 951-1000)
   - Comprehensive pattern matching
   - Detailed contamination reporting
   - Integration with all derivations

2. **Create SBOM generator** (Lines 1001-1100)
   - Embedded NVD snapshot
   - SPDX 2.3 and CycloneDX 1.5 output
   - CVE cross-reference

3. **Create reproducibility-test** (Lines 1101-1150)
   - Build 3 times, compare hashes
   - Automated validation
   - Report generation

4. **Integrate all 4 NVIDIA isolation layers** (Lines 1151-1250)
   - Layer 1: Poisoned packages (already done)
   - Layer 2: Dependency auditor (already done)
   - Layer 3: Sandbox path blacklisting
   - Layer 4: Binary scanner (enhanced)

5. **Validate Stage 5**:
   ```bash
   # Run reproducibility test
   nix run .#reproducibility-test
   
   # Generate SBOM
   nix run .#sbom-generator
   cat result/SBOM.spdx.json
   
   # Test NVIDIA isolation
   nix run .#test-nvidia-isolation
   # Should report: All 4 layers active, no contamination
   ```

**Success Criteria**:
- Reproducibility test passes (3 identical builds)
- SBOM generates successfully
- CVE report shows < 10 critical issues
- All 4 isolation layers verified

#### Stage 6: DevShell + Deployment (1 hour)

**Implementation Steps**:

1. **Create comprehensive devShell** (Lines 1251-1400)
   - All development tools
   - Convenient aliases (build-gcc, test-isolation, etc.)
   - Pre-configured environment variables
   - Shell hooks for setup

2. **Create offline-bundle-creator** (Lines 1401-1550)
   - Export full closure to NARs
   - Generate installer script
   - Include systemd services
   - Bundle documentation

3. **Create VS Code tasks configuration** (Lines 1551-1650)
   - Task for each build stage
   - Validation tasks
   - Testing tasks
   - Deployment tasks

4. **Create integration tests** (Lines 1651-1750)
   - Full system smoke test
   - Performance benchmarks
   - Deployment validation

5. **Validate Stage 6**:
   ```bash
   # Enter devShell
   nix develop
   
   # Test aliases
   build-all
   test-integration
   validate-pre
   
   # Create bundle
   package-bundle
   
   # Verify bundle
   ls -lh rockbuilder-bundle-v6.0.tar.zst
   # Should be ~20-30GB compressed
   ```

**Success Criteria**:
- DevShell enters without errors
- All aliases functional
- Bundle creation completes
- Integration tests pass

---

## Safety Protocols

### Protocol 1: Never Ignore Warnings

**Rule**: Every warning must be investigated.

**Process**:
1. Warning appears → STOP building
2. Read warning message carefully
3. Determine root cause
4. Fix or document as known issue
5. THEN continue

**Example Warnings to NEVER Ignore**:
- "warning: unknown attribute 'xxx'" → Typo in attribute name
- "warning: deprecated syntax" → Update to modern Nix
- "warning: hash mismatch" → Source changed, security risk

### Protocol 2: Validate Before Integration

**Rule**: Never add code to the flake without testing it in isolation first.

**Process**:
1. Write new derivation
2. Test with `nix build .#new-component`
3. Verify outputs manually
4. Add to larger integration
5. Re-test everything

**Example**:
```nix
# BAD: Add new component directly to large buildEnv
buildEnv {
  paths = [ gcc rocm pytorch vllm new-untested-component ];
}

# GOOD: Test new component first
# Step 1: nix build .#new-component
# Step 2: Verify result/
# Step 3: THEN add to buildEnv
```

### Protocol 3: Memory Awareness

**Rule**: Always consider memory constraints during builds.

**Before Building Large Components** (PyTorch, ROCm):
```bash
# Check available memory
free -h
# Minimum 50GB free recommended for PyTorch

# Check current Nix builds
ps aux | grep nix-build
# If multiple builds running, wait for completion

# Monitor during build
watch -n 5 'free -h && echo "---" && cat /sys/fs/cgroup/memory.pressure'
```

**If Memory Pressure Detected**:
1. Pause new builds
2. Let current job complete
3. Run garbage collection: `nix-collect-garbage -d`
4. Resume with reduced parallelism

### Protocol 4: Store Path Hygiene

**Rule**: Never hardcode /nix/store paths.

**BAD**:
```nix
postInstall = ''
  cp /nix/store/abc123-rocm-7.2.0/lib/librocm.so $out/lib/
'';
```

**GOOD**:
```nix
postInstall = ''
  cp ${rocm}/lib/librocm.so $out/lib/
'';
```

### Protocol 5: Hash Verification

**Rule**: All fetchurl must have correct hashes.

**Process**:
1. If hash unknown: Use `lib.fakeSha256` temporarily
2. Build will fail with actual hash
3. Copy actual hash into derivation
4. Rebuild to verify

**Example**:
```nix
src = fetchurl {
  url = "https://example.com/source.tar.gz";
  sha256 = lib.fakeSha256;  # Temporary, will fail
};

# After failure, Nix shows:
# "got: sha256-abc123..."
# Copy that hash and replace fakeSha256
```

---

## Error Recovery Procedures

### Scenario 1: Build Fails Due to Missing Dependency

**Symptoms**:
- Error: "command not found: cmake"
- Error: "xxx.h: No such file or directory"

**Solution**:
1. Identify missing package
2. Add to `nativeBuildInputs` (build-time) or `buildInputs` (runtime)
3. Rebuild

**Example**:
```nix
# Before:
buildInputs = [ gcc ];

# After (adding cmake):
nativeBuildInputs = [ cmake ];  # Build-time tool
buildInputs = [ gcc ];           # Runtime dependency
```

### Scenario 2: NVIDIA Contamination Detected

**Symptoms**:
- Binary scanner reports cuda/nvidia symbols
- Dependency auditor finds NVIDIA package in graph

**Solution**:
1. Identify which component introduced contamination
2. Check if component has ROCm alternative (e.g., nccl → rccl)
3. Add override to force ROCm version
4. If no alternative exists, find different package

**Example**:
```nix
# Package wants to use CUDA version
somePackage = prev.somePackage.override {
  cudaSupport = false;
  rocmSupport = true;
  rocmPackages = final.rocmPackages;
};
```

### Scenario 3: Out of Memory During Build

**Symptoms**:
- Build killed with no error message
- dmesg shows "OOM killer"
- System becomes unresponsive

**Solution**:
1. Stop all builds: `killall nix-build`
2. Run garbage collection: `nix-collect-garbage -d`
3. Reduce parallelism in nix.conf:
   ```
   max-jobs = 8    # Was 24
   cores = 1       # Was 2
   ```
4. Rebuild problematic component alone
5. After success, restore parallelism for other components

### Scenario 4: Reproducibility Test Fails

**Symptoms**:
- Three builds produce different hashes
- Binary differs across builds

**Causes**:
- Timestamp embedded in binary
- Build process uses random values
- Path includes build-specific data

**Solution**:
1. Use `diffoscope` to compare binaries:
   ```bash
   nix-shell -p diffoscope
   diffoscope result-1/ result-2/
   ```
2. Identify non-deterministic source
3. Common fixes:
   - Strip timestamps: Add `ZERO_AR_DATE=1`
   - Fix random seeds: Set `PYTHONHASHSEED=0`
   - Normalize paths: Use `--prefix-map` in compiler flags

### Scenario 5: Flake Evaluation Error

**Symptoms**:
- `nix flake show` fails
- Error: "undefined variable 'xxx'"
- Error: "infinite recursion encountered"

**Solution for Undefined Variable**:
1. Check spelling of variable name
2. Verify variable is in scope (inside same `let` block)
3. If referencing from same block, add `rec`:
   ```nix
   # Before:
   let
     a = 1;
     b = a + 1;  # Error: undefined variable 'a'
   in ...
   
   # After:
   let
     a = 1;
   in rec {
     b = a + 1;  # Now works
   }
   ```

**Solution for Infinite Recursion**:
1. Check overlay chain for circular references
2. Use `nix-instantiate --eval --show-trace` to see stack
3. Break cycle by removing problematic reference

---

## Code Quality Standards

### Naming Conventions

**Derivations**: `kebab-case`
```nix
rocm-7-2-0          # Good
rocm_7_2_0          # Bad
RocM-7.2.0          # Bad
```

**Functions**: `camelCase`
```nix
buildWithRocm = ...   # Good
build_with_rocm = ... # Bad
```

**Variables in `let` blocks**: `camelCase`
```nix
let
  gccVersion = "14.2.1";     # Good
  gcc_version = "14.2.1";    # Bad
in ...
```

### Formatting Standards

**Use alejandra formatter**:
```bash
nix-shell -p alejandra
alejandra flake.nix
```

**Manual standards**:
- Indent: 2 spaces (no tabs)
- Line length: 100 characters max
- Lists: One item per line
- Strings: Double quotes unless containing ${interpolation}

**Example**:
```nix
buildInputs = [
  gcc
  cmake
  pkg-config
  rocm
]; # Trailing semicolon on same indentation level
```

### Documentation Standards

**Every derivation must have**:
```nix
someComponent = stdenv.mkDerivation {
  pname = "some-component";
  version = "1.2.3";
  
  # What: Brief description of component
  # Why: Why this version, why these flags
  # Gotchas: Known issues or special requirements
  
  meta = {
    description = "Human-readable description";
    homepage = "https://...";
    license = lib.licenses.mit;
  };
};
```

**Complex build phases must have**:
```nix
buildPhase = ''
  # Step 1: Configure with gfx1151 optimizations
  cmake -DAMDGPU_TARGETS=gfx1151 .
  
  # Step 2: Build with parallel make
  # Note: Limited to 8 jobs due to memory constraints
  make -j8
  
  # Step 3: Run smoke test
  ./bin/tool --version
'';
```

---

## Testing Requirements

### Per-Component Tests

**Every derivation must include**:
```nix
postInstall = ''
  # Test 1: Binary exists
  test -f $out/bin/program
  
  # Test 2: Version check
  $out/bin/program --version | grep -q "${version}"
  
  # Test 3: Library links correctly (if applicable)
  ldd $out/bin/program | grep -q "librocm"
'';
```

### Integration Tests

**Create `tests/` directory in flake with**:
1. `test-nvidia-isolation.nix`: Verify all 4 layers
2. `test-reproducibility.nix`: Build 3 times, compare
3. `test-memory-orchestration.nix`: Simulate low memory
4. `test-binary-symbols.nix`: Scan for forbidden patterns
5. `test-deployment.nix`: Bundle creation and installation

**Run all tests**:
```bash
nix flake check    # Runs all tests in tests/
```

---

## Success Metrics

### Stage Completion Checklist

**Stage 1**:
- [ ] Flake evaluates without errors
- [ ] GCC 14.2.1 builds and passes version check
- [ ] No warnings in build output
- [ ] devShell enters successfully

**Stage 2**:
- [ ] ROCm 7.2.0 builds successfully
- [ ] No NVIDIA packages in dependency graph
- [ ] rocminfo shows gfx1151 support
- [ ] All binaries pass symbol scan

**Stage 3**:
- [ ] Build orchestrator functional
- [ ] PyTorch builds without OOM kills
- [ ] PyTorch detects ROCm backend
- [ ] CUDA explicitly unavailable

**Stage 4**:
- [ ] vLLM builds and imports successfully
- [ ] llama.cpp all variants build
- [ ] Both use ROCm backend
- [ ] Model management tools functional

**Stage 5**:
- [ ] Reproducibility test passes (3/3 builds identical)
- [ ] SBOM generates successfully
- [ ] All 4 NVIDIA isolation layers verified
- [ ] CVE report generated

**Stage 6**:
- [ ] DevShell all aliases work
- [ ] Offline bundle creates successfully
- [ ] Integration tests pass
- [ ] Documentation complete

### Final Validation

**Before declaring success, verify**:
1. Total build time < 12 hours (first build, no cache)
2. All safety checks passing
3. No critical CVEs in SBOM
4. Bundle size < 35GB compressed
5. All documentation readable and accurate

---

## Communication Protocols

### When to Ask for Human Input

**ASK BEFORE**:
1. Making architectural changes to PRD design
2. Changing version numbers from Iron Rules
3. Disabling safety checks "temporarily"
4. Proceeding with >5 warnings in build output
5. Skipping validation steps

**INFORM AFTER**:
1. Each stage completion
2. Any test failures (with proposed fix)
3. Discovery of new gotchas
4. Performance anomalies (build taking 2x expected time)

### Progress Reporting Format

**After Each Stage**:
```
Stage N: [COMPONENT NAME] - COMPLETE
Build Time: X hours Y minutes
Warnings: N (list if >0)
Tests Passed: X/Y
Next Stage: [STAGE N+1 NAME]
Estimated Time: Z hours

Issues Found:
- [Issue 1]: [Solution applied]
- [Issue 2]: [Solution applied]

Ready to proceed to Stage N+1? (y/n)
```

---

## Emergency Procedures

### Critical Failure (System Unresponsive)

1. **Immediate Actions**:
   - Kill all nix builds: `killall -9 nix-build`
   - Clear temp: `rm -rf /tmp/nix-build-*`
   - Run GC: `nix-collect-garbage -d`

2. **Recovery**:
   - Reboot if necessary
   - Check disk space: `df -h`
   - Verify Nix daemon: `systemctl status nix-daemon`
   - Test minimal build: `nix-shell -p hello`

3. **Resume**:
   - Start from last successful stage
   - Reduce parallelism before retrying
   - Monitor resources closely

### Data Loss Prevention

**Before Each Stage**:
```bash
# Commit progress
git add flake.nix flake.lock
git commit -m "Stage N: [component] complete"
git tag stage-N-success
```

**Backup Store Paths**:
```bash
# After successful stage
nix-store -qR result > stage-N-paths.txt
# Can restore these later if needed
```

---

## Final Notes

**Remember**:
1. This is a marathon, not a sprint (8-12 hours total build time)
2. Validation is not optional, it's essential
3. When in doubt, test in isolation first
4. Memory is the primary constraint, respect it
5. NVIDIA contamination is the primary risk, defend against it

**Success looks like**:
- All 6 stages completed sequentially
- No skipped validations
- Full test suite passing
- Clean, documented code
- Deployable offline bundle

**The agent's goal is not just working code, but production-ready, maintainable, safe infrastructure.**

---

**END OF SKILL AGENT SPECIFICATION**