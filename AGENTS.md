# AI Collaboration Guide for TheRockBuilder v6.0

**Purpose**: Guidelines for AI assistants (Claude Opus, GPT-4, etc.) working on this project  
**Version**: 1.0  
**Last Updated**: January 26, 2026

---

## 🤖 AI Assistant Profiles

### Primary: Claude Opus 4.5 (Build Execution)

**Role**: Build engineer and validator  
**Strengths**: Long context, code execution, systematic validation  
**Usage**: Deploy pre-written code, run builds, troubleshoot issues  

**Assigned Documents**:
- `opus_instructions.md` - Deployment instructions
- `opus_prompt_pack.md` - Complete code reference
- `vscode_skill_agent.md` - Operating guidelines

**Key Responsibilities**:
- Extract code from prompt pack into flake.nix
- Execute builds stage-by-stage
- Run validation tests
- Monitor resource usage
- Troubleshoot build failures
- Report results to user

---
## 🤖 Jules (The Operator)
**Role:** Facility Maintenance & State Enforcement
**Directives:**
1.  **The "Clean Room" Rule:** Before any specialized agent (e.g., *Palladio*, *Scryer*) begins a major task, you must run the **State Enforcement Protocol** to ensure the workspace is clean.
2.  **Tooling:**
    - To prep the repo: `bash scripts/jules/enforce_nexus_state.sh`
    - To fix simple linting/formatting: `just lint` (if available) or standard Python/Bash formatters.
3.  **Failure Protocol:** If the State Enforcement script fails, you are NOT authorized to proceed with feature work. You must fix the hygiene or audit error first.

### Secondary: Claude Sonnet 4.5 (Documentation & Support)

**Role**: Documentation writer and support assistant  
**Strengths**: Fast response, concise explanations, debugging help  
**Usage**: Answer questions, explain errors, update docs  

**Assigned Documents**:
- `README.md` - Project overview
- `HOW-TO.md` - User guide
- `PRD_v6.0.md` - Technical specification

**Key Responsibilities**:
- Answer user questions about build process
- Explain error messages
- Suggest quick fixes for common issues
- Update documentation based on new findings

---

### Tertiary: GPT-4 / Other Models (Analysis & Review)

**Role**: Code reviewer and architectural consultant  
**Strengths**: Broad knowledge, pattern recognition  
**Usage**: Review changes, suggest optimizations  

**Key Responsibilities**:
- Review proposed changes to flake.nix
- Suggest performance optimizations
- Identify security issues
- Compare approaches (Nix vs Docker, etc.)

---

## 🎯 Collaboration Workflows

### Workflow 1: Initial Build (Opus 4.5)

**Human initiates**:
```
"Start TheRockBuilder v6.0 build. Documents provided:
- PRD v6.0
- Skill Agent guidelines  
- Prompt Pack with complete code"
```

**Opus responds**:
1. Confirms receipt of all three documents
2. Verifies prerequisites (Nix version, disk space, RAM)
3. Extracts Stage 1 code from prompt pack
4. Creates flake.nix with Stage 1 code
5. Runs build: `nix build .#gcc14`
6. Executes all validation tests
7. Reports results

**Expected output**:
```
Stage 1: GCC 14.2.1 - COMPLETE
✅ Build completed in 28 minutes
✅ Version check passed (14.2.1)
✅ All 6 validation tests passed
✅ Git checkpoint created (stage-1-success)

Ready to proceed to Stage 2?
```

**Human approves**: "Yes, proceed to Stage 2"

**Opus continues** with Stage 2...

---

### Workflow 2: Troubleshooting (Sonnet 4.5)

**Human encounters error**:
```
"Build failed with error:
error: hash mismatch in fixed-output derivation
  specified: sha256:abc123...
  got:       sha256:xyz789...
What do I do?"
```

