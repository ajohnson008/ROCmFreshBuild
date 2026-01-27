# ROCmFreshBuild vNext (Pass A Only) — Product Requirements Document (PRD)

## 0) Executive Summary
ROCmFreshBuild vNext is a **mirror-first, evidence-driven, Nix-flake build environment** that produces a deterministic ROCm + AI stack for **ROCm 7.2.0 only** and **gfx1151 only (Pass A)**.

It is designed to:
- **Stop ROCm version drift** (forbidden to enter ROCm 6.x or arbitrary 7.x variants).
- **Parallel acquire** all required sources (40+ repos + tarballs) via local mirrors.
- **Derive and enforce build order** from a generated dependency graph.
- Emit a **production-grade evidence spine** (structured logs, receipts, manifests) that local AI agents can treat as the **source of truth**.

Pass B (fat-arch gfx110X-all augmentation) is **explicitly not created** in this repo until NexusJr arrives.

---

## 1) Goals
### 1.1 Primary Goals (Must)
1) **ROCm 7.2.0 fence**: hard-pin to ROCm 7.2.0 release pins; fail on any drift.
2) **Mirror-first acquisition**: all network activity occurs in a controlled **sync/prefetch phase**; builds use mirrors/offline stores.
3) **Correct build order**: generate a DAG and enforce topo build layers for ROCm core + AI layers.
4) **Production evidence**: each run produces a run-id directory with structured events and a receipt binding inputs → outputs → checks.
5) **Editor-friendly operation**: “works now” via VS Code tasks (and antigravity-compatible CLI surface).

### 1.2 Secondary Goals (Should)
- Deterministic-ish rebuilds with explainable nondeterminism.
- Supply-chain traceability: source locks, hashes, provenance, and future signing readiness.
- Future local-agent readiness: artifacts are queryable and machine-readable.

### 1.3 Non-Goals (Now)
- Pass B implementation.
- NexusJr sidecar/RPC integration.
- Full end-user “installer UX” beyond a minimal offline bundle prototype.

---

## 2) Hard Constraints & Policies
### 2.1 ROCm Version Policy (Non-Negotiable)
- Allowed ROCm release: **7.2.0 only**.
- Forbidden:
  - Any ROCm **6.x** sources, tags, manifests, or inferred upgrades.
  - Any “latest” behavior (branches/tags without resolved commit SHAs).

**Policy enforcement must happen before any build** and must hard-fail with an offender list.

### 2.2 GPU Target Policy (Pass A)
- Pass A targets: **gfx1151 only**.
- No fat-arch behavior in this repo.
- Any runtime overrides must be **opt-in**, recorded in receipts, and never silently applied.

### 2.3 Network Policy
- Only these phases may touch the network:
  - mirror sync (git + tarballs)
  - flake inputs prefetch
- Build phases must be able to run with **network disabled** (mirror-only mode).

### 2.4 Evidence Policy
- Every actionable recommendation must be grounded in:
  - a manifest entry
  - a lock entry
  - a build rule/build log event
  - a scanner output

Agents must treat evidence artifacts as primary sources.

---

## 3) Inputs / Outputs
### 3.1 Inputs
- Upstream ROCm release manifest for 7.2.0 (archived and hashed).
- Repo configuration:
  - mirror locations
  - concurrency settings for the 3960X
  - policy (ROCm fence, GPU target, network mode)

### 3.2 Outputs
Each run produces:
- **Receipts**: inputs (pins + hashes) → outputs (artifact hashes) → checks (pass/fail).
- **Graph artifacts**: dependency DAG + build order layers.
- **Logs**: structured JSONL event stream + human summary.
- **Reports**: integrity, contamination, SBOM, vulnerability decision, reproducibility (as implemented).

---

## 4) Architecture

### 4.1 Planes
**A) Acquisition Plane (Mirror-First)**
- Git mirrors for all manifest repos.
- Blob/tarball mirror for fixed-output sources.
- Flake input prefetch for transitive inputs.

**B) Evidence Plane (Build + Checks)**
- Graph extraction → enforced order.
- Build (ROCm core → PyTorch → vLLM → llama.cpp).
- Scanners + SBOM + reproducibility tests.
- Receipt + run evidence packaging.

### 4.2 Artifact Registry Layout (Local)
- `pinned/rocm/7.2.0/`
  - `default.xml`
  - `default.xml.sha256`
  - `source-lock.json`
- `mirrors/`
  - `git/` (mirrors)
  - `blobs/` (content-addressed)
  - `git/index.json`
  - `blobs/index.json`
- `graph/`
  - `graph.json`
  - `order.json`
