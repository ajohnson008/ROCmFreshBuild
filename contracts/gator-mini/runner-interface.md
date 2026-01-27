# Gator-Mini Runner Interface

## Purpose

Machine-oriented interface specification for Gator-Mini scanner integration.

## Interface Version

`1.0.0`

## Invocation

```
gator-mini scan \
  --target <path-or-store-ref> \
  --run-id <run-id> \
  --output-dir runs/<run-id>/reports/ \
  --config contracts/gator-mini/expected-reports.json
```

## Required Environment

- `REPO_ROOT`: Repository root path
- `RUN_ID`: Current run identifier
- `SOURCE_LOCK`: Path to source-lock.json
- `MANIFEST_SHA256`: Manifest hash for verification

## Input Contracts

### Target Specification

The scanner receives:

1. `target_path`: Nix store path or local path to scan
2. `run_id`: Run identifier for output correlation
3. `source_lock`: Path to source-lock.json for hash verification

### Configuration

Scanner reads `expected-reports.json` to determine required reports.

## Output Contracts

### Report Files

All reports written to: `runs/<run-id>/reports/`

Each report must:

1. Validate against its schema in `report-schemas/`
2. Include `version` field matching schema version
3. Include timestamp in ISO 8601 format

### Event Emission

Scanner emits events to `runs/<run-id>/events.jsonl`:

```json
{"event": "scan_start", "scanner": "gator-mini", "timestamp": "..."}
{"event": "report_generated", "report": "nvidia-contamination.json", "timestamp": "..."}
{"event": "scan_complete", "success": true, "timestamp": "..."}
```

## Error Handling

On failure:

1. Write partial report with `"result": "error"`
2. Emit `scan_error` event with error details
3. Exit with non-zero code

## Validation

Receipt generator validates:

1. All required reports exist
2. Reports validate against schemas
3. Report timestamps within run window

## Integration Points

### Pre-scan

- Policy fence must pass
- Source lock must exist
- Build must have completed

### Post-scan

- Receipt includes report references
- Summary includes scan results
- Artifacts indexed by hash