**Sonnet responds**:
```
This is a hash mismatch error. The source file changed since 
the hash was computed.

Fix:
1. Get the correct hash:
   nix-prefetch-url https://github.com/ROCm/ROCm/archive/refs/tags/rocm-7.2.0.tar.gz

2. Copy the output hash (xyz789...)

3. Update flake.nix line 267:
   sha256 = "xyz789...";  # Replace abc123 with the new hash

4. Rebuild:
   nix build .#rocm
```

**Human follows fix**: Build succeeds

---

### Workflow 3: Code Review (GPT-4)

**Human proposes change**:
```
"I want to update PyTorch to 2.11.0 instead of 2.10.0.
Here's my proposed change to flake.nix:

[paste code diff]

Will this work? Any issues?"
```

**GPT-4 reviews**:
```
Potential issues with this change:

1. ✅ Version update looks correct
2. ⚠️  You'll need to update the sha256 hash
3. ⚠️  PyTorch 2.11.0 may require ROCm 7.3.0 (compatibility check needed)
4. ❌ Missing update to propagatedBuildInputs - PyTorch 2.11 needs 
   numpy>=1.24 (you have 1.23)

Recommendation:
- Check PyTorch 2.11 release notes for ROCm compatibility
- Update numpy version in propagatedBuildInputs
- Run nix-prefetch-url to get new hash
- Test in isolation before full integration
```

**Human**: Makes adjustments based on review

---

### Workflow 4: Architecture Discussion (Multiple AIs)

**Human asks complex question**:
```
"Should I switch from Nix to Docker + Conda for easier maintenance?
Team is struggling with Nix learning curve."
```

**Claude Opus 4.5**:
```
From a build execution perspective:

Pros of staying with Nix:
- We've already invested 11 hours in the build
- Reproducibility is working perfectly
- NVIDIA isolation is battle-tested

Cons:
- Team learning curve is real
- Harder to find Nix expertise for support
- Maintenance burden on small team

My recommendation: If team <5 people and unfamiliar with Nix, 
Docker may be more practical despite lower reproducibility.
```

**Claude Sonnet 4.5**:
```
Consider a hybrid approach:

1. Keep the Nix build system for releases
2. Provide Docker images built FROM the Nix bundle
3. Daily development uses Docker
4. Official releases use Nix for reproducibility

This gives you both:
- Easy daily workflow (Docker)
- Guaranteed reproducibility for releases (Nix)
```

**GPT-4**:
```
Industry perspective:

Docker + Conda is the standard for ML in 2026:
- 95% of ML teams use this stack
- Massive community support
- Much faster iteration

Nix is niche (~5% adoption) but superior for:
- Regulatory compliance (medical, finance)
- Long-term support (5+ year reproducibility)
- Air-gapped deployments

Decision framework:
- If compliance/air-gapped: Stay with Nix
- If speed-to-market: Switch to Docker
- If both: Hybrid approach (Sonnet's suggestion)
```

**Human**: Makes informed decision with multiple perspectives

---

## 📐 Code Contribution Guidelines for AI

### When Modifying flake.nix

**✅ DO**:
- Explain WHY the change is needed
- Show before/after code diffs
- List affected components
- Propose validation steps
- Estimate impact on build time

**❌ DON'T**:
- Make changes without explaining reasoning
- Skip validation after changes
- Modify multiple stages simultaneously
- Change version numbers without checking compatibility

**Template for proposing changes**:
```
Change: [Brief description]

Reasoning: [Why this change is needed]

Affected Components:
- Component A (rebuild required)
- Component B (no rebuild needed)

Code Diff:
[Show specific lines changed]

Validation Plan:
1. Test X
2. Test Y
3. Test Z

Estimated Impact:
- Build time: +30 minutes
- New dependencies: None
- Risk level: Low/Medium/High
```

---

## 🧪 Testing Requirements

### All AI Changes Must Include Tests

