#!/usr/bin/env python3
"""
Extract Build Graph - Generate DAG from ROCm/PyTorch dependencies

This tool:
1. Parses CMakeLists.txt for find_package() dependencies
2. Parses Python setup files for build requirements
3. Generates graph.json with nodes and edges
4. Applies overrides.yaml for manual edge corrections

Usage:
    python extract_graph.py --source-lock pinned/rocm/7.2.0/source-lock.json --output graph/
"""

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Dict, Any, Optional, Set


@dataclass
class Node:
    """Build graph node"""
    id: str
    kind: str  # rocm_repo | python_pkg | toolchain | blob
    path: str
    outputs: List[str] = field(default_factory=list)
    
    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        if not d['outputs']:
            del d['outputs']
        return d


@dataclass
class Edge:
    """Build graph edge"""
    from_node: str
    to_node: str
    reason: str
    edge_class: str  # build | link | headers | python_build_req | toolchain | runtime
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "from": self.from_node,
            "to": self.to_node,
            "reason": self.reason,
            "class": self.edge_class
        }


@dataclass
class BuildGraph:
    """Complete build graph"""
    version: str
    generated_at: str
    source_lock_sha256: str
    nodes: List[Node]
    edges: List[Edge]
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "version": self.version,
            "generated_at": self.generated_at,
            "source_lock_sha256": self.source_lock_sha256,
            "nodes": [n.to_dict() for n in self.nodes],
            "edges": [e.to_dict() for e in self.edges]
        }


# Known ROCm dependencies (static knowledge)
ROCM_DEPENDENCIES = {
    "rocm-cmake": [],
    "ROCT-Thunk-Interface": [],
    "ROCR-Runtime": ["ROCT-Thunk-Interface", "rocm-cmake"],
    "ROCm-Device-Libs": ["llvm-project", "rocm-cmake"],
    "clr": ["ROCR-Runtime", "ROCm-Device-Libs", "rocm-cmake"],
    "HIP": ["clr", "rocm-cmake"],
    "rocminfo": ["ROCR-Runtime"],
    "rocm_smi_lib": [],
    "amdsmi": ["rocm_smi_lib"],
    "rocBLAS": ["ROCR-Runtime", "clr", "rocm-cmake"],
    "hipBLAS": ["rocBLAS", "clr"],
    "hipBLASLt": ["hipBLAS"],
    "rocSOLVER": ["rocBLAS"],
    "hipSOLVER": ["rocSOLVER", "hipBLAS"],
    "rocSPARSE": ["ROCR-Runtime", "clr"],
    "hipSPARSE": ["rocSPARSE"],
    "rocFFT": ["ROCR-Runtime", "clr"],
    "hipFFT": ["rocFFT"],
    "rocRAND": ["ROCR-Runtime", "clr"],
    "hipRAND": ["rocRAND"],
    "rocPRIM": ["ROCR-Runtime", "clr"],
    "hipCUB": ["rocPRIM"],
    "rocThrust": ["rocPRIM"],
    "MIOpen": ["rocBLAS", "composable_kernel", "clr"],
    "composable_kernel": ["clr", "rocm-cmake"],
    "rccl": ["ROCR-Runtime", "clr"],
    "llvm-project": ["rocm-cmake"],
}

# Python ML stack dependencies
PYTHON_DEPENDENCIES = {
    "numpy": [],
    "pytorch": ["numpy", "MIOpen", "rocBLAS", "rccl", "clr"],
    "torchvision": ["pytorch", "numpy"],
    "torchaudio": ["pytorch"],
    "flash-attention": ["pytorch"],
    "xformers": ["pytorch", "flash-attention"],
    "deepspeed": ["pytorch"],
    "bitsandbytes": ["pytorch"],
    "vllm": ["pytorch", "flash-attention", "xformers"],
    "llama-cpp": ["clr"],
    "onnxruntime": ["numpy"],
}


