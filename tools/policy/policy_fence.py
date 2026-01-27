#!/usr/bin/env python3
"""
ROCm 7.2.0 Policy Fence - Hard-fail gate for version drift

This module enforces the ROCm 7.2.0 only policy by:
1. Validating manifest existence and hash
2. Checking all source pins are full commit SHAs
3. Rejecting any ROCm 6.x references
4. Rejecting floating refs (branches, tags without SHA)

Exit codes:
  0 - Policy check passed
  78 - Policy violation (EX_CONFIG from sysexits.h)
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

# Policy exit code (EX_CONFIG)
EXIT_POLICY_VIOLATION = 78

@dataclass
class Violation:
    """Represents a policy violation"""
    category: str
    message: str
    offender: str
    severity: str = "error"

@dataclass
class PolicyCheckResult:
    """Result of policy fence check"""
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
    """Enforces ROCm 7.2.0 only policy"""
    
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
        
    def load_policy(self) -> Dict[str, Any]:
        """Load policy configuration"""
        if not self.policy_file.exists():
            raise FileNotFoundError(f"Policy file not found: {self.policy_file}")
        with open(self.policy_file) as f:
            return json.load(f)
    
    def check_manifest_exists(self) -> List[Violation]:
        """Check that manifest files exist and are hashed"""
        violations = []
        
        manifest_file = self.manifest_dir / "default.xml"
        hash_file = self.manifest_dir / "default.xml.sha256"
        
        if not self.manifest_dir.exists():
            violations.append(Violation(
                category="manifest_missing",
                message=f"Manifest directory does not exist",
                offender=str(self.manifest_dir)
            ))
            return violations
            
        if not manifest_file.exists():
            violations.append(Violation(
                category="manifest_missing",
                message="ROCm 7.2.0 manifest not archived",
                offender=str(manifest_file)
            ))
            
        if not hash_file.exists():
            violations.append(Violation(
                category="manifest_hash_missing",
                message="Manifest hash file not found",
                offender=str(hash_file)
            ))
        elif manifest_file.exists():
            # Verify hash matches
            with open(manifest_file, 'rb') as f:
                actual_hash = hashlib.sha256(f.read()).hexdigest()
            with open(hash_file) as f:
                expected_hash = f.read().strip().split()[0]
            if actual_hash != expected_hash:
                violations.append(Violation(
                    category="manifest_hash_mismatch",
                    message=f"Manifest hash mismatch: expected {expected_hash[:16]}..., got {actual_hash[:16]}...",
                    offender=str(manifest_file)
                ))
                
        return violations
    
    def check_source_lock(self) -> List[Violation]:
        """Check source-lock.json for policy compliance"""
        violations = []
        
        if not self.source_lock.exists():
            violations.append(Violation(
                category="source_lock_missing",
                message="source-lock.json not found",
                offender=str(self.source_lock)
            ))
            return violations
            
        with open(self.source_lock) as f:
            lock = json.load(f)
            
        # Check ROCm release
        if lock.get("rocm_release") != self.ALLOWED_RELEASE:
            violations.append(Violation(
                category="version_drift",
                message=f"Source lock specifies ROCm {lock.get('rocm_release')}, expected {self.ALLOWED_RELEASE}",
                offender="source-lock.json:rocm_release"
            ))
            
        # Check all projects have valid commit SHAs
        for project in lock.get("projects", []):
            name = project.get("name", "unknown")
            commit_sha = project.get("commit_sha", "")
            
            # Check for valid SHA
            if not self.SHA_PATTERN.match(commit_sha):
                violations.append(Violation(
                    category="floating_ref",
                    message=f"Project '{name}' has invalid/floating ref: {commit_sha[:20] if commit_sha else 'empty'}",
                    offender=f"source-lock.json:projects:{name}"
                ))
                
            # Check for forbidden patterns in URL
            url = project.get("remote_url", "")
            for pattern in self.FORBIDDEN_PATTERNS:
                if pattern.search(url):
                    violations.append(Violation(
                        category="forbidden_version",
                        message=f"Project '{name}' URL contains forbidden pattern",
                        offender=url
                    ))
                    
        return violations
    
    def check_flake_for_drift(self) -> List[Violation]:
        """Scan flake.nix for ROCm version drift"""
        violations = []
        flake_nix = self.repo_root / "flake.nix"
        
        if not flake_nix.exists():
            return violations
            
        with open(flake_nix) as f:
            content = f.read()
            
        for pattern in self.FORBIDDEN_PATTERNS:
            matches = pattern.findall(content)
            for match in matches:
                violations.append(Violation(
                    category="drift_in_flake",
                    message=f"Forbidden pattern found in flake.nix",
                    offender=match
                ))
                
        return violations
    
    def check_gpu_target(self) -> List[Violation]:
        """Verify GPU target is gfx1151 only for Pass A"""
        violations = []
        
        # Check environment
        targets = os.environ.get("AMDGPU_TARGETS", "")
        if targets and targets != "gfx1151":
            violations.append(Violation(
                category="gpu_target_violation",
                message=f"AMDGPU_TARGETS must be 'gfx1151' for Pass A, got '{targets}'",
                offender="AMDGPU_TARGETS"
            ))
            
        return violations
    
    def run_full_check(self) -> PolicyCheckResult:
        """Run complete policy fence check"""
        all_violations = []
        warnings = []
        
        # Check manifest
        all_violations.extend(self.check_manifest_exists())
        
        # Check source lock
        all_violations.extend(self.check_source_lock())
        
        # Check flake for drift
        all_violations.extend(self.check_flake_for_drift())
        
        # Check GPU target
        all_violations.extend(self.check_gpu_target())
        
        passed = len(all_violations) == 0
        
        return PolicyCheckResult(
            passed=passed,
            violations=all_violations,
            warnings=warnings
        )


def main():
    """CLI entrypoint for policy fence"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="ROCm 7.2.0 Policy Fence - Hard-fail gate for version drift"
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path.cwd(),
        help="Repository root directory"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON"
    )
    parser.add_argument(
        "--run-id",
        type=str,
        help="Run ID for evidence tracking"
    )
    
    args = parser.parse_args()
    
    fence = ROCmPolicyFence(args.repo_root)
    
    try:
        result = fence.run_full_check()
    except FileNotFoundError as e:
        result = PolicyCheckResult(
            passed=False,
            violations=[Violation(
                category="setup_error",
                message=str(e),
                offender=str(args.repo_root)
            )]
        )
    
    if args.json:
        print(json.dumps(result.to_dict(), indent=2))
    else:
        print("=" * 60)
        print("ROCm 7.2.0 Policy Fence Check")
        print("=" * 60)
        print(f"Repository: {args.repo_root}")
        print(f"Checked at: {result.checked_at}")
        print(f"Allowed release: {ROCmPolicyFence.ALLOWED_RELEASE}")
        print(f"GPU target: gfx1151 (Pass A)")
        print()
        
        if result.passed:
            print("✅ POLICY CHECK PASSED")
        else:
            print("❌ POLICY CHECK FAILED")
            print()
            print(f"Violations ({len(result.violations)}):")
            for v in result.violations:
                print(f"  [{v.category}] {v.message}")
                print(f"    Offender: {v.offender}")
                print()
                
    # Write to run directory if run-id provided
    if args.run_id:
        run_dir = args.repo_root / "runs" / args.run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        with open(run_dir / "policy-check.json", "w") as f:
            json.dump(result.to_dict(), f, indent=2)
    
    sys.exit(0 if result.passed else EXIT_POLICY_VIOLATION)


if __name__ == "__main__":
    main()
