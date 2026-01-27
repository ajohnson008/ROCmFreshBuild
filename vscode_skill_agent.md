# VS Code Skill Agent Guidelines

> **For**: AI assistants working in VS Code with TheRockBuilder v6.1+  
> **Purpose**: Operating guidelines and best practices  
> **Last Updated**: January 27, 2026

---

## 🎯 Core Operating Principles

### 1. Target Awareness

**ALWAYS consider GPU target when building:**

```bash
# Before any build command, ask user:
"Which GPU target?
  - gfx110x (RDNA3 desktop - faster, recommended)
  - gfx1151 (Strix Halo laptop - UMA optimized)"

# Use explicit targets in commands
nix build .#ai-stack-gfx110x   # RDNA3
nix build .#ai-stack-gfx1151   # Strix Halo
```

### 2. VS Code Task Integration

**Create target-specific tasks in `.vscode/tasks.json`:**

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Build: ROCm Core (gfx110x)",
      "type": "shell",
      "command": "nix build .#rocm-core-gfx110x",
      "group": "build",
      "presentation": {
        "reveal": "always",
        "panel": "dedicated"
      },
      "problemMatcher": []
    },
    {
      "label": "Build: ROCm Core (gfx1151)",
      "type": "shell",
      "command": "nix build .#rocm-core-gfx1151",
      "group": "build",
      "problemMatcher": []
    },
    {
      "label": "Build: PyTorch (gfx110x)",
      "type": "shell",
      "command": "./scripts/build-with-target.sh gfx110x pytorch-rocm",
      "group": "build",
      "problemMatcher": []
    },
    {
      "label": "Build: Complete AI Stack (gfx110x)",
      "type": "shell",
      "command": "./scripts/build-with-target.sh gfx110x ai-stack",
      "group": {
        "kind": "build",
        "isDefault": true
      },
      "problemMatcher": []
    },
    {
      "label": "Build: Complete AI Stack (gfx1151)",
      "type": "shell",
      "command": "./scripts/build-with-target.sh gfx1151 ai-stack",
      "group": "build",
      "problemMatcher": []
    },
    {
      "label": "Validate: All Targets",
      "type": "shell",
      "command": "./scripts/validate-targets.sh",
      "group": "test",
      "problemMatcher": []
    },
    {
      "label": "Validate: gfx110x Only",
      "type": "shell",
      "command": "./scripts/validate-targets.sh gfx110x",
      "group": "test",
      "problemMatcher": []
    },
    {
      "label": "Lint: All Scripts",
      "type": "shell",
      "command": "./scripts/lint.sh",
      "group": "test",
      "problemMatcher": []
    },
    {
      "label": "Flake: Check Syntax",
      "type": "shell",
      "command": "nix flake check",
      "group": "test",
      "problemMatcher": []
    }
  ]
}
```

### 3. Launch Configurations

**Create `.vscode/launch.json` for debugging:**

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Build gfx110x (Debug)",
      "type": "node-terminal",
      "request": "launch",
      "command": "./scripts/build-with-target.sh gfx110x rocm-core --verbose",
      "cwd": "${workspaceFolder}"
    },
    {
      "name": "Validate Targets",
      "type": "node-terminal",
      "request": "launch",
      "command": "./scripts/validate-targets.sh",
      "cwd": "${workspaceFolder}"
    }
  ]
}
```

---

## 📚 Reference Documents

**Primary References**:
- `AGENTS.md` - AI collaboration protocols
- `opus_prompt_pack.md` - Complete code reference
- `TARGETS.md` - GPU target comparison guide
- `FLAKE_MODIFICATIONS_REFERENCE.md` - Implementation steps

**User Guides**:
- `README.md` - Project overview
- `HOW-TO.md` - Step-by-step usage
- `PRD_v6.0.md` - Technical specification

---

## 🧪 Validation Workflow

### Before Making Changes

```bash
# 1. Check current state
nix flake check

# 2. Verify target configuration
nix eval .#lib.targets --apply 'builtins.attrNames'
# Expected: [ "gfx110x" "gfx1151" ]

# 3. Check existing builds
ls -la result*
```

### After Making Changes

```bash
# 1. Syntax check
nix flake check

# 2. Test build (dry-run)
./scripts/build-with-target.sh gfx110x rocm-core --dry-run

# 3. Full validation
./scripts/validate-targets.sh

# 4. Lint scripts
./scripts/lint.sh
```

---

## 🔍 Troubleshooting Guide

### Issue: "Target not found"

```bash
# Check if target exists in lib/targets.nix
nix eval --raw .#lib.targets.gfx110x.name
nix eval --raw .#lib.targets.gfx1151.name

# If missing, verify lib/targets.nix file exists
ls -la lib/targets.nix
```

### Issue: "Flake check fails"

```bash
# Get detailed error
nix flake check --show-trace

# Common causes:
# 1. Syntax error in flake.nix
# 2. Missing import for lib/targets.nix
# 3. Incorrect overlay application
```

### Issue: "Build for wrong target"

```bash
# Check environment variable
echo $ROCM_BUILD_TARGET

# Check GPU hardware
rocminfo | grep "Name:"

# Use explicit target
./scripts/build-with-target.sh gfx110x rocm-core
```

---

## 🎨 Best Practices

### 1. Always Use Helper Scripts

```bash
# PREFERRED: Use build-with-target.sh
./scripts/build-with-target.sh gfx110x pytorch-rocm

# Instead of: Direct nix build (unless you know the exact attribute)
# nix build .#pytorch-rocm-gfx110x
```

### 2. Validate Frequently

```bash
# After every significant change
nix flake check
./scripts/validate-targets.sh gfx110x
```

### 3. Document Target Selection

```bash
# In commit messages
git commit -m "feat: add flash-attention for gfx110x target"

# In code comments
# Build flash-attention for gfx110x (RDNA3 optimization)
nix build .#flash-attention-gfx110x
```

---

## 🚀 Quick Reference

| Task | Command |
|------|---------|
| List all targets | `./scripts/build-with-target.sh list` |
| Build for gfx110x | `./scripts/build-with-target.sh gfx110x <component>` |
| Build for gfx1151 | `./scripts/build-with-target.sh gfx1151 <component>` |
| Validate all | `./scripts/validate-targets.sh` |
| Check syntax | `nix flake check` |
| Lint scripts | `./scripts/lint.sh` |
| See help | `./scripts/build-with-target.sh --help` |

---

**Operating Guidelines**:
- Follow `AGENTS.md` protocols for multi-agent coordination
- Use `opus_prompt_pack.md` for code references
- Consult `TARGETS.md` for target-specific details
- Reference `FLAKE_MODIFICATIONS_REFERENCE.md` for flake.nix changes

**Status**: Production-ready v6.1+ guidelines
