#!/usr/bin/env python3
"""
Run Manager - Evidence spine for build runs

This module manages:
1. Run ID creation (YYYYMMDD-HHMMSS-<random>)
2. Event logging (events.jsonl append-only)
3. Status tracking (status.json)
4. Receipt generation (receipt.json)

Usage:
    from lib.run_manager import RunManager
    
    mgr = RunManager(repo_root)
    run_id = mgr.create_run()
    mgr.emit_event("phase_start", {"phase": "build"})
    mgr.finalize(status="success")
"""

import hashlib
import json
import os
import secrets
import sys
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Dict, Any, Optional


@dataclass
class RunStatus:
    """Current run status"""
    run_id: str
    status: str  # "pending" | "running" | "success" | "failed"
    phase: str
    started_at: str
    updated_at: str
    errors: List[str] = field(default_factory=list)
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class Phase:
    """Build phase tracking"""
    name: str
    status: str  # "pending" | "running" | "success" | "failed" | "skipped"
    started_at: Optional[str] = None
    ended_at: Optional[str] = None
    duration_seconds: Optional[float] = None
    error: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        return {k: v for k, v in d.items() if v is not None}


@dataclass
class Output:
    """Build output reference"""
    name: str
    path_or_store_ref: str
    sha256: str
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class Receipt:
    """Final run receipt"""
    run_id: str
    started_at: str
    ended_at: str
    status: str
    policy: Dict[str, Any]
    pins: Dict[str, str]
    targets: Dict[str, Any]
    phases: List[Phase]
    outputs: List[Output]
    gator_reports_expected: List[str]
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "run_id": self.run_id,
            "started_at": self.started_at,
            "ended_at": self.ended_at,
            "status": self.status,
            "policy": self.policy,
            "pins": self.pins,
            "targets": self.targets,
            "phases": [p.to_dict() for p in self.phases],
            "outputs": [o.to_dict() for o in self.outputs],
            "gator_reports_expected": self.gator_reports_expected
        }


class RunManager:
    """Manage build run evidence"""
    
    def __init__(self, repo_root: Path, run_id: Optional[str] = None):
        self.repo_root = repo_root
        self.runs_dir = repo_root / "runs"
        self.run_id = run_id
        self.run_dir: Optional[Path] = None
        self.status: Optional[RunStatus] = None
        self.phases: List[Phase] = []
        self.outputs: List[Output] = []
        self.started_at: Optional[str] = None
        
        if self.run_id:
            self.run_dir = self.runs_dir / self.run_id
            self._ensure_run_dir()
            self._load_status()
            if self.status is None:
                # Initialize status if it doesn't exist
                self.started_at = datetime.now(timezone.utc).isoformat()
                self.status = RunStatus(
                    run_id=self.run_id,
                    status="running",
                    phase="init",
                    started_at=self.started_at,
                    updated_at=self.started_at
                )
            
    def _ensure_run_dir(self):
        """Ensure run directory and subdirectories exist"""
        if self.run_dir:
            self.run_dir.mkdir(parents=True, exist_ok=True)
            (self.run_dir / "reports").mkdir(exist_ok=True)
            (self.run_dir / "artifacts").mkdir(exist_ok=True)

    def _load_status(self):
        """Load status from status.json if exists"""
        if self.run_dir and (self.run_dir / "status.json").exists():
            try:
                with open(self.run_dir / "status.json") as f:
                    data = json.load(f)
                    self.status = RunStatus(**data)
                    self.started_at = self.status.started_at
            except Exception as e:
                print(f"Warning: Failed to load status: {e}", file=sys.stderr)
        
    @staticmethod
    def generate_run_id() -> str:
        """Generate unique run ID: YYYYMMDD-HHMMSS-<random>"""
        now = datetime.now(timezone.utc)
        random_suffix = secrets.token_hex(4)
        return f"{now.strftime('%Y%m%d-%H%M%S')}-{random_suffix}"
        
    def create_run(self) -> str:
        """Create new run directory and initialize files"""
        if self.run_id is None:
            self.run_id = self.generate_run_id()
            
        self.run_dir = self.runs_dir / self.run_id
        self._ensure_run_dir()
        
        # Initialize status
        self.started_at = datetime.now(timezone.utc).isoformat()
        self.status = RunStatus(
            run_id=self.run_id,
            status="running",
            phase="init",
            started_at=self.started_at,
            updated_at=self.started_at
        )
        self._write_status()
        
        # Initialize events file
        self.emit_event("run_start", {
            "run_id": self.run_id,
            "repo_root": str(self.repo_root)
        })
        
        return self.run_id
        
    def emit_event(self, event_type: str, data: Dict[str, Any] = None):
        """Append event to events.jsonl"""
        if self.run_dir is None:
            raise RuntimeError("Run not created")
            
        event = {
            "event": event_type,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "run_id": self.run_id,
            **(data or {})
        }
        
        events_file = self.run_dir / "events.jsonl"
        with open(events_file, 'a') as f:
            f.write(json.dumps(event, separators=(',', ':')) + '\n')
            
    def start_phase(self, phase_name: str):
        """Start a build phase"""
        phase = Phase(
            name=phase_name,
            status="running",
            started_at=datetime.now(timezone.utc).isoformat()
        )
        self.phases.append(phase)
        
        self.status.phase = phase_name
        self.status.updated_at = phase.started_at
        self._write_status()
        
        self.emit_event("phase_start", {"phase": phase_name})
        
    def end_phase(self, phase_name: str, status: str = "success", error: str = None):
        """End a build phase"""
        ended_at = datetime.now(timezone.utc).isoformat()
        
        for phase in self.phases:
            if phase.name == phase_name and phase.status == "running":
                phase.status = status
                phase.ended_at = ended_at
                phase.error = error
                
                if phase.started_at:
                    start = datetime.fromisoformat(phase.started_at)
                    end = datetime.fromisoformat(ended_at)
                    phase.duration_seconds = (end - start).total_seconds()
                break
                
        self.status.updated_at = ended_at
        self._write_status()
        
        self.emit_event("phase_end", {
            "phase": phase_name,
            "status": status,
            "error": error
        })
        
    def add_output(self, name: str, path_or_store_ref: str, sha256: str = ""):
        """Add a build output"""
        self.outputs.append(Output(
            name=name,
            path_or_store_ref=path_or_store_ref,
            sha256=sha256
        ))
        
        self.emit_event("output_added", {
            "name": name,
            "path": path_or_store_ref
        })
        
    def finalize(
        self,
        status: str = "success",
        policy_hash: str = "",
        manifest_sha256: str = "",
        source_lock_sha256: str = "",
        flake_lock_sha256: str = "",
        gpu_targets: List[str] = None
    ):
        """Finalize run and generate receipt"""
        if self.run_dir is None:
            raise RuntimeError("Run not created")
            
        ended_at = datetime.now(timezone.utc).isoformat()
        
        # Update status
        self.status.status = status
        self.status.updated_at = ended_at
        self._write_status()
        
        # Generate receipt
        receipt = Receipt(
            run_id=self.run_id,
            started_at=self.started_at,
            ended_at=ended_at,
            status=status,
            policy={
                "name": "rocm-7.2.0-only",
                "hash": policy_hash
            },
            pins={
                "manifest_sha256": manifest_sha256,
                "source_lock_sha256": source_lock_sha256,
                "flake_lock_sha256": flake_lock_sha256
            },
            targets={
                "gpu_targets": gpu_targets or ["gfx1151"],
                "pass": "A"
            },
            phases=self.phases,
            outputs=self.outputs,
            gator_reports_expected=[
                "nvidia-contamination.json",
                "sbom.spdx.json",
                "vulnerability-analysis.json",
                "reproducibility-check.json"
            ]
        )
        
        # Write receipt
        receipt_path = self.run_dir / "receipt.json"
        with open(receipt_path, 'w') as f:
            json.dump(receipt.to_dict(), f, indent=2)
            f.write('\n')
            
        # Write summary
        summary = {
            "run_id": self.run_id,
            "status": status,
            "started_at": self.started_at,
            "ended_at": ended_at,
            "phase_count": len(self.phases),
            "output_count": len(self.outputs),
            "phases_passed": sum(1 for p in self.phases if p.status == "success"),
            "phases_failed": sum(1 for p in self.phases if p.status == "failed")
        }
        summary_path = self.run_dir / "summary.json"
        with open(summary_path, 'w') as f:
            json.dump(summary, f, indent=2)
            f.write('\n')
            
        self.emit_event("run_end", {
            "status": status,
            "phases": len(self.phases),
            "outputs": len(self.outputs)
        })
        
        return receipt
        
    def _write_status(self):
        """Write current status to status.json"""
        if self.run_dir is None or self.status is None:
            return
            
        status_path = self.run_dir / "status.json"
        with open(status_path, 'w') as f:
            json.dump(self.status.to_dict(), f, indent=2)
            f.write('\n')