**For new derivations**:
```nix
# Add postInstall validation
postInstall = ''
  # Test 1: Binary exists
  test -f $out/bin/myprogram
  
  # Test 2: Version check
  $out/bin/myprogram --version | grep -q "1.0.0"
  
  # Test 3: Dependencies correct
  ldd $out/bin/myprogram | grep -q "librocm"
'';
```

**For build changes**:
1. Verify component builds: `nix build .#component`
2. Run smoke test: Import/execute basic operation
3. Check for contamination: `nix run .#binary-scanner -- ./result`

**For system changes**:
1. Run integration tests: `nix run .#integration-test-suite`
2. Verify reproducibility: `nix run .#reproducibility-test`
3. Test offline bundle: `nix run .#bundle-creator`

---

## 🔄 AI Handoff Protocols

### When Handing Off Between AI Models

**Outgoing AI provides**:
```
Handoff Summary:
- Current stage: [Stage number and status]
- Last successful operation: [What worked]
- Known issues: [Any warnings or problems]
- Next steps: [What needs to happen next]
- Context files: [Which docs are relevant]
- Build artifacts: [What's in /nix/store]
```

**Incoming AI acknowledges**:
```
Handoff received:
- Stage [N] verified as complete ✅
- Issues noted: [List]
- Proceeding with: [Next action]
```

**Example**:
```
Opus → Sonnet Handoff:

Opus:
"Stage 3 complete. PyTorch built successfully but received 2 warnings 
about deprecated APIs (non-critical). Build time was 4.2 hours (expected 4.0).
Memory peaked at 47GB. Next step: Stage 4 (vLLM + llama.cpp).
Relevant docs: opus_prompt_pack.md lines 581-950."

Sonnet:
"Understood. PyTorch warnings noted (will monitor if they recur). 
Proceeding with Stage 4 vLLM build. Estimated completion: 2 hours."
```

---

## 🎨 Communication Style Guidelines

### For Claude Opus (Build Execution)

**Style**: Methodical, detailed, progress-oriented

**Good**:
```
Stage 2: ROCm 7.2.0 - IN PROGRESS
⏱️  Elapsed: 1.2 hours / 2.0 expected
💾 Memory: 22GB / 64GB
🔧 Current: Compiling HIP runtime (78% complete)
⚠️  1 warning (deprecated cmake variable, non-critical)
```

**Bad**:
```
Building ROCm, looks fine
```

### For Claude Sonnet (Q&A Support)

**Style**: Concise, actionable, friendly

**Good**:
```
Hash mismatch = source file changed.

Quick fix:
1. Run: nix-prefetch-url <URL>
2. Copy the hash
3. Update line 267 in flake.nix
4. Rebuild

Usually takes 5 minutes to fix.
```

**Bad**:
```
This error occurs when the cryptographic hash verification fails 
during the source fetching phase of the Nix derivation evaluation 
process, which can be remediated by obtaining the correct hash 
through the nix-prefetch-url utility...
[3 more paragraphs]
```

### For GPT-4 (Architecture Review)

**Style**: Analytical, comparative, pros/cons

**Good**:
```
Approach A (Nix):
✅ Reproducible
❌ Steep learning curve

Approach B (Docker):
✅ Easier maintenance
❌ Less reproducible

Recommendation: Choose Nix if compliance required, Docker otherwise.
```

---

## 🚨 Error Handling Protocols

### Severity Levels

**Level 1: CRITICAL** (Build cannot proceed)
- OOM kill during PyTorch
- Hash verification failures
- NVIDIA contamination detected

**Action**: STOP immediately, report to human, propose fix

**Level 2: WARNING** (Build proceeds but issue noted)
- Deprecated API warnings
- Build time 20% over estimate
- Minor dependency version mismatches

**Action**: Log warning, complete build, report in summary

**Level 3: INFO** (Normal informational)
- Build progress updates
- Validation test passes
- Cache hits

**Action**: Include in progress reports

### Error Reporting Template

