#!/usr/bin/env python3
"""
sync_git_mirrors.py - Offline-safe source mirroring for ROCm 7.2.0
Fixes: Uses GitHub tarball format (not git repos) for hash stability
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

def parse_args():
    parser = argparse.ArgumentParser(description="Sync ROCm sources to offline cache")
    parser.add_argument("--lock", required=True, help="Path to source-lock.json")
    parser.add_argument("--output", required=True, help="Output directory for cache")
    parser.add_argument("--manifest", required=True, help="Repo manifest XML")
    return parser.parse_args()

def get_tarball_url(repo_url: str, rev: str, subdir: str = None) -> str:
    """Convert git repo to GitHub tarball URL"""
    # Handle ROCm org repos
    if "github.com/ROCm/" in repo_url:
        repo_name = repo_url.split("ROCm/")[1].rstrip(".git")
        if subdir:
            # Monorepo subdirectory - full repo tarball
            return f"https://github.com/ROCm/{repo_name}/archive/{rev}.tar.gz"
        else:
            # Tagged release
            return f"https://github.com/ROCm/{repo_name}/archive/refs/tags/{rev}.tar.gz"
    else:
        # Fallback for other repos
        parsed = urlparse(repo_url)
        path = parsed.path.rstrip(".git")
        return f"{parsed.scheme}://{parsed.netloc}{path}/archive/{rev}.tar.gz"

def main():
    args = parse_args()
    lock_path = Path(args.lock)
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    with open(lock_path) as f:
        lock = json.load(f)
    
    print(f"Syncing {len(lock['sources'])} sources to {output_dir}...")
    
    for src in lock['sources']:
        name = src['name']
        repo = src['repo']
        rev = src['rev']
        sha256 = src.get('sha256', 'sha256-unknown')
        subdir = src.get('subdir', None)  # Critical for monorepos
        
        # Generate tarball filename
        if subdir:
            tarball_name = f"{name}-{rev}-{subdir.replace('/', '-')}.tar.gz"
        else:
            tarball_name = f"{name}-{rev}.tar.gz"
        
        tarball_path = output_dir / tarball_name
        
        # Skip if already cached
        if tarball_path.exists():
            print(f"✓ {name} already cached at {tarball_path.name}")
            continue
        
        # Generate download URL
        url = get_tarball_url(repo, rev, subdir)
        print(f"↓ Fetching {name} ({rev}) from {url}")
        
        # Download with curl (retry on failure)
        try:
            subprocess.run([
                "curl", "-L", "--retry", "3", "--retry-delay", "2",
                "-o", str(tarball_path), url
            ], check=True, capture_output=True)
        except subprocess.CalledProcessError as e:
            print(f"✗ Failed to fetch {name}: {e.stderr.decode()}", file=sys.stderr)
            sys.exit(1)
        
        # Verify hash if available
        if sha256 != 'sha256-unknown':
            print(f"  Verifying SHA256...")
            result = subprocess.run(
                ["nix-hash", "--type", "sha256", "--base32", str(tarball_path)],
                capture_output=True, text=True
            )
            actual_hash = f"sha256-{result.stdout.strip()}"
            if actual_hash != sha256:
                print(f"✗ Hash mismatch for {name}!", file=sys.stderr)
                print(f"  Expected: {sha256}", file=sys.stderr)
                print(f"  Actual:   {actual_hash}", file=sys.stderr)
                tarball_path.unlink()
                sys.exit(1)
            else:
                print(f"  ✓ Hash verified")
        
        print(f"✓ Cached {tarball_path.name}")
    
    print("\nAll sources synced successfully. Offline cache ready.")

if __name__ == "__main__":
    main()