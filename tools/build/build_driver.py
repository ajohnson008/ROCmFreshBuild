#!/usr/bin/env python3.11
"""
Build Driver - Pass A orchestrator

This driver:
1. Reads order.json for build sequence
2. Executes builds per-layer with parallelism config
3. Records all events to run directory
4. Produces receipt on completion or failure

Usage:
    python build_driver.py --order graph/order.json --run-id <run-id>
"""

import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Dict, Any, Optional, Tuple

# Import run manager
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "lib"))
from run_manager import RunManager


# Nix attribute mapping for known packages
NIX_ATTRS = {
    # Toolchain
    "gcc14": ".#gcc14",
    
    # ROCm Core
    "rocm-cmake": ".#rocm-cmake",
    "ROCR-Runtime": ".#rocm-runtime",
    "clr": ".#clr",
    "rocm-core": ".#rocm-core",
    
    # Python packages
    "numpy": ".#numpy",
    "pytorch": ".#pytorch-rocm",
    "torchvision": ".#torchvision",
    "torchaudio": ".#torchaudio",
    "flash-attention": ".#flash-attention",
    "xformers": ".#xformers",
    "deepspeed": ".#deepspeed",
    "bitsandbytes": ".#bitsandbytes",
    "vllm": ".#vllm",
    "llama-cpp": ".#llamacpp-gpu",
    "onnxruntime": ".#onnxruntime",
}


@dataclass
class BuildResult:
    """Result of building a single component"""
    node_id: str
    success: bool
    output_path: Optional[str]
    duration_seconds: float
    error: Optional[str] = None


class BuildDriver:
    """Pass A build orchestrator"""
    
    def __init__(
        self,
        repo_root: Path,
        order_path: Path,
        run_manager: RunManager,
        max_parallel: int = 1,
        dry_run: bool = False
    ):
        self.repo_root = repo_root
        self.order_path = order_path
        self.run_manager = run_manager
        self.max_parallel = max_parallel
        self.dry_run = dry_run
        self.order = self._load_order()
        
    def _load_order(self) -> Dict[str, Any]:
        with open(self.order_path) as f:
            return json.load(f)
            
    def _get_nix_attr(self, node_id: str) -> Optional[str]:
        """Get Nix attribute for a node"""
        return NIX_ATTRS.get(node_id)
        
    def _build_node(self, node_id: str) -> BuildResult:
        """Build a single node"""
        started = datetime.now(timezone.utc)
        
        nix_attr = self._get_nix_attr(node_id)
        
        if not nix_attr:
            # Node has no Nix attribute (may be built differently)
            return BuildResult(
                node_id=node_id,
                success=True,
                output_path=None,
                duration_seconds=0.0,
                error=f"No Nix attribute for {node_id} (skipped)"
            )
            
        if self.dry_run:
            return BuildResult(
                node_id=node_id,
                success=True,
                output_path=f"/nix/store/dry-run-{node_id}",
                duration_seconds=0.1
            )
            
        try:
            # Build with Nix
            result = subprocess.run(
                ['nix', 'build', nix_attr, '--print-out-paths'],
                capture_output=True,
                text=True,
                cwd=self.repo_root,
                timeout=14400  # 4 hour timeout
            )
            
            ended = datetime.now(timezone.utc)
            duration = (ended - started).total_seconds()
            
            if result.returncode == 0:
                output_path = result.stdout.strip().split('\n')[0] if result.stdout else None
                return BuildResult(
                    node_id=node_id,
                    success=True,
                    output_path=output_path,
                    duration_seconds=duration
                )
            else:
                return BuildResult(
                    node_id=node_id,
                    success=False,
                    output_path=None,
                    duration_seconds=duration,
                    error=result.stderr[:2000] if result.stderr else "Build failed"
                )
                
        except subprocess.TimeoutExpired:
            ended = datetime.now(timezone.utc)
            return BuildResult(
                node_id=node_id,
                success=False,
                output_path=None,
                duration_seconds=(ended - started).total_seconds(),
                error="Build timeout (4 hours)"
            )
        except Exception as e:
            ended = datetime.now(timezone.utc)
            return BuildResult(
                node_id=node_id,
                success=False,
                output_path=None,
                duration_seconds=(ended - started).total_seconds(),
                error=str(e)[:2000]
            )
            
    def _build_layer(self, layer_idx: int, nodes: List[str]) -> List[BuildResult]:
        """Build all nodes in a layer (potentially in parallel)"""
        results = []
        
        # Filter to nodes with Nix attrs
        buildable = [n for n in nodes if self._get_nix_attr(n)]
        skipped = [n for n in nodes if not self._get_nix_attr(n)]
        
        # Add skipped results
        for node_id in skipped:
            results.append(BuildResult(
                node_id=node_id,
                success=True,
                output_path=None,
                duration_seconds=0.0,
                error=f"Skipped (no Nix attr)"
            ))
            
        if not buildable:
            return results
            
        # Build with bounded parallelism
        # Note: For large builds, parallel=1 is safer for memory
        with ThreadPoolExecutor(max_workers=min(self.max_parallel, len(buildable))) as executor:
            futures = {
                executor.submit(self._build_node, node_id): node_id
                for node_id in buildable
            }
            
            for future in as_completed(futures):
                result = future.result()
                results.append(result)
                
                symbol = "✅" if result.success else "❌"
                print(f"    {symbol} {result.node_id} ({result.duration_seconds:.1f}s)")
                
                # Emit event
                self.run_manager.emit_event("component_build", {
                    "node_id": result.node_id,
                    "success": result.success,
                    "output_path": result.output_path,
                    "duration_seconds": result.duration_seconds,
                    "error": result.error
                })
                
        return results
        
    def run(self) -> Tuple[bool, List[BuildResult]]:
        """Execute full build sequence"""
        all_results: List[BuildResult] = []
        
        layers = self.order.get('layers', [])
        
        print(f"Build Driver - Pass A")
        print(f"  Layers: {len(layers)}")
        print(f"  GPU target: gfx1151")
        print(f"  Parallel: {self.max_parallel}")
        print()
        
        self.run_manager.start_phase("build")
        
        for layer_idx, layer in enumerate(layers):
            print(f"Layer {layer_idx}: {len(layer)} nodes")
            
            self.run_manager.emit_event("layer_start", {
                "layer_idx": layer_idx,
                "nodes": layer
            })
            
            results = self._build_layer(layer_idx, layer)
            all_results.extend(results)
            
            # Check for failures
            failures = [r for r in results if not r.success and r.error and "Skipped" not in r.error]
            
            if failures:
                print(f"\n❌ Layer {layer_idx} failed!")
                for f in failures:
                    print(f"   {f.node_id}: {f.error[:100]}")
                    
                self.run_manager.end_phase("build", status="failed", 
                    error=f"Layer {layer_idx} failed: {failures[0].node_id}")
                    
                return False, all_results
                
            self.run_manager.emit_event("layer_end", {
                "layer_idx": layer_idx,
                "success": True
            })
            
        self.run_manager.end_phase("build", status="success")
        
        # Add outputs to run manager
        for result in all_results:
            if result.output_path:
                self.run_manager.add_output(
                    name=result.node_id,
                    path_or_store_ref=result.output_path,
                    sha256=""  # Would compute if needed
                )
                
        return True, all_results


