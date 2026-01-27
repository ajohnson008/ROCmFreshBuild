
import subprocess
import json
import sys
import hashlib
from pathlib import Path
from io import StringIO

# Add parent to path
sys.path.append(str(Path(__file__).parent.parent))
from tools.lib.common import RunContext
from tools import env_manager

def run_proof(repo_root: Path, run_id: str, scope: str = "all"):
    ctx = RunContext(repo_root, run_id)
    
    # 1. Check Prereqs
    if "policy_verify" not in ctx.receipt.get("phases", {}) or \
       ctx.receipt["phases"]["policy_verify"]["status"] != "success":
        print("❌ Error: Policy verify must pass before offline proof.")
        sys.exit(1)
        
    print(f"Starting Offline Proof (Run ID: {run_id})")
    
    # 2. Get Offline Options
    nix_flags = env_manager.handle_nix_opts("mirror-only")
    nix_flags_str = " ".join(nix_flags)
    
    # 3. Execute Proof (Nix Eval)
    # We evaluate the graph of the 'ai-stack' or 'rocm-core' to prove we can build the graph offline.
    # Using 'rocm-core' as a representative target.
    target_attr = ".#packages.x86_64-linux.rocm-core"
    
    proof_cmd = ["nix", "eval", "--raw", target_attr + ".drvPath"] + nix_flags
    
    proof_record = {
        "command": proof_cmd,
        "nix_options": nix_flags_str,
        "scope": scope,
        "targets": [target_attr],
        "executed_at": ctx.receipt["start_time"]
    }
    
    try:
        # Run the command with restricted network
        result = subprocess.run(proof_cmd, cwd=repo_root, capture_output=True, text=True)
        
        if result.returncode != 0:
            offenders = []
            if "restricted mode" in result.stderr:
                # Try to parse blocked URI
                 import re
                 uri_match = re.search(r"access to URI '([^']+)' is forbidden", result.stderr)
                 if uri_match:
                     offenders.append(uri_match.group(1))
            
            proof_record["offender_uris"] = offenders
            raise Exception(f"Nix eval failed: {result.stderr}")
            
        # Success
        drv_path = result.stdout.strip()
        proof_record["status"] = "passed"
        proof_record["drv_path"] = drv_path
        
        # Calculate proof hash (hash of validation inputs + result)
        proof_content = json.dumps(proof_record, sort_keys=True)
        proof_hash = hashlib.sha256(proof_content.encode()).hexdigest()
        proof_record["proof_hash"] = proof_hash
        
        # Write report
        report_path = ctx.run_dir / "reports" / "offline-proof.json"
        
        # Ensure reports dir exists (common does it, but double check)
        report_path.parent.mkdir(exist_ok=True)
        
        with open(report_path, "w") as f:
            json.dump(proof_record, f, indent=2)
            
        ctx.record_phase("offline_proof", "success", {"report_path": str(report_path), "proof_hash": proof_hash})
        ctx.update_receipt({"offline_proof_hash": proof_hash})
        print(f"✅ Offline Proof Passed (Derivation: {drv_path})")
        print(f"   Proof Hash: {proof_hash}")
        
    except Exception as e:
        proof_record["status"] = "failed"
        proof_record["error"] = str(e)
        
        report_path = ctx.run_dir / "reports" / "offline-proof.json"
        report_path.parent.mkdir(exist_ok=True)
        with open(report_path, "w") as f:
            json.dump(proof_record, f, indent=2)
            
        ctx.record_phase("offline_proof", "failed", {"error": str(e)})
        print(f"❌ Offline Proof Failed: {e}")
        sys.exit(1)
