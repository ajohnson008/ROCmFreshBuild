# Gator-Mini Scan (gator-mini-scan) 🔬

Status: Deferred (placeholder for scanner integration)

Contracts & expected reports

- Contract dir: `contracts/gator-mini/`
- Expected outputs (future scanner):
  - `nvidia-contamination.json`
  - `sbom.json`
  - `vulnerability-analysis.json`
  - `reproducibility-check.json`
  - `integrity-check.json`

Notes

- When integrated, run this after build-pass-a completes and artifacts are available.
- Preserve scanner outputs under `runs/$RUN_ID/reports/` for evidence and contract compliance.