def main():
    parser = argparse.ArgumentParser(
        description="Build Driver - Pass A orchestrator"
    )
    parser.add_argument(
        "--order",
        type=Path,
        required=True,
        help="Path to order.json"
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path.cwd(),
        help="Repository root"
    )
    parser.add_argument(
        "--run-id",
        help="Existing run ID (creates new if not provided)"
    )
    parser.add_argument(
        "--parallel",
        type=int,
        default=1,
        help="Max parallel builds per layer"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Don't actually build"
    )
    
    args = parser.parse_args()
    
    if not args.order.exists():
        print(f"Error: Order file not found: {args.order}", file=sys.stderr)
        sys.exit(1)
        
    # Initialize run manager
    run_mgr = RunManager(args.repo_root, run_id=args.run_id)
    if not args.run_id:
        args.run_id = run_mgr.create_run()
        print(f"Created run: {args.run_id}")
    else:
        run_mgr.run_dir = run_mgr.runs_dir / args.run_id
        run_mgr.started_at = datetime.now(timezone.utc).isoformat()
        
    # Run build
    driver = BuildDriver(
        repo_root=args.repo_root,
        order_path=args.order,
        run_manager=run_mgr,
        max_parallel=args.parallel,
        dry_run=args.dry_run
    )
    
    success, results = driver.run()
    
    # Finalize
    run_mgr.finalize(
        status="success" if success else "failed",
        manifest_sha256="",  # Would load from source-lock
        source_lock_sha256="",
        flake_lock_sha256=""
    )
    
    print()
    print(f"Build {'succeeded' if success else 'failed'}")
    print(f"Run ID: {args.run_id}")
    print(f"Receipt: {run_mgr.run_dir / 'receipt.json'}")
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
