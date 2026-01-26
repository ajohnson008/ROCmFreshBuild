#!/usr/bin/env bash
set -euo pipefail

# Computes sha256 for each pinned tarball and writes a 'sources.nix' file
# Usage: ./fill-shas.sh

HERE=$(cd $(dirname $0) && pwd)
OUT=$HERE/sources.nix

cat > "$OUT" <<'NIXHDR'
{
  # Generated sources.nix - contains fetchFromGitHub derivations with sha256 values
  # Run nix-prefetch-url --unpack <url> to compute each sha256 and this script will
  # fill them in automatically.

  sources = {
NIXHDR

jq -n '. as $null' >/dev/null 2>&1 || true

# Try to read pins via nix eval; if that fails, fall back to parsing flake.nix
for name in rocm-systems rocm-cmake "ROCR-Runtime" clr llvm-project; do
  url=""
  if url=$(nix eval --raw "(import ${HERE}/flake.nix {}).pins.${name}.url" 2>/dev/null); then
    :
  else
    # Fallback: extract the url line from flake.nix between '${name} = {' and '};'
    url=$(sed -n "/${name} = {/,/};/p" "$HERE/flake.nix" | sed -n 's/.*url = "\([^"]*\)".*/\1/p' | head -n1 || true)
  fi

  if [ -z "$url" ]; then
    echo "No URL found for $name — skipping"
    continue
  fi

  echo "Processing $name -> $url"
  sha=$(nix-prefetch-url --unpack "$url" 2>/dev/null || nix-prefetch-url --unpack "$url" 2>/dev/null || echo "UNKNOWN")
  if [ "$sha" = "UNKNOWN" ]; then
    echo "Failed to prefetch $name, leaving placeholder"
    sha='"0000000000000000000000000000000000000000000000000000"'
  else
    sha="\"$sha\""
  fi

  cat >> "$OUT" <<EOF
    ${name} = {
      url = "${url}";
      sha256 = ${sha};
    };
EOF

done

cat >> "$OUT" <<'NIXEOF'
  };
}
NIXEOF

echo "Written $OUT"
chmod +x "$OUT" || true

# Show the generated file
sed -n '1,200p' "$OUT"
