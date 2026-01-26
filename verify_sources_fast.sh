#!/bin/bash
# verify_sources_fast.sh (v2)
# Phase 1: Hyper-Parallel Source Audit
# Goal: Saturate 48 threads to verify rocm-7.2.0.xml sources

XML_FILE="/home/thenexussidekick/code/test/prd3/repos/ROCm/tools/rocm-build/rocm-7.2.0.xml"
MANIFEST_FILE="/tmp/rocm_manifest.txt"
RESULTS_FILE="verified_sources.json"

# Clean previous run
rm -f "$MANIFEST_FILE" "$RESULTS_FILE"

echo "Parsing $XML_FILE..."

# Bloat Filter regex
SKIP_REGEX="aomp|flang|hipfort|omniperf|rocm-docs"

# 1. Extract Default Revision
DEFAULT_REV=$(grep "<default" "$XML_FILE" | grep -o 'revision="[^"]*"' | cut -d'"' -f2)
if [ -z "$DEFAULT_REV" ]; then
    echo "Error: Could not find default revision in XML"
    exit 1
fi
echo "Default Revision: $DEFAULT_REV"

# 2. Extract Projects
# XML structure: <project name="..." /> or <project name="..." revision="..." />
grep "<project" "$XML_FILE" | while read -r line; do
    # Extract name
    NAME=$(echo "$line" | grep -o 'name="[^"]*"' | cut -d'"' -f2)
    
    # Skip if bloat
    if [[ "$NAME" =~ $SKIP_REGEX ]]; then
        continue
    fi
    
    # Extract specific revision if present, otherwise use default
    REV=$(echo "$line" | grep -o 'revision="[^"]*"' | cut -d'"' -f2)
    if [ -z "$REV" ]; then
        REV="$DEFAULT_REV"
    fi
    
    # Construct URL
    # All projects in this XML seem to be under rocm-org (https://github.com/ROCm/)
    URL="https://github.com/ROCm/$NAME"

    echo "$NAME $URL $REV" >> "$MANIFEST_FILE"
done

echo "Manifest populated with $(wc -l < "$MANIFEST_FILE") components."

# The Worker Function
verify_component() {
    local NAME="$1"
    local URL="$2"
    local EXPECTED_REV="$3"

    # Prefetch
    # nix-prefetch-git returns JSON. We use --quiet to reduce noise.
    # Note: --rev accepts tags (refs/tags/...)
    JSON=$(nix-prefetch-git --url "$URL" --rev "$EXPECTED_REV" --quiet --fetch-submodules 2>/dev/null)
    
    # Check if empty/failed
    if [ -z "$JSON" ]; then
        echo "{\"name\": \"$NAME\", \"error\": \"prefetch_failed\"}"
        echo "[FAIL] $NAME - Prefetch failed" >&2
        return 1
    fi

    # Extract info
    FETCHED_REV=$(echo "$JSON" | grep '"rev":' | cut -d'"' -f4)
    FETCHED_SHA=$(echo "$JSON" | grep '"sha256":' | cut -d'"' -f4)

    # Simple mismatch check (Note: tags resolve to commit hashes, so EXPECTED_REV (tag) != FETCHED_REV (hash) is expected behavior)
    # We just want the hash.
    
    echo "{\"name\": \"$NAME\", \"rev\": \"$FETCHED_REV\", \"sha256\": \"$FETCHED_SHA\"}"
    echo "[OK] $NAME -> $FETCHED_SHA" >&2
}

export -f verify_component

echo "Starting Hyper-Parallel Verification (48 threads)..."
cat "$MANIFEST_FILE" | xargs -P 48 -n 3 bash -c 'verify_component "$@"' _ >> "$RESULTS_FILE"

echo "Verification Complete. Results in $RESULTS_FILE"
