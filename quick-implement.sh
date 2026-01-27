#!/usr/bin/env bash
# quick-implement.sh - Rapid implementation script for dual-target support
#
# This script automates the creation of gfx110X-all variant support.
# It performs the "simple approach" from FLAKE_CHANGES.md.
#
# Usage:
#   bash quick-implement.sh          # Full implementation
#   bash quick-implement.sh --check  # Dry-run only

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

DRY_RUN=false
if [ "${1:-}" = "--check" ]; then
    DRY_RUN=true
    echo "🔍 DRY RUN MODE - No changes will be made"
    echo ""
fi

# ============================================================================
# Helper Functions
# ============================================================================

log_step() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $*"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

log_info() {
    echo "ℹ️  $*"
}

log_success() {
    echo "✅ $*"
}

log_error() {
    echo "❌ $*"
}

log_warning() {
    echo "⚠️  $*"
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

log_step "Pre-flight Checks"

# Check if we're in the right directory
if [ ! -f "flake.nix" ]; then
    log_error "flake.nix not found. Are you in the repository root?"
    exit 1
fi
log_success "Repository structure validated"

# Check if lib/targets.nix exists
if [ ! -f "lib/targets.nix" ]; then
    log_error "lib/targets.nix not found. Run the main implementation first."
    exit 1
fi
log_success "lib/targets.nix found"

# Check for git
if ! command -v git &>/dev/null; then
    log_warning "git not found - skipping branch creation"
else
    # Check if we're on a feature branch
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
    if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
        log_warning "You're on $CURRENT_BRANCH branch. Consider creating a feature branch first:"
        echo "  git checkout -b feature/dual-target-gfx110x"
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    else
        log_info "Current branch: $CURRENT_BRANCH"
    fi
fi

echo ""
log_info "This script will:"
echo "  1. Backup flake.nix → flake.nix.backup"
echo "  2. Create rocm-overlay-gfx110x.nix (copy & modify)"
echo "  3. Create rocm-overlay-gfx1151.nix (preserve current)"
echo "  4. Update policy/rocm-policy.json"
echo "  5. Display manual steps for flake.nix"
echo ""

if [ "$DRY_RUN" = false ]; then
    read -p "Proceed with implementation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted by user"
        exit 0
    fi
fi

# ============================================================================
# Step 1: Backup Critical Files
# ============================================================================

log_step "Step 1: Backup Critical Files"

if [ "$DRY_RUN" = false ]; then
    if [ ! -f "flake.nix.backup" ]; then
        cp flake.nix flake.nix.backup
        log_success "Backed up flake.nix → flake.nix.backup"
    else
        log_info "Backup already exists: flake.nix.backup"
    fi
    
    if [ -f "rocm-overlay.nix" ] && [ ! -f "rocm-overlay.nix.backup" ]; then
        cp rocm-overlay.nix rocm-overlay.nix.backup
        log_success "Backed up rocm-overlay.nix → rocm-overlay.nix.backup"
    fi
else
    log_info "[DRY RUN] Would backup flake.nix and rocm-overlay.nix"
fi

# ============================================================================
# Step 2: Create rocm-overlay-gfx110x.nix
# ============================================================================

log_step "Step 2: Create rocm-overlay-gfx110x.nix"

if [ "$DRY_RUN" = false ]; then
    if [ ! -f "rocm-overlay.nix" ]; then
        log_error "rocm-overlay.nix not found!"
        exit 1
    fi
    
    log_info "Copying rocm-overlay.nix → rocm-overlay-gfx110x.nix"
    cp rocm-overlay.nix rocm-overlay-gfx110x.nix
    
    log_info "Modifying rocm-overlay-gfx110x.nix for RDNA3 targets"
    
    # Update header comment
    sed -i '1,5s/gfx1151/gfx110X-all/g' rocm-overlay-gfx110x.nix
    
    # Replace AMDGPU_TARGETS with gfx110X-all targets
    # This is a simplified replacement - review manually for accuracy
    sed -i 's/gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1103;gfx1151/gfx900;gfx906;gfx908;gfx90a;gfx1030;gfx1100;gfx1101;gfx1102;gfx1103/g' rocm-overlay-gfx110x.nix
    
    # Remove gfx1151-specific flags
    sed -i '/LLVM_AMDGPU_ALLOW_NAKED_POINTER/d' rocm-overlay-gfx110x.nix
    sed -i '/HSA_OVERRIDE_GFX_VERSION/d' rocm-overlay-gfx110x.nix
    
    # Note: vLLM patches (lines 310-320) need manual removal
    log_warning "Manual edit required: Remove vLLM gfx1103 fallback patches (lines ~310-320)"
    log_warning "Search for: 'Force gfx1103 kernel compatibility' and remove that block"
    
    log_success "Created rocm-overlay-gfx110x.nix (requires manual review)"
else
    log_info "[DRY RUN] Would create rocm-overlay-gfx110x.nix"
fi

# ============================================================================
# Step 3: Create rocm-overlay-gfx1151.nix
# ============================================================================

log_step "Step 3: Create rocm-overlay-gfx1151.nix"

if [ "$DRY_RUN" = false ]; then
    if [ ! -f "rocm-overlay-gfx1151.nix" ]; then
        log_info "Copying rocm-overlay.nix → rocm-overlay-gfx1151.nix (preserve original)"
        cp rocm-overlay.nix rocm-overlay-gfx1151.nix
        log_success "Created rocm-overlay-gfx1151.nix"
    else
        log_info "rocm-overlay-gfx1151.nix already exists"
    fi
else
    log_info "[DRY RUN] Would create rocm-overlay-gfx1151.nix"
fi

# ============================================================================
# Step 4: Update policy/rocm-policy.json
# ============================================================================

log_step "Step 4: Update policy/rocm-policy.json"

if [ "$DRY_RUN" = false ]; then
    if [ -f "policy/rocm-policy.json" ]; then
        log_info "Updating gpu_targets.pass_a.allowed in policy/rocm-policy.json"
        
        # Backup policy file
        cp policy/rocm-policy.json policy/rocm-policy.json.backup
        
        # Update allowed targets (simple string replacement)
        # This assumes the current format - may need manual adjustment
        sed -i 's/"allowed": \["gfx1151"\]/"allowed": ["gfx1151", "gfx1100", "gfx1101", "gfx1102", "gfx1103"]/' policy/rocm-policy.json
        
        log_success "Updated policy/rocm-policy.json"
    else
        log_warning "policy/rocm-policy.json not found - skipping"
    fi
else
    log_info "[DRY RUN] Would update policy/rocm-policy.json"
fi

# ============================================================================
# Step 5: Display Manual Steps
# ============================================================================

log_step "Step 5: Manual Steps Required"

echo ""
echo "The automated portion is complete. You must now manually edit flake.nix:"
echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo ""
echo "1. Open flake.nix in your editor"
echo ""
echo "2. Find the overlay import section (~line 50-60) and change:"
echo ""
echo "   FROM:"
echo "     overlays = ["
echo "       self.overlays.default"
echo "       ..."
echo "       (import ./rocm-overlay.nix)"
echo "     ];"
echo ""
echo "   TO:"
echo "     # Create package sets for each target"
echo "     mkPkgs = targetConfig: import nixpkgs {"
echo "       overlays = ["
echo "         self.overlays.default"
echo "         ..."
echo "         (import \"\${./rocm-overlay}-\${targetConfig.name}.nix\")"
echo "       ];"
echo "     };"
echo ""
echo "     pkgs-gfx110x = mkPkgs (import ./lib/targets.nix).gfx110x;"
echo "     pkgs-gfx1151 = mkPkgs (import ./lib/targets.nix).gfx1151;"
echo "     pkgs = pkgs-gfx110x;  # Default"
echo ""
echo "──────────────────────────────────────────────────────────────────────"
echo ""
echo "3. In the packages = { } section, duplicate key packages:"
echo ""
echo "   FROM:"
echo "     rocm-core = ...;"
echo "     pytorch-rocm = ...;"
echo "     ai-stack = buildEnv { ... };"
echo ""
echo "   TO:"
echo "     rocm-core-gfx110x = pkgs-gfx110x.rocm-core;"
echo "     rocm-core-gfx1151 = pkgs-gfx1151.rocm-core;"
echo ""
echo "     pytorch-rocm-gfx110x = pkgs-gfx110x.pytorch-rocm;"
echo "     pytorch-rocm-gfx1151 = pkgs-gfx1151.pytorch-rocm;"
echo ""
echo "     ai-stack-gfx110x = pkgs-gfx110x.buildEnv { ... };"
echo "     ai-stack-gfx1151 = pkgs-gfx1151.buildEnv { ... };"
echo ""
echo "     # Backward compat aliases"
echo "     rocm-core = self.packages.\${system}.rocm-core-gfx110x;"
echo "     ai-stack = self.packages.\${system}.ai-stack-gfx110x;"
echo "     default = self.packages.\${system}.ai-stack-gfx110x;"
echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo ""
echo "For detailed instructions, see:"
echo "  - FLAKE_CHANGES.md (step-by-step guide)"
echo "  - IMPLEMENTATION_SUMMARY.md (complete checklist)"
echo ""
echo "After manual edits, test with:"
echo "  nix flake check"
echo "  nix build .#rocm-core-gfx110x"
echo "  nix build .#rocm-core-gfx1151"
echo "  ./scripts/validate-targets.sh"
echo ""

# ============================================================================
# Summary
# ============================================================================

log_step "Summary"

echo ""
echo "Automated Steps Complete:"
if [ "$DRY_RUN" = false ]; then
    echo "  ✅ Created backups (flake.nix.backup, rocm-overlay.nix.backup)"
    echo "  ✅ Created rocm-overlay-gfx110x.nix"
    echo "  ✅ Created rocm-overlay-gfx1151.nix"
    echo "  ✅ Updated policy/rocm-policy.json"
else
    echo "  ℹ️  DRY RUN - No files were modified"
fi
echo ""
echo "Remaining Manual Steps:"
echo "  ⏳ Edit flake.nix (see instructions above)"
echo "  ⏳ Review rocm-overlay-gfx110x.nix (remove vLLM patches)"
echo "  ⏳ Test builds (nix flake check, nix build)"
echo "  ⏳ Run validation (./scripts/validate-targets.sh)"
echo ""
echo "Documentation:"
echo "  📖 FLAKE_CHANGES.md - Complete modification guide"
echo "  📖 IMPLEMENTATION_SUMMARY.md - Implementation checklist"
echo "  📖 TARGETS.md - User guide"
echo ""
echo "Next Command:"
echo "  \$EDITOR flake.nix  # Apply manual changes"
echo ""

if [ "$DRY_RUN" = false ]; then
    log_success "Implementation foundation complete!"
else
    log_info "Dry run complete. Run without --check to apply changes."
fi
