# Graph Extraction (graph-extraction) 🧭

Commands

```bash
python tools/graph/extract_graph.py --source-lock pinned/rocm/7.2.0/source-lock.json --output graph/ --overrides graph/overrides.yaml --run-id $RUN_ID
python tools/graph/toposort.py --graph graph/graph.json --output graph/order.json
```

Evidence

- `graph/graph.json`
- `graph/order.json`

Success Criteria

- `graph/graph.json` contains nodes and edges; `order.json` contains `layers` suitable for build.

Failure Actions

- If graph is incomplete, check `graph/overrides.yaml` and `agent_playbooks/stories/graph-incomplete.json`.
- Re-run extraction after fixes.

Quick commands

- `jq . graph/graph.json | jq '.nodes | length'`
- `jq . graph/order.json | head -n 200`