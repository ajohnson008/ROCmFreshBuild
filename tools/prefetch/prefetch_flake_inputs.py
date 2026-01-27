#!/usr/bin/env python3.11
"""
Prefetch Flake Inputs - Offline-ready flake input caching

This script:
1. Runs `nix flake prefetch-inputs` to cache all transitive inputs
2. Records results to run directory
3. Supports network-only phase isolation

Usage:
    python prefetch_flake_inputs.py --flake . --run-id <run-id>
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, Optional


def prefetch_flake_inputs(
    flake_path: Path,
    run_id: Optional[str] = None,
    repo_root: Optional[Path] = None
) -> Dict[str, Any]:
    """Prefetch all flake inputs recursively"""
    
    started_at = datetime.now(timezone.utc).isoformat()
    
    # Run nix flake archive (alternative to prefetch-inputs)
    result = subprocess.run(
        ['nix', 'flake', 'archive', str(flake_path), '--json'],
        capture_output=True,
        text=True
    )
    
    ended_at = datetime.now(timezone.utc).isoformat()
    
    report = {
        "operation": "prefetch_flake_inputs",
        "flake_path": str(flake_path),
        "started_at": started_at,
        "ended_at": ended_at,
        "exit_code": result.returncode,
        "success": result.returncode == 0
    }
    
    if result.returncode == 0 and result.stdout.strip():
        try:
            report["inputs"] = json.loads(result.stdout)
        except json.JSONDecodeError:
            report["stdout"] = result.stdout[:2000]
    elif result.stderr:
        report["error"] = result.stderr[:2000]
        
    # Write to run directory if provided
    if run_id and repo_root:
        run_dir = repo_root / "runs" / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        
        report_path = run_dir / "prefetch-report.json"
        with open(report_path, 'w') as f:
            json.dump(report, f, indent=2)
            f.write('\n')
            
        # Emit event
        event = {
            "event": "prefetch_complete",
            "timestamp": ended_at,
            "run_id": run_id,
            "success": report["success"],
            "exit_code": result.returncode
        }
        events_path = run_dir / "events.jsonl"
        with open(events_path, 'a') as f:
            f.write(json.dumps(event, separators=(',', ':')) + '\n')
            
    return report


def main():
    parser = argparse.ArgumentParser(
        description="Prefetch flake inputs for offline builds"
    )
    parser.add_argument(
        "--flake",
        type=Path,
        default=Path.cwd(),
        help="Path to flake"
    )
    parser.add_argument(
        "--run-id",
        help="Run ID for evidence tracking"
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path.cwd(),
        help="Repository root"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output JSON"
    )
    
    args = parser.parse_args()
    
    print(f"Prefetching flake inputs from: {args.flake}")
    
    report = prefetch_flake_inputs(
        flake_path=args.flake,
        run_id=args.run_id,
        repo_root=args.repo_root
    )
    
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        if report["success"]:
            print("✅ Flake inputs prefetched successfully")
        else:
            print(f"❌ Prefetch failed: {report.get('error', 'unknown error')}")
            
    sys.exit(0 if report["success"] else 1)


if __name__ == "__main__":
    main()