```
🚨 CRITICAL ERROR 🚨

Component: PyTorch 2.10.0 build
Stage: 3 (of 6)
Error Type: Out of Memory (OOM kill)

Error Message:
"Killed (signal 9)"

Context:
- Build was 87% complete (3.5 hours in)
- Memory usage peaked at 62GB
- System went into swap

Diagnosis:
PyTorch compilation spawned too many parallel jobs.
With MAX_JOBS=8, peak memory exceeded 64GB capacity.

Proposed Solution:
1. Reduce MAX_JOBS to 4 in PyTorch buildPhase
2. Add more aggressive throttling in build-orchestrator
3. Retry build

Estimated Recovery Time: 4 hours (rebuild from checkpoint)

Alternative: Add 32GB swap space, retry with MAX_JOBS=8

Awaiting human approval to proceed with solution.
```

---

## 📚 Knowledge Base Maintenance

### When AI Discovers New Issues

**Document immediately in this format**:

```markdown
## Issue: [Short description]

**First encountered**: [Date, stage, component]
**Frequency**: [One-time / Occasional / Frequent]
**Impact**: [Critical / Warning / Info]

**Symptoms**:
- [Observable behavior]

**Root cause**:
- [Technical explanation]

**Solution**:
- [Step-by-step fix]

**Prevention**:
- [How to avoid in future]

**Related issues**:
- [Links to similar problems]
```

**Location**: Add to `docs/known_issues.md`

### When AI Finds Optimization

**Document in this format**:

```markdown
## Optimization: [Description]

**Component**: [Which part of system]
**Benefit**: [Reduced build time / memory / disk usage]
**Measurement**: 
- Before: [Metric]
- After: [Metric]
- Improvement: [Percentage]

**Implementation**:
[Code changes required]

**Trade-offs**:
- [Any downsides]

**Recommendation**: [Adopt / Test further / Skip]
```

**Location**: Add to `docs/optimizations.md`

---

## 🤝 Multi-AI Collaboration Patterns

### Pattern 1: Parallel Analysis

**Scenario**: Complex architectural decision

**Approach**:
1. Human poses question to multiple AIs simultaneously
2. Each AI analyzes from their strength perspective
3. Human synthesizes answers
4. AIs discuss any disagreements
5. Human makes final decision

**Example**: "Should we update to ROCm 7.3.0?"

- Opus: Build impact analysis
- Sonnet: Compatibility research
- GPT-4: Industry trends, risk assessment

### Pattern 2: Sequential Handoff

**Scenario**: Long-running build process

**Approach**:
1. Opus starts build, monitors for 4 hours
2. Hands off to Sonnet with status summary
3. Sonnet continues monitoring overnight
4. Hands back to Opus for validation

**Requires**: Clear handoff summaries (see above)

### Pattern 3: Review Chain

**Scenario**: Code change proposal

**Approach**:
1. Human proposes change
2. Opus: Technical feasibility check
3. Sonnet: Documentation impact assessment
4. GPT-4: Security and best practices review
5. All AIs: Vote approve/reject/needs-revision
6. Human makes final decision

---

## 📊 Performance Metrics for AI

### Build Execution (Opus)

**Measured**:
- Build time vs estimate accuracy (target: ±10%)
- Validation pass rate (target: 100%)
- Issue detection rate (find issues before human notices)

**Reported monthly**:
```
Opus Performance Report:
- Builds completed: 12
- Average time accuracy: 8% over estimate
- Validation pass rate: 100%
- Issues caught proactively: 7
- Issues missed: 0
```

### Support Quality (Sonnet)

**Measured**:
- Response time (target: <2 minutes)
- Solution success rate (target: >90%)
- Follow-up questions needed (target: <20%)

**Reported monthly**:
```
Sonnet Performance Report:
- Questions answered: 47
- Avg response time: 1.8 minutes
- First-response-resolution: 89%
- User satisfaction: 4.6/5.0
```

---

## 🎓 Learning & Improvement

