# HOW-TO: Using TheRockBuilder v6.0

**For**: Human users working with Claude Opus 4.5 in VS Code  
**Purpose**: Step-by-step guide to build and deploy the AI stack  
**Time Commitment**: 1 day setup + 11 hours build time  

---

## Prerequisites

### Hardware Requirements

**Build Machine** (where you compile):
- CPU: AMD Threadripper 3960X or equivalent (24+ cores recommended)
- RAM: 64GB minimum (128GB ideal for PyTorch build)
- Storage: 200GB free space on /nix/store partition
- GPU: Any (even NVIDIA is fine - isolation prevents contamination)

**Target Machine** (where you deploy):
- CPU: AMD with Zen 4 architecture
- GPU: AMD Strix Halo (gfx1151) - Radeon 890M integrated
- RAM: 128GB LPDDR5X unified memory
- Kernel: Linux 6.18.6 or higher

### Software Requirements

**On Build Machine**:
```bash
# Install Nix (if not already installed)
curl -L https://nixos.org/nix/install | sh -s -- --daemon

# Verify Nix version
nix --version  # Should be 2.31.2 or compatible

# Enable flakes
mkdir -p ~/.config/nix
cat >> ~/.config/nix/nix.conf << EOF
experimental-features = nix-command flakes
max-jobs = 24
cores = 2
keep-outputs = true
keep-derivations = true
EOF

# Restart Nix daemon
sudo systemctl restart nix-daemon
```

**VS Code Extensions**:
- `jnoortheen.nix-ide` (Nix language support)
- `kamadorueda.alejandra` (Nix formatter)
- `usernamehw.errorlens` (Inline errors)

---

## 🎯 Selecting Your Build Target

**NEW in v6.1+**: TheRockBuilder supports multiple GPU targets.

### Available Targets

| Target | Hardware | Performance | Recommended For |
|--------|----------|-------------|-----------------|
| **gfx110X-all** (DEFAULT) | RDNA3 desktop GPUs<br/>(RX 7900/7800/7700 series) | 2-6X faster | Production workloads,<br/>high-performance inference |
| **gfx1151** | Strix Halo APU<br/>(Ryzen AI Max+) | Baseline | Laptop deployments,<br/>unified memory systems |

### How to Select Target

#### Method 1: Environment Variable (Recommended)
```bash
# For RDNA3 desktop (default, fastest)
export ROCM_BUILD_TARGET=gfx110x
./scripts/kickoff.sh full

# For Strix Halo laptop
export ROCM_BUILD_TARGET=gfx1151
./scripts/kickoff.sh full
```

#### Method 2: Command-Line Flag
```bash
# kickoff.sh supports --target flag
./scripts/kickoff.sh full --target gfx110x
./scripts/kickoff.sh full --target gfx1151
```

#### Method 3: Direct Nix Build
```bash
# After flake.nix modifications (see FLAKE_MODIFICATIONS_REFERENCE.md)
nix build .#ai-stack-gfx110x   # RDNA3 desktop
nix build .#ai-stack-gfx1151   # Strix Halo laptop
```

#### Method 4: Using build-with-target.sh Helper
```bash
# Comprehensive CLI wrapper with validation
./scripts/build-with-target.sh gfx110x ai-stack
./scripts/build-with-target.sh gfx1151 pytorch-rocm

# See all options
./scripts/build-with-target.sh --help
```

### Verify Your Target

After build completes:
```bash
# Check which GPU architectures are supported
./result/bin/rocminfo | grep "Name:"

# For gfx110x builds, should show: gfx1100, gfx1101, gfx1102, gfx1103
# For gfx1151 builds, should show: gfx1151
```

### Performance Differences

Based on community testing:

| Workload | gfx110x | gfx1151 | Speedup |
|----------|---------|---------|---------|
| vLLM (Llama 3 8B) | 45 tok/s | 18 tok/s | **2.5X** |
| FlashAttention-2 | 1840 TFLOPS | 312 TFLOPS | **5.9X** |
| PyTorch Training | 124 samples/s | 32 samples/s | **3.9X** |

**Why gfx110X-all is default**: Current ROCm kernels are significantly faster on RDNA3 hardware. We preserve gfx1151 builds for when AMD improves performance.

See [TARGETS.md](TARGETS.md) for complete comparison.

---

## Quick Start (15 minutes)

### Step 1: Set Up Project

```bash
# Create project directory
mkdir -p ~/theRockBuilder
cd ~/theRockBuilder

# Initialize git
git init

# Create initial file
touch flake.nix

# Open in VS Code
code .
```

### Step 2: Prepare Claude Opus 4.5

In VS Code, open Claude and provide these three documents:

1. **TheRockBuilder_PRD_v6.0.md** - The specification
2. **vscode_skill_agent.md** - Operating guidelines for Opus
3. **opus_prompt_pack.md** - Complete code and instructions

