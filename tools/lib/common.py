
import os
import json
import time
import uuid
import sys
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, Any, Optional, List

class RunContext:
    """
    Manages the run context, including the run directory, receipt.json, and events.jsonl.
    Enforces the 'Evidence-first' policy.
    """
    def __init__(self, repo_root: Path, run_id: str = None):
        self.repo_root = repo_root.resolve()
        self.run_id = run_id or f"run-{int(time.time())}-{uuid.uuid4().hex[:8]}"
        self.run_dir = self.repo_root / "runs" / self.run_id
        self.receipt_file = self.run_dir / "receipt.json"
        self.events_file = self.run_dir / "events.jsonl"
        self._ensure_run_dir()
        self._load_or_init_receipt()

    def _ensure_run_dir(self):
        if not self.run_dir.exists():
            self.run_dir.mkdir(parents=True, exist_ok=True)
            # Create subdirs
            (self.run_dir / "reports").mkdir(exist_ok=True)
            (self.run_dir / "artifacts").mkdir(exist_ok=True)

    def _load_or_init_receipt(self):
        if self.receipt_file.exists():
            with open(self.receipt_file) as f:
                self.receipt = json.load(f)
        else:
            self.receipt = {
                "run_id": self.run_id,
                "start_time": datetime.now(timezone.utc).isoformat(),
                "status": "pending",
                "phases": {},
                "policy": {"decisions": []},
                "artifacts": [],
                "system_info": self._gather_system_info()
            }
            self._save_receipt()

    def _gather_system_info(self):
        return {
            "platform": os.uname().sysname,
            "release": os.uname().release,
            "machine": os.uname().machine,
            "cwd": str(Path.cwd())
        }

    def _save_receipt(self):
        with open(self.receipt_file, "w") as f:
            json.dump(self.receipt, f, indent=2)

    def log_event(self, event_type: str, data: Dict[str, Any]):
        event = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "type": event_type,
            "data": data
        }
        with open(self.events_file, "a") as f:
            f.write(json.dumps(event) + "\n")

    def update_receipt(self, update_dict: Dict[str, Any]):
        """Updates the receipt with new data, managing nested merges for known keys."""
        for k, v in update_dict.items():
            if isinstance(v, dict) and k in self.receipt and isinstance(self.receipt[k], dict):
                 self.receipt[k].update(v)
            else:
                 self.receipt[k] = v
        self._save_receipt()

    def record_phase(self, phase_name: str, status: str, details: Dict[str, Any] = None):
        """Records a phase execution in the receipt."""
        self.receipt["phases"][phase_name] = {
            "status": status,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "details": details or {}
        }
        self._save_receipt()
        self.log_event("phase_update", {"phase": phase_name, "status": status})

    def mark_failed(self, reason: str, exit_code: int = 1):
         self.receipt["status"] = "failed"
         self.receipt["failure_reason"] = reason
         self.receipt["exit_code"] = exit_code
         self.receipt["end_time"] = datetime.now(timezone.utc).isoformat()
         self._save_receipt()
         self.log_event("run_failed", {"reason": reason, "exit_code": exit_code})

    def mark_success(self):
         self.receipt["status"] = "success"
         self.receipt["end_time"] = datetime.now(timezone.utc).isoformat()
         self._save_receipt()
         self.log_event("run_success", {})