- `runs/<run-id>/`
  - `status.json`
  - `events.jsonl`
  - `summary.md`
  - `receipt.json`
  - `reports/…`
  - `artifacts/…`

---

## 5) Build Graph & Order Enforcement

### 5.1 Graph Extraction
The graph generator must inspect:
- CMake build entrypoints (`CMakeLists.txt`, toolchain files, exported targets)
- Kconfig/DKMS rules (if kernel modules appear)
- Python packaging (`pyproject.toml`, setup config)
- Linkage signals (DT_NEEDED, rpaths, installed libs)

Graph output:
- `graph.json`: nodes, edges, and **edge reasons**.
- `order.json`: topo layers (parallel sets) + serialization constraints.

### 5.2 Order Enforcement
Build driver must:
- Build in topo layer order.
- Within a layer, parallelize components when safe.
- Fail legibly and emit a failure class.

---

## 6) Mirror-First Acquisition

### 6.1 Git Mirrors
- For each repo in `source-lock.json`, maintain a `--mirror` clone.
- Sync in parallel (bounded concurrency).
- Record:
  - last sync time
  - resolved commit SHA availability
  - integrity notes

### 6.2 Blob/Tarball Mirror
- Store by hash under `mirrors/blobs/<algo>/<hash>`.
- Maintain index with provenance and size.

### 6.3 Flake Input Prefetch
- Prefetch transitive flake inputs before builds.
- Store a prefetch report with timing and resolved store paths.

---

## 7) Checks (Pass A)

### 7.1 Integrity Checks (Fail Fast)
- No floating refs (all repos pinned to commit SHA).
- Manifest hash matches expected.
- Tarballs match expected hashes.
- Mirror-only mode is possible.

### 7.2 Contamination Checks (NVIDIA/CUDA Isolation)
- DT_NEEDED scan: no CUDA/NVIDIA libs pulled by dynamic deps.
- Symbol scan + strings scan: detect CUDA/NVIDIA fingerprints.
- Closure audit: ensure no unintended dependency pulls.

### 7.3 SBOM + Vulnerability Policy
- Generate SBOM for produced artifacts.
- Produce vulnerability report and a policy decision.

### 7.4 Reproducibility (Incremental)
- v1: same-run artifact hash indexing + deterministic build metadata.
- vNext: rebuild twice under identical pins and compare outputs; on mismatch emit diff evidence.

---

## 8) Logging, Receipts, and “Agent as Source”

### 8.1 Structured Event Model
- JSONL events for every phase:
  - `phase_start`, `phase_end`
  - `component_start`, `component_end`
  - `command`, `stdout_tail`, `stderr_tail`
  - `artifact_emitted` (hashes)
  - `check_result`

### 8.2 Receipt Schema (Minimum)
Receipt must include:
- `run_id`, `timestamp`, `host_fingerprint`
- `policy_version`
- `pins`:
  - `rocm_manifest_sha256`
  - `source_lock_sha256`
  - `flake_lock_sha256`
- `targets`:
  - `GPU_TARGETS` (or compatibility value)
- `outputs`:
  - artifact hashes, SBOM hash, report hashes
- `checks`:
  - pass/fail + offender lists

### 8.3 “Agent Knowledge Bundle”
Agents must rely on:
- `receipt.json`
- `graph.json` / `order.json`
- `reports/*`
- `events.jsonl` (canonical execution record)

Agents are forbidden from guessing when evidence exists.

---

## 9) Operational UX (VS Code + antigravity)

### 9.1 Single Entry Surface
Provide a minimal command surface:
- `sync-mirrors`
- `prefetch-flake-inputs`
- `generate-graph`
- `build-rocm-core`
- `build-pytorch`
- `build-stack`
- `run-checks`

### 9.2 VS Code Tasks
Provide tasks that map 1:1 to the above.
Each task prints:
- active manifest version
- active target
- run-id
- where logs live

---

## 10) Concurrency & Resource Policy (3960X / 64GB)

### 10.1 Download Parallelism
- High concurrency for mirror sync and tarball fetch.
- Nix fetch/substitution concurrency tuned to saturate network without starving IO.

### 10.2 Build Parallelism
- Bound concurrent heavy builds to avoid OOM.
- Prefer wider parallelism at the component level with smaller per-component `-j` where applicable.

---

## 11) Acceptance Criteria (Pass A v1)
1) **No drift**: any attempt to pull ROCm 6.x or a non-7.2.0 pinset hard-fails.
2) **A→Z acquisition**: all sources required for the build are mirrored locally.
3) **Graph enforced**: build runs follow `order.json` and are reproducible in ordering.
4) **Evidence spine**: run produces structured logs + receipt + reports.
5) **Editor workflow**: VS Code tasks can run the full pipeline on a fresh machine.