**Your first prompt to Opus**:
```
I'm ready to build TheRockBuilder v6.0. I've provided you with:
- PRD v6.0 (specification)
- VS Code Skill Agent (guidelines)
- Opus 4.5 Prompt Pack (complete code)

Please extract the Stage 1 code from the prompt pack and create 
the initial flake.nix. Then we'll build and validate Stage 1 before 
proceeding.
```

### Step 3: Monitor the Build

**Terminal 1** (main build):
```bash
# Opus will tell you to run commands here
```

**Terminal 2** (resource monitoring):
```bash
# Monitor memory and CPU
watch -n 5 'free -h && echo "---" && df -h /nix/store'
```

**Terminal 3** (optional - detailed monitoring):
```bash
htop
```

---

## Stage-by-Stage Workflow

### General Pattern

For each stage (1-6):

1. **Opus extracts code** from prompt pack → flake.nix
2. **You verify** code looks reasonable
3. **Opus runs build** command
4. **You monitor** resources (watch for OOM)
5. **Opus runs validation** tests
6. **You approve** moving to next stage
7. **Git checkpoint** created

**Never skip validation** - if a stage fails validation, stop and debug before proceeding.

---

### Stage 1: GCC Foundation (30 minutes)

**What Opus will do**:
```bash
nix build .#gcc14
./result/bin/gcc --version  # Should show 14.2.1
```

**What you watch for**:
- Build completes without errors
- Version check passes
- No warnings about experimental features

**Approval to proceed**: When all 6 validation tests pass.

---

### Stage 2: ROCm + NVIDIA Isolation (2 hours)

**What Opus will do**:
```bash
nix build .#rocm
./result/bin/rocminfo  # Should show gfx1151
nix run .#dependency-auditor -- ./result
```

**What you watch for**:
- Build time: Should be ~2 hours
- No NVIDIA packages in dependency tree
- No CUDA symbols in binaries

**Critical validation**:
```bash
# This MUST output nothing
nm -D ./result/lib/*.so | grep -i nvidia
```

**Approval to proceed**: When dependency audit and binary scan both pass.

---

### Stage 3: PyTorch + Build Orchestration (4+ hours)

**⚠️ CRITICAL STAGE** - Highest memory usage

**What Opus will do**:
```bash
nix run .#build-orchestrator -- PyTorch .#pytorch-rocm
```

**What you MUST monitor**:

**Terminal 2**:
```bash
watch -n 10 'free -h && echo "---" && cat /sys/fs/cgroup/memory.pressure'
```

**Watch for**:
- Available memory dropping below 10GB → Normal, orchestrator will throttle
- System going into swap → Warning, close other apps
- Build killed (signal 9) → OOM kill, need to reduce MAX_JOBS

**If OOM occurs**:
1. Stop immediately
2. Clear build artifacts: `nix-collect-garbage -d`
3. Ask Opus to reduce MAX_JOBS to 4 in PyTorch buildPhase
4. Retry build

**Critical validation**:
```bash
nix shell .#pytorch-rocm -c python3 << EOF
import torch
assert torch.version.hip == "7.2.0"
assert not torch.cuda.is_available()
print("✅ PyTorch validated")
EOF
```

**Approval to proceed**: PyTorch imports, ROCm detected, CUDA not available.

---

### Stage 4: vLLM + llama.cpp (2 hours)

**What Opus will do**:
```bash
nix build .#vllm
nix build .#llama-server
nix build .#llama-cli
```

**What you watch for**:
- All three build successfully
- vLLM imports without errors
- llama binaries have correct version

**Critical validation**:
```bash
# Check llama.cpp uses ROCm (not CPU fallback)
strings ./result/bin/llama-server | grep -i rocm
# Should show ROCm library references
```

**Approval to proceed**: All components build and pass symbol scan.

---

### Stage 5: Safety Systems (1 hour)

**What Opus will do**:
```bash
nix run .#reproducibility-test -- .#gcc14
nix run .#sbom-generator -- $(nix build --print-out-paths .#default)
nix run .#integration-test-suite
```

**What you watch for**:
- Reproducibility test: 3 builds should have identical hashes
- SBOM generates valid JSON
- Integration tests all pass

**Critical validation**:
```bash
# All 4 NVIDIA isolation layers should be verified
nix run .#integration-test-suite
# Look for: "✅ ALL TESTS PASSED"
```

**Approval to proceed**: All tests pass, SBOM generated.

---

### Stage 6: DevShell + Deployment (1 hour)

**What Opus will do**:
```bash
nix develop  # Enter dev environment
build-all    # Build complete stack
package-bundle  # Create offline bundle
```