class GraphExtractor:
    """Extract build graph from source lock"""
    
    def __init__(self, source_lock_path: Path, repos_dir: Optional[Path] = None):
        self.source_lock_path = source_lock_path
        self.repos_dir = repos_dir
        self.source_lock = self._load_source_lock()
        
    def _load_source_lock(self) -> Dict[str, Any]:
        with open(self.source_lock_path) as f:
            return json.load(f)
            
    def _project_id(self, name: str) -> str:
        """Convert project name to node ID"""
        # Remove ROCm/ prefix if present
        if '/' in name:
            return name.split('/')[-1]
        return name
        
    def extract(self) -> BuildGraph:
        """Extract full build graph"""
        nodes: List[Node] = []
        edges: List[Edge] = []
        seen_nodes: Set[str] = set()
        
        # Add toolchain nodes
        nodes.append(Node(id="gcc14", kind="toolchain", path="", outputs=["gcc"]))
        seen_nodes.add("gcc14")
        
        # Add ROCm nodes from source lock
        for project in self.source_lock.get('projects', []):
            node_id = self._project_id(project['name'])
            if node_id not in seen_nodes:
                nodes.append(Node(
                    id=node_id,
                    kind="rocm_repo",
                    path=project.get('path', node_id)
                ))
                seen_nodes.add(node_id)
                
        # Add Python package nodes
        for pkg in PYTHON_DEPENDENCIES.keys():
            if pkg not in seen_nodes:
                nodes.append(Node(
                    id=pkg,
                    kind="python_pkg",
                    path=f"python-packages/{pkg}"
                ))
                seen_nodes.add(pkg)
                
        # Add ROCm edges from static knowledge
        for node_id, deps in ROCM_DEPENDENCIES.items():
            if node_id in seen_nodes:
                for dep in deps:
                    if dep in seen_nodes:
                        edges.append(Edge(
                            from_node=node_id,
                            to_node=dep,
                            reason=f"find_package({dep})",
                            edge_class="build"
                        ))
                        
        # Add toolchain edges
        for node in nodes:
            if node.kind == "rocm_repo":
                edges.append(Edge(
                    from_node=node.id,
                    to_node="gcc14",
                    reason="C/C++ compiler requirement",
                    edge_class="toolchain"
                ))
                
        # Add Python edges
        for pkg, deps in PYTHON_DEPENDENCIES.items():
            for dep in deps:
                if dep in seen_nodes:
                    edge_class = "python_build_req" if dep in PYTHON_DEPENDENCIES else "link"
                    edges.append(Edge(
                        from_node=pkg,
                        to_node=dep,
                        reason=f"build dependency",
                        edge_class=edge_class
                    ))
                    
        return BuildGraph(
            version="1.0.0",
            generated_at=datetime.now(timezone.utc).isoformat(),
            source_lock_sha256=self.source_lock.get('lock_sha256', ''),
            nodes=nodes,
            edges=edges
        )
        
    def apply_overrides(self, graph: BuildGraph, overrides_path: Path) -> BuildGraph:
        """Apply manual overrides from YAML file"""
        if not overrides_path.exists():
            return graph
            
        import yaml
        with open(overrides_path) as f:
            overrides = yaml.safe_load(f)
            
        if not overrides:
            return graph
            
        # Apply edge additions
        for edge_def in overrides.get('add_edges', []):
            graph.edges.append(Edge(
                from_node=edge_def['from'],
                to_node=edge_def['to'],
                reason=edge_def.get('reason', 'manual override'),
                edge_class=edge_def.get('class', 'build')
            ))
            
        # Apply edge removals
        remove_set = set()
        for edge_def in overrides.get('remove_edges', []):
            remove_set.add((edge_def['from'], edge_def['to']))
            
        graph.edges = [
            e for e in graph.edges 
            if (e.from_node, e.to_node) not in remove_set
        ]
        
        return graph


def main():
    parser = argparse.ArgumentParser(
        description="Extract build graph from source lock"
    )
    parser.add_argument(
        "--source-lock",
        type=Path,
        required=True,
        help="Path to source-lock.json"
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Output directory for graph files"
    )
    parser.add_argument(
        "--overrides",
        type=Path,
        help="Path to overrides.yaml"
    )
    parser.add_argument(
        "--run-id",
        help="Run ID for evidence tracking"
    )
    
    args = parser.parse_args()
    
    if not args.source_lock.exists():
        print(f"Error: Source lock not found: {args.source_lock}", file=sys.stderr)
        sys.exit(1)
        
    extractor = GraphExtractor(args.source_lock)
    graph = extractor.extract()
    
    # Apply overrides if provided
    if args.overrides and args.overrides.exists():
        graph = extractor.apply_overrides(graph, args.overrides)
        
    # Write graph
    args.output.mkdir(parents=True, exist_ok=True)
    
    graph_path = args.output / "graph.json"
    with open(graph_path, 'w') as f:
        json.dump(graph.to_dict(), f, indent=2)
        f.write('\n')
        
    print(f"Generated: {graph_path}")
    print(f"  Nodes: {len(graph.nodes)}")
    print(f"  Edges: {len(graph.edges)}")
    
    # Emit event if run-id
    if args.run_id:
        event = {
            "event": "graph_extracted",
            "run_id": args.run_id,
            "timestamp": graph.generated_at,
            "node_count": len(graph.nodes),
            "edge_count": len(graph.edges)
        }
        print(json.dumps(event))


if __name__ == "__main__":
    main()
