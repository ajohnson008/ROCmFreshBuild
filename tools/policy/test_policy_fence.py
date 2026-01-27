#!/usr/bin/env python3
"""
Unit tests for ROCm 7.2.0 policy fence

Tests:
1. ROCm 6.x pin attempt fails
2. Floating ref fails  
3. Correct 7.2.0 manifest passes
"""

import json
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent))
from policy.policy_fence import ROCmPolicyFence, PolicyCheckResult, Violation


class TestPolicyFence(unittest.TestCase):
    """Test cases for ROCm policy fence"""
    
    def setUp(self):
        """Create temporary test directory structure"""
        self.test_dir = tempfile.mkdtemp()
        self.repo_root = Path(self.test_dir)
        
        # Create policy directory
        policy_dir = self.repo_root / "policy"
        policy_dir.mkdir(parents=True)
        
        # Create policy file
        policy = {
            "policy_version": "1.0.0",
            "policy_name": "rocm-7.2.0-only",
            "rocm": {
                "allowed_release": "7.2.0"
            }
        }
        with open(policy_dir / "rocm-policy.json", "w") as f:
            json.dump(policy, f)
            
    def create_manifest_structure(self, release: str = "7.2.0"):
        """Helper to create manifest directory structure"""
        manifest_dir = self.repo_root / "pinned" / "rocm" / release
        manifest_dir.mkdir(parents=True, exist_ok=True)
        
        # Create default.xml
        manifest_content = f'<?xml version="1.0"?><manifest><remote name="rocm"/></manifest>'
        manifest_file = manifest_dir / "default.xml"
        with open(manifest_file, "w") as f:
            f.write(manifest_content)
            
        # Create hash file
        import hashlib
        manifest_hash = hashlib.sha256(manifest_content.encode()).hexdigest()
        with open(manifest_dir / "default.xml.sha256", "w") as f:
            f.write(manifest_hash)
            
        return manifest_dir
        
    def create_source_lock(self, manifest_dir: Path, rocm_release: str, projects: list):
        """Helper to create source-lock.json"""
        lock = {
            "rocm_release": rocm_release,
            "manifest_sha256": "abc123",
            "generated_at": "2026-01-26T00:00:00Z",
            "projects": projects
        }
        with open(manifest_dir / "source-lock.json", "w") as f:
            json.dump(lock, f)
    
    def test_rocm_6x_fails(self):
        """Test that ROCm 6.x pin attempt fails"""
        manifest_dir = self.create_manifest_structure("7.2.0")
        
        # Create source lock with 6.x reference
        self.create_source_lock(manifest_dir, "6.2.0", [
            {
                "name": "rocm-cmake",
                "remote_url": "https://github.com/ROCm/rocm-cmake",
                "commit_sha": "abc123"  # Invalid - not 40 hex chars
            }
        ])
        
        fence = ROCmPolicyFence(self.repo_root)
        result = fence.run_full_check()
        
        self.assertFalse(result.passed)
        
        # Should have version drift violation
        version_violations = [v for v in result.violations if v.category == "version_drift"]
        self.assertGreater(len(version_violations), 0)
        
    def test_floating_ref_fails(self):
        """Test that floating refs (non-SHA) fail"""
        manifest_dir = self.create_manifest_structure("7.2.0")
        
        # Create source lock with floating ref
        self.create_source_lock(manifest_dir, "7.2.0", [
            {
                "name": "rocm-cmake",
                "remote_url": "https://github.com/ROCm/rocm-cmake",
                "commit_sha": "rocm-7.2.0"  # Tag, not SHA!
            }
        ])
        
        fence = ROCmPolicyFence(self.repo_root)
        result = fence.run_full_check()
        
        self.assertFalse(result.passed)
        
        # Should have floating ref violation
        float_violations = [v for v in result.violations if v.category == "floating_ref"]
        self.assertGreater(len(float_violations), 0)
        
    def test_correct_720_passes(self):
        """Test that correct 7.2.0 manifest with valid SHAs passes"""
        manifest_dir = self.create_manifest_structure("7.2.0")
        
        # Create valid source lock
        self.create_source_lock(manifest_dir, "7.2.0", [
            {
                "name": "rocm-cmake",
                "remote_url": "https://github.com/ROCm/rocm-cmake",
                "commit_sha": "f2657238cb71df839c97807d5b0cb2c184075227"  # Valid 40-char hex
            },
            {
                "name": "ROCR-Runtime",
                "remote_url": "https://github.com/ROCm/ROCR-Runtime",
                "commit_sha": "51e6956eb97475f6139c6cf88b51fbebea4c987b"  # Valid 40-char hex
            }
        ])
        
        fence = ROCmPolicyFence(self.repo_root)
        result = fence.run_full_check()
        
        self.assertTrue(result.passed, f"Expected pass but got violations: {[v.message for v in result.violations]}")
        
    def test_missing_manifest_fails(self):
        """Test that missing manifest directory fails"""
        # Don't create manifest structure
        fence = ROCmPolicyFence(self.repo_root)
        result = fence.run_full_check()
        
        self.assertFalse(result.passed)
        
        # Should have manifest missing violation
        missing_violations = [v for v in result.violations if v.category == "manifest_missing"]
        self.assertGreater(len(missing_violations), 0)
        
    def test_forbidden_url_pattern_fails(self):
        """Test that forbidden URL patterns fail"""
        manifest_dir = self.create_manifest_structure("7.2.0")
        
        # Create source lock with forbidden URL pattern
        self.create_source_lock(manifest_dir, "7.2.0", [
            {
                "name": "bad-project",
                "remote_url": "https://github.com/ROCm/rocm-cmake/tree/rocm-6.2",
                "commit_sha": "f2657238cb71df839c97807d5b0cb2c184075227"
            }
        ])
        
        fence = ROCmPolicyFence(self.repo_root)
        result = fence.run_full_check()
        
        self.assertFalse(result.passed)


class TestViolationDataclass(unittest.TestCase):
    """Test Violation dataclass"""
    
    def test_violation_creation(self):
        v = Violation(
            category="test",
            message="Test message",
            offender="test_file.txt"
        )
        self.assertEqual(v.category, "test")
        self.assertEqual(v.severity, "error")  # default


class TestPolicyCheckResult(unittest.TestCase):
    """Test PolicyCheckResult dataclass"""
    
    def test_to_dict(self):
        result = PolicyCheckResult(
            passed=False,
            violations=[
                Violation(category="test", message="msg", offender="off")
            ]
        )
        d = result.to_dict()
        self.assertFalse(d["passed"])
        self.assertEqual(d["violation_count"], 1)
        self.assertIn("checked_at", d)


if __name__ == "__main__":
    unittest.main()