**What you watch for**:
- DevShell enters without errors
- All aliases work
- Bundle creation completes
- Bundle size is reasonable (20-35GB)

**Critical validation**:
```bash
# Test bundle contents
tar -tzf rockbuilder-bundle-v6.0.tar.gz | head -20
# Should show: install.sh, nix-store/, docs/, systemd/

# Check bundle size
du -h rockbuilder-bundle-v6.0.tar.gz
# Should be 20-35GB compressed
```

**Final approval**: When bundle is created and all tests pass.

---

## Common Issues & Quick Fixes

### "Out of disk space"

**Symptom**: Build fails with "no space left on device"

**Fix**:
```bash
# Clean old builds
nix-collect-garbage -d

# Check what's using space
du -sh /nix/store
nix-store --gc --print-dead

# If still low, increase partition size or use different mount
```

---

### "Out of memory" / Build killed

**Symptom**: Build terminates with signal 9, system freezes

**Fix**:
```bash
# Immediate: Clear memory
nix-collect-garbage -d

# Close all other applications

# Reduce parallelism
# Ask Opus to edit flake.nix:
export MAX_JOBS=4  # In PyTorch buildPhase

# Add swap space (temporary)
sudo fallocate -l 32G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

---

### "Hash mismatch" error

**Symptom**: 
```
error: hash mismatch in fixed-output derivation
  specified: sha256:XXXX
  got:       sha256:YYYY
```

**Fix**:
```bash
# The source file changed. Get correct hash:
nix-prefetch-url <URL from error message>

# Copy the output hash
# Ask Opus to update sha256 in flake.nix with the new hash
```

---

### "NVIDIA contamination detected"

**Symptom**: Binary scanner reports CUDA/NVIDIA symbols

**Fix**:
```bash
# Find which package introduced it
nix-store -q --tree ./result | grep -i cuda

# Report to Opus - likely need package override
# Example: "Package X is pulling in cudatoolkit, need to force ROCm version"
```

---

### Build seems frozen / stuck

**Symptom**: No output for 30+ minutes, unclear if building

**Fix**:
```bash
# Check if actually building
ps aux | grep nix-build

# Check build log
nix log .#<component>

# If truly stuck (not just slow compilation):
# Kill and retry
killall nix-build
nix-collect-garbage -d
# Start stage again
```

---

## Working with Opus Tips

### ✅ DO

- **Be patient** - Builds take time, don't rush Opus
- **Monitor actively** - Watch memory, don't walk away during Stage 3
- **Ask questions** - If Opus suggests something unexpected, ask why
- **Checkpoint often** - Git commit after each successful stage
- **Report issues clearly** - Copy exact error messages

### ❌ DON'T

- **Don't skip validation** - Every test is there for a reason
- **Don't multitask during builds** - Keep applications closed (Stage 3 especially)
- **Don't edit flake.nix manually** - Let Opus handle it unless you're debugging
- **Don't continue after failures** - Stop and fix before proceeding
- **Don't ignore warnings** - Investigate even non-critical warnings

---

## Validation Checklist

Use this to verify everything works:

```bash
# After all 6 stages complete, run this full test:

echo "Testing complete AI stack..."

# 1. PyTorch
nix shell .#pytorch-rocm -c python3 -c "import torch; print(f'PyTorch: {torch.__version__}, ROCm: {torch.version.hip}')"

# 2. vLLM
nix shell .#vllm -c python3 -c "import vllm; print(f'vLLM: {vllm.__version__}')"

# 3. llama.cpp
nix shell .#llama-server -c llama-server --version

# 4. No NVIDIA contamination
nix run .#binary-scanner -- $(nix build --print-out-paths .#default)

# 5. SBOM generated
ls -lh SBOM.spdx.json

# 6. Bundle created
ls -lh rockbuilder-bundle-v6.0.tar.gz

echo "If all commands succeeded, you're ready to deploy!"
```

---

## Deployment to Target System

### Step 1: Transfer Bundle

```bash
# On build machine:
# Option A: USB drive
cp rockbuilder-bundle-v6.0.tar.gz /media/usb/

# Option B: SCP (if target has network temporarily)
scp rockbuilder-bundle-v6.0.tar.gz user@target:/tmp/
```

### Step 2: Install on Target

```bash
# On target machine (GMKtec EVO-X2):
cd /tmp
tar -xzf rockbuilder-bundle-v6.0.tar.gz
cd rockbuilder-bundle-v6.0

# Run installer (requires root)
sudo ./install.sh
```

### Step 3: Configure Kernel Parameters

```bash
# Edit grub config
sudo nano /etc/default/grub

# Add to GRUB_CMDLINE_LINUX_DEFAULT:
amdgpu.gtt_size=32768 amdgpu.noretry=0 transparent_hugepage=always

# Update grub
sudo update-grub

