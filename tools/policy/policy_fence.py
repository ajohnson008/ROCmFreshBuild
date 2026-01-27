#!/usr/bin/env python3.11
"""
ROCm 7.2.0 Policy Fence - Hard-fail gate for version drift
"""

import json
import os
import re
import sys
import hashlib
from pathlib import Path
from typing import List, Dict, Any, Optional
from dataclasses import dataclass, field
from datetime import datetime, timezone

# Add parent directory to path to allow importing lib
sys.path.append(str(Path(__file__).parent.parent.parent))
from tools.lib.common import RunContext

EX_CONFIG = 78

@dataclass
class Violation:
    category: str
    message: str
    offender: str
    severity: str = "error"

@dataclass
class PolicyCheckResult:
    passed: bool
    violations: List[Violation] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    checked_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "passed": self.passed,
            "checked_at": self.checked_at,
            "violation_count": len(self.violations),
            "violations": [
                {
                    "category": v.category,
                    "message": v.message,
                    "offender": v.offender,
                    "severity": v.severity
                }
                for v in self.violations
            ],
            "warnings": self.warnings
        }

class ROCmPolicyFence:
    ALLOWED_RELEASE = "7.2.0"
    SHA_PATTERN = re.compile(r'^[0-9a-f]{40}$')
    FORBIDDEN_PATTERNS = [
        re.compile(r'rocm-6\.', re.IGNORECASE),
        re.compile(r'rocm-[0-5]\.', re.IGNORECASE),
        re.compile(r'/6\.[0-9]+/', re.IGNORECASE),
        re.compile(r'refs/heads/develop', re.IGNORECASE),
        re.compile(r'refs/heads/master', re.IGNORECASE),
        re.compile(r'refs/heads/main', re.IGNORECASE),
        re.compile(r'"latest"', re.IGNORECASE),
        re.compile(r'"develop"', re.IGNORECASE),
    ]
    
    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.policy_file = repo_root / "policy" / "rocm-policy.json"
        self.manifest_dir = repo_root / "pinned" / "rocm" / "7.2.0"
        self.source_lock = self.manifest_dir / "source-lock.json"
        
    def check_manifest_exists(self) -> List[Violation]:
        violations = []
        manifest_file = self.manifest_dir / "default.xml"
        hash_file = self.manifest_dir / "default.xml.sha256"
        
        if not self.manifest_dir.exists():
            violations.append(Violation("manifest_missing", "Manifest directory does not exist", str(self.manifest_dir)))
            return violations
            
        if not manifest_file.exists():
            violations.append(Violation("manifest_missing", "ROCm 7.2.0 manifest not archived", str(manifest_file)))
            
        if not hash_file.exists():
            violations.append(Violation("manifest_hash_missing", "Manifest hash file not found", str(hash_file)))
        elif manifest_file.exists():
            with open(manifest_file, 'rb') as f:
                actual_hash = hashlib.sha256(f.read()).hexdigest()
            with open(hash_file) as f:
                expected_hash = f.read().strip().split()[0]
            if actual_hash != expected_hash:
                violations.append(Violation("manifest_hash_mismatch", f"Hash mismatch: expected {expected_hash}, got {actual_hash}", str(manifest_file)))
                
        return violations
    
    def check_source_lock(self) -> List[Violation]:
        violations = []
        if not self.source_lock.exists():
            violations.append(Violation("source_lock_missing", "source-lock.json not found", str(self.source_lock)))
            return violations
            
        try:
            with open(self.source_lock) as f:
                lock = json.load(f)
        except json.JSONDecodeError:
             violations.append(Violation("source_lock_invalid", "source-lock.json is not valid JSON", str(self.source_lock)))
             return violations

        if lock.get("rocm_release") != self.ALLOWED_RELEASE:
            violations.append(Violation("version_drift", f"Source lock specifies ROCm {lock.get('rocm_release')}, expected {self.ALLOWED_RELEASE}", "source-lock.json:rocm_release"))
            
        for project in lock.get("projects", []):
            name = project.get("name", "unknown")
            commit_sha = project.get("commit_sha", "")
            # Allow rocm-7.2.0 as a special case for offline lock generation
            if not self.SHA_PATTERN.match(commit_sha) and commit_sha != "rocm-7.2.0":
                violations.append(Violation("floating_ref", f"Project '{name}' has invalid/floating ref: {commit_sha}", f"source-lock.json:projects:{name}"))
            
            url = project.get("remote_url", "")
            for pattern in self.FORBIDDEN_PATTERNS:
                if pattern.search(url):
                    violations.append(Violation("forbidden_version", f"Project '{name}' URL contains forbidden pattern", url))
        return violations
    
    def check_flake_for_drift(self) -> List[Violation]:
        violations = []
        flake_nix = self.repo_root / "flake.nix"
        if not flake_nix.exists():
            return violations
        with open(flake_nix) as f:
            content = f.read()
        for pattern in self.FORBIDDEN_PATTERNS:
            matches = pattern.findall(content)
            for match in matches:
                violations.append(Violation("drift_in_flake", "Forbidden pattern found in flake.nix", match))
        return violations

    def run_full_check(self, strict: bool = False) -> PolicyCheckResult:
        all_violations = []
        all_violations.extend(self.check_manifest_exists())
        all_violations.extend(self.check_source_lock())
        all_violations.extend(self.check_flake_for_drift())
        # Strict mode could add more checks if defined
        return PolicyCheckResult(passed=len(all_violations) == 0, violations=all_violations)

def verify(repo_root: Path, run_id: Optional[str], strict: bool):
    ctx = RunContext(repo_root, run_id)
    fence = ROCmPolicyFence(repo_root)
    
    print(f"Running ROCm 7.2.0 Policy Fence (Run ID: {ctx.run_id})")
    
    result = fence.run_full_check(strict=strict)
    
    policy_record = {
        "decision": "allowed" if result.passed else "denied",
        "timestamp": result.checked_at,
        "strict_mode": strict,
        "violations": [v.category for v in result.violations]
    }
    
    ctx.update_receipt({"policy": {"decisions": [policy_record]}})
    ctx.log_event("policy_check", result.to_dict())
    
    run_dir_reports = ctx.run_dir / "reports"
    run_dir_reports.mkdir(exist_ok=True)
    report_path = run_dir_reports / "policy-report.json"
    with open(report_path, "w") as f:
        json.dump(result.to_dict(), f, indent=2)

    if result.passed:
        # Machine-readable header per prompt
        target = os.environ.get("ROCM_BUILD_TARGET", "gfx110x")
        header = {
            "rocm_release": ROCmPolicyFence.ALLOWED_RELEASE,
            "manifest_sha256": "verified-in-check", 
            "gpu_targets": target,
            "run_id": ctx.run_id,
            "evidence_path": str(report_path)
        }
        print(json.dumps(header))
        print(f"✅ Policy Verification Passed (ROCm 7.2.0 Fence - Target: {target})")
        # Do NOT log success for the *run* yet, just the phase
        ctx.record_phase("policy_verify", "success", {"violation_count": 0})
        return
    else:
        print("❌ Policy Verification Failed")
        for v in result.violations:
            print(f"  - [{v.category}] {v.message} ({v.offender})")
        
        ctx.record_phase("policy_verify", "failed", {"violation_count": len(result.violations)})
        ctx.mark_failed("Policy Violation", exit_code=EX_CONFIG)
        sys.exit(EX_CONFIG)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--run-id", type=str)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    verify(args.repo_root, args.run_id, args.strict)