### AI Knowledge Updates

When new information discovered:

1. **Verify**: Test the finding thoroughly
2. **Document**: Add to knowledge base
3. **Share**: Update relevant sections
4. **Review**: Flag for human review if significant

**Example**:
```
Discovery: ROCm 7.2.0 builds 15% faster with ninja-1.11.1

Actions taken:
1. ✅ Verified with 3 builds (reproducible)
2. ✅ Updated flake.nix to prefer ninja 1.11.1
3. ✅ Added to optimizations.md
4. ⏳ Flagged for human code review
```

### Continuous Improvement

**Weekly retrospective** (AI self-assessment):
```
What went well:
- All builds completed without human intervention
- 3 issues caught before becoming critical

What could improve:
- Better memory prediction (2 builds approached OOM)
- Earlier detection of build time anomalies

Action items:
- Enhance memory monitoring thresholds
- Add predictive build time modeling
```

---

## 🔐 Security & Safety

### AI Safety Protocols

**NEVER**:
- Disable safety checks "temporarily"
- Skip validation to save time
- Make undocumented changes
- Proceed after critical errors without approval

**ALWAYS**:
- Run binary scanner after builds
- Verify NVIDIA isolation
- Check SBOM for critical CVEs
- Report security findings immediately

### Sensitive Information Handling

**Treat as confidential**:
- Build system credentials
- Internal package repositories
- Unpublished model weights
- Organization-specific configurations

**Public information**:
- Nix flake code (MIT licensed)
- Build times and metrics
- Error messages (after scrubbing paths)
- Performance benchmarks

---

## 📞 Escalation Paths

### When AI Should Escalate to Human

**Immediate escalation**:
- Critical security vulnerability discovered
- NVIDIA contamination detected after Stage 5
- Data loss risk (corrupted /nix/store)
- Reproducibility test fails

**Escalate within 1 hour**:
- Build failure after 2 retry attempts
- New error type (not in knowledge base)
- Resource exhaustion (out of disk/memory)

**Escalate within 24 hours**:
- Non-critical optimization opportunities
- Documentation gaps
- Nice-to-have feature ideas

### Escalation Template

```
🚨 ESCALATION REQUIRED 🚨

Priority: [IMMEDIATE / 1-HOUR / 24-HOUR]
AI: [Which AI is escalating]
Component: [Affected system]

Issue:
[Clear description]

Impact:
[What this affects]

Attempts to resolve:
1. [What was tried]
2. [Results]

Recommendation:
[Suggested next step]

Awaiting human decision.
```

---

## ✅ AI Collaboration Checklist

Before starting work:
- [ ] Read all assigned documentation
- [ ] Understand current project state
- [ ] Verify prerequisites met
- [ ] Confirm role and responsibilities

During work:
- [ ] Follow stage-by-stage progression
- [ ] Run all validation tests
- [ ] Monitor resource usage
- [ ] Document findings
- [ ] Report progress regularly

After completion:
- [ ] Verify all tests passed
- [ ] Create git checkpoint
- [ ] Update documentation
- [ ] Prepare handoff summary (if applicable)
- [ ] Report final results

---

## 📖 Quick Reference

**For Claude Opus 4.5**:
- Primary doc: `opus_instructions.md`
- Code source: `opus_prompt_pack.md`
- Guidelines: `vscode_skill_agent.md`
- Role: Build execution and validation

**For Claude Sonnet 4.5**:
- Primary doc: `HOW-TO.md`
- Reference: `README.md`, `PRD_v6.0.md`
- Role: User support and troubleshooting

**For GPT-4 / Others**:
- Primary doc: `PRD_v6.0.md`
- Reference: All documentation
- Role: Analysis and review

---

**This collaboration guide is a living document. AI assistants should propose updates based on discovered patterns, new issues, and improved workflows.**

**Last reviewed**: January 26, 2026  
**Next review**: March 2026 or after major project changes