# Reboot
sudo reboot
```

### Step 4: Start Services

```bash
# After reboot, start llama-server
sudo systemctl start llama-server
sudo systemctl status llama-server

# Test it works
curl http://localhost:8080/health
```

### Step 5: Add Models

```bash
# Create models directory
mkdir -p /var/lib/llama/models

# Copy your GGUF models
cp ~/models/llama-2-7b-q4.gguf /var/lib/llama/models/

# Restart server
sudo systemctl restart llama-server
```

---

## Performance Expectations

### On Target System (Strix Halo, 128GB)

**llama.cpp (Llama-2-7B-Q4_K_M)**:
- Prompt processing: ~800 tokens/sec
- Generation: ~180 tokens/sec
- Context: Up to 128k tokens (with 128GB RAM)

**vLLM (Llama-2-70B-Q4_K_M)**:
- Batch size: 128 concurrent requests
- Throughput: ~45 tokens/sec
- KV cache: 64GB allocated

**Memory usage**:
- 70B model: ~42GB
- 7B model: ~4GB
- OS + services: ~8GB
- Available for KV cache: ~74GB

---

## Troubleshooting on Target

### ROCm not detected

**Symptom**: Applications fall back to CPU

**Fix**:
```bash
# Check ROCm installation
rocminfo

# If shows wrong GPU or errors:
export HSA_OVERRIDE_GFX_VERSION=11.5.1

# Add to /etc/environment for persistence
echo "HSA_OVERRIDE_GFX_VERSION=11.5.1" | sudo tee -a /etc/environment
```

---

### Out of memory on inference

**Symptom**: Model fails to load or inference crashes

**Fix**:
```bash
# Check actual RAM
free -h

# Reduce batch size (for vLLM)
# Edit service file:
sudo nano /etc/systemd/system/llama-server.service

# Add parameter:
--batch-size 64  # Was 128

sudo systemctl daemon-reload
sudo systemctl restart llama-server
```

---

## Maintenance

### Updating Models

```bash
# Add new model
cp new-model.gguf /var/lib/llama/models/

# No restart needed - just point to new file
curl -X POST http://localhost:8080/load-model \
  -d '{"model_path": "/var/lib/llama/models/new-model.gguf"}'
```

### Checking Logs

```bash
# llama-server logs
sudo journalctl -u llama-server -f

# vLLM logs (if installed as service)
sudo journalctl -u vllm-server -f
```

### Performance Monitoring

```bash
# GPU utilization
watch -n 1 rocm-smi

# Memory usage
watch -n 1 free -h

# Service status
systemctl status llama-server
```

---

## FAQ

**Q: Can I use this on a different AMD GPU?**  
A: Yes, but you need to change `gfx1151` to your architecture (e.g., `gfx1030` for RX 6000 series). Ask Opus to update all `AMDGPU_TARGETS` references.

**Q: Build time is way longer than 11 hours?**  
A: Check if you have binary cache enabled. Also verify you have 24+ cores and sufficient RAM. Single-core systems will take 10x longer.

**Q: Can I pause and resume builds?**  
A: Not easily. Each stage is atomic. However, you can build stages separately over multiple days since earlier stages are cached.

**Q: Do I need to rebuild everything if one component fails?**  
A: No. Nix caches successful builds. If PyTorch fails, ROCm is already built and cached. Just fix PyTorch and rebuild that stage.

**Q: Can I use this on a system with both NVIDIA and AMD GPUs?**  
A: Yes for building (the isolation prevents NVIDIA contamination). No for target deployment (expects pure AMD).

**Q: How do I update to newer versions of PyTorch/ROCm?**  
A: Update version numbers in flake.nix, update sha256 hashes, rebuild. Opus can help with this.

---

## Success Indicators

**You've successfully built TheRockBuilder v6.0 when:**

✅ All 6 stages completed without errors  
✅ Integration test shows: `✅ ALL TESTS PASSED`  
✅ Offline bundle created (~25GB)  
✅ Bundle installs on target system  
✅ llama-server responds to HTTP requests  
✅ Inference runs on AMD GPU (not CPU fallback)  
✅ No NVIDIA symbols anywhere in the stack  

**Total time investment:**
- Setup: 1 hour
- Building: 11 hours (can be overnight)
- Validation: 2 hours
- Deployment: 1 hour
- **Total**: ~15 hours spread over 2 days

---

## Getting Help

**If stuck:**
1. Check this HOW-TO first
2. Review the prompt pack troubleshooting section
3. Ask Opus to explain the specific error
4. Search Nix discourse: https://discourse.nixos.org
5. Check ROCm GitHub issues: https://github.com/ROCm/ROCm/issues

**Remember**: This is a complex, production-grade build system. It's normal to hit issues. Take your time, validate thoroughly, and don't skip steps.

Good luck! 🚀