def main():
    """CLI for run manager operations"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Run Manager CLI")
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    
    subparsers = parser.add_subparsers(dest="command", required=True)
    
    # create command
    create_parser = subparsers.add_parser("create", help="Create new run")
    create_parser.add_argument("--run-id", help="Optional run ID")
    
    # emit command
    emit_parser = subparsers.add_parser("emit", help="Emit event")
    emit_parser.add_argument("--run-id", required=True)
    emit_parser.add_argument("--event", required=True)
    emit_parser.add_argument("--data", help="JSON data")
    
    # phase-start command
    phase_start = subparsers.add_parser("phase-start", help="Start phase")
    phase_start.add_argument("--run-id", required=True)
    phase_start.add_argument("--phase", required=True)
    
    # phase-end command
    phase_end = subparsers.add_parser("phase-end", help="End phase")
    phase_end.add_argument("--run-id", required=True)
    phase_end.add_argument("--phase", required=True)
    phase_end.add_argument("--status", default="success")
    phase_end.add_argument("--error")
    
    args = parser.parse_args()
    
    mgr = RunManager(args.repo_root, run_id=getattr(args, 'run_id', None))
    
    if args.command == "create":
        run_id = mgr.create_run()
        print(json.dumps({"run_id": run_id, "run_dir": str(mgr.run_dir)}))
        
    elif args.command == "emit":
        mgr.run_dir = mgr.runs_dir / args.run_id
        data = json.loads(args.data) if args.data else {}
        mgr.emit_event(args.event, data)
        
    elif args.command == "phase-start":
        mgr.run_dir = mgr.runs_dir / args.run_id
        mgr.status = RunStatus(
            run_id=args.run_id,
            status="running",
            phase=args.phase,
            started_at="",
            updated_at=""
        )
        mgr.start_phase(args.phase)
        
    elif args.command == "phase-end":
        mgr.run_dir = mgr.runs_dir / args.run_id
        mgr.status = RunStatus(
            run_id=args.run_id,
            status="running",
            phase=args.phase,
            started_at="",
            updated_at=""
        )
        mgr.end_phase(args.phase, args.status, args.error)


if __name__ == "__main__":
    main()