---

# Opus 4.5 Prompt Pack (VS Code) — Best Practices

## Pack Principles (apply to all prompts)
- **ROCm 7.2.0 only**. Never propose ROCm 6.x, never “upgrade to latest,” never suggest drifting tags.
- Treat `pinned/rocm/7.2.0/default.xml` + `source-lock.json` + `flake.lock` as ground truth.
- Every output must cite evidence from the repo artifacts (graph, receipt, reports, logs).
- Prefer smallest-change, reversible edits.
- Produce explicit file-by-file change lists.

---

## Prompt 0 — System / Project Header (paste into VS Code agent system prompt)
You are BUILD-SHERLOCK, a forensic build-forensics architect. Your job is to harden ROCmFreshBuild into a deterministic, mirror-first, evidence-driven build environment.

Hard constraints:
- ROCm release is 7.2.0 ONLY. ROCm 6.x is forbidden.
- Pass A only: gfx1151 only.
- Do not create Pass B outputs, folders, commands, tasks, or docs.
- Network is allowed only during mirror sync and flake prefetch phases.

Success means: the repo builds in correct order, emits structured evidence, and can be operated via VS Code tasks.

---

## Prompt 1 — Repo Recon + Evidence Index
Task: Build an evidence index of the current repo.

Inputs:
- Entire repository tree.

Output:
1) Current command surface and entrypoints (flake apps/checks, scripts).
2) Current logging locations.
3) Existing verification artifacts.
4) A “gaps list” vs the PRD (with exact file references).

Rules:
- No speculation where files exist.
- Use a concise bullet list per item.

---

## Prompt 2 — ROCm 7.2.0 Fence Implementation Plan
Task: Implement the ROCm 7.2.0 hard fence.

Output:
- Exact policy file(s) to add.
- Exact validation logic placement.
- Explicit failure messages and offender list format.
- Tests to prove:
  - a 6.x pin fails
  - a floating ref fails
  - correct 7.2.0 pins pass

Also include:
- Everything added
- Everything removed/disabled

---

## Prompt 3 — Manifest Ingestion → source-lock.json
Task: Implement ingestion of ROCm 7.2.0 `default.xml` and generate `source-lock.json`.

Output:
- File layout under `pinned/rocm/7.2.0/`.
- Schema for `source-lock.json`.
- How manifest hash is computed and stored.
- How lock hash is computed and recorded.
- Unit tests for parsing stability.

---

## Prompt 4 — Mirror-First Sync (Parallel)
Task: Implement mirror sync for all repos/tarballs.

Output:
- Mirror directory layout.
- Concurrency design (bounded parallelism).
- Index file schemas for git and blobs.
- A mirror-only mode switch.
- Logs/events emitted for sync.

---

## Prompt 5 — Graph Extraction + order.json
Task: Add build graph extraction that produces `graph.json` and `order.json`.

Output:
- Node and edge schema (include “reason”).
- How you detect dependencies for:
  - CMake libraries
  - Python packages
  - toolchain/runtime requirements
- How you enforce order in the build driver.
- A small “graph sanity test” suite.

---

## Prompt 6 — Evidence Spine (runs/<run-id>)
Task: Move logging to production-grade run directories.

Output:
- run-id format
- event schema (JSONL)
- receipt schema
- how legacy root logs are retained as pointers (if required)

Acceptance tests:
- a failed build produces a complete receipt + logs
- a successful build produces artifacts + hashes

---

## Prompt 7 — Checks Implementation (Pass A)
Task: Implement Pass A checks only.

Output:
- Integrity report schema
- Contamination report schema
- SBOM + vuln decision schema
- Where these run in `nix flake check`
- How failures are classified

---

## Prompt 8 — VS Code Tasks + Operator UX
Task: Add `.vscode/tasks.json` and minimal docs so an operator can run everything.

Output:
- Task list and mapping to commands
- Standard console output header per task (manifest version, target, run-id)
- Troubleshooting section

---

## Prompt 9 — Final PRD Alignment Diff
Task: Produce a PRD compliance report.

Output:
- A checklist with “done / partial / missing”
- Evidence references (file paths + run artifacts)
- Top 5 remaining risks

---

## Prompt 10 — Change Control (Required in every PR)
Before coding, output:
1) Files to add
2) Files to modify
3) Files to remove
4) New commands/tasks
5) New tests

After coding, output:
- A verification plan: exact commands to run and expected artifacts.

---

# Notes for later (Do not implement now)
- Pass B: fat-arch augmentation `gfx1151;gfx110X-all` gated behind NexusJr.
- Signing + remote cache policies.
- Sidecar RPC interface.

