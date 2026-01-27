#!/usr/bin/env python3
"""
Topological Sort - Generate build order from graph

This tool:
1. Reads graph.json
2. Performs topological sort (Kahn's algorithm)
3. Groups nodes into parallelizable layers
4. Outputs order.json

Usage:
    python toposort.py --graph graph/graph.json --output graph/order.json
"""

import argparse
import json
import sys
from collections import defaultdict, deque
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Dict, Any, Set


@dataclass
class SerialConstraint:
    """Explicit serial ordering constraint"""
    before: str
    after: str
    reason: str
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class BuildOrder:
    """Build order with parallelizable layers"""
    version: str
    generated_at: str
    graph_sha256: str
    layers: List[List[str]]
    serial_constraints: List[SerialConstraint]
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "version": self.version,
            "generated_at": self.generated_at,
            "graph_sha256": self.graph_sha256,
            "layers": self.layers,
            "serial_constraints": [c.to_dict() for c in self.serial_constraints]
        }


class TopologicalSorter:
    """Topological sort with layer grouping"""
    
    def __init__(self, graph_path: Path):
        self.graph_path = graph_path
        self.graph = self._load_graph()
        
    def _load_graph(self) -> Dict[str, Any]:
        with open(self.graph_path) as f:
            return json.load(f)
            
    def sort(self) -> BuildOrder:
        """Perform topological sort and group into layers"""
        nodes = {n['id'] for n in self.graph.get('nodes', [])}
        
        # Build adjacency list and in-degree map
        # edges go from dependent -> dependency (from -> to means "from depends on to")
        # So for build order, we need to build 'to' before 'from'
        dependents: Dict[str, Set[str]] = defaultdict(set)  # dependency -> set of dependents
        dependencies: Dict[str, Set[str]] = defaultdict(set)  # dependent -> set of dependencies
        
        for edge in self.graph.get('edges', []):
            from_node = edge['from']  # dependent
            to_node = edge['to']  # dependency
            
            if from_node in nodes and to_node in nodes:
                dependents[to_node].add(from_node)
                dependencies[from_node].add(to_node)
                
        # Initialize in-degree (number of unbuilt dependencies)
        in_degree: Dict[str, int] = {n: len(dependencies[n]) for n in nodes}
        
        # Kahn's algorithm with layer tracking
        layers: List[List[str]] = []
        remaining = set(nodes)
        
        while remaining:
            # Find all nodes with no remaining dependencies
            layer = [n for n in remaining if in_degree[n] == 0]
            
            if not layer:
                # Cycle detected
                print(f"Warning: Cycle detected! Remaining: {remaining}", file=sys.stderr)
                # Add remaining as final layer (shouldn't happen with valid graph)
                layers.append(list(remaining))
                break
                
            # Sort for determinism
            layer.sort()
            layers.append(layer)
            
            # Remove this layer from graph
            for node in layer:
                remaining.remove(node)
                for dependent in dependents[node]:
                    in_degree[dependent] -= 1
                    
        # Generate serial constraints for large builds
        serial_constraints: List[SerialConstraint] = []
        
        # PyTorch must build after ROCm core
        if 'pytorch' in nodes and 'MIOpen' in nodes:
            serial_constraints.append(SerialConstraint(
                before="MIOpen",
                after="pytorch",
                reason="MIOpen must complete before PyTorch for kernel linking"
            ))
            
        return BuildOrder(
            version="1.0.0",
            generated_at=datetime.now(timezone.utc).isoformat(),
            graph_sha256=self.graph.get('source_lock_sha256', ''),
            layers=layers,
            serial_constraints=serial_constraints
        )


def main():
    parser = argparse.ArgumentParser(
        description="Generate build order from graph"
    )
    parser.add_argument(
        "--graph",
        type=Path,
        required=True,
        help="Path to graph.json"
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Output path for order.json"
    )
    parser.add_argument(
        "--run-id",
        help="Run ID for evidence tracking"
    )
    
    args = parser.parse_args()
    
    if not args.graph.exists():
        print(f"Error: Graph not found: {args.graph}", file=sys.stderr)
        sys.exit(1)
        
    sorter = TopologicalSorter(args.graph)
    order = sorter.sort()
    
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, 'w') as f:
        json.dump(order.to_dict(), f, indent=2)
        f.write('\n')
        
    print(f"Generated: {args.output}")
    print(f"  Layers: {len(order.layers)}")
    print(f"  Serial constraints: {len(order.serial_constraints)}")
    
    for i, layer in enumerate(order.layers):
        print(f"  Layer {i}: {len(layer)} nodes")
        
    # Emit event
    if args.run_id:
        event = {
            "event": "order_generated",
            "run_id": args.run_id,
            "timestamp": order.generated_at,
            "layer_count": len(order.layers)
        }
        print(json.dumps(event))


if __name__ == "__main__":
    main()
