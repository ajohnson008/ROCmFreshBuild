#!/usr/bin/env python3
"""
Sync Git Mirrors - Mirror all ROCm repositories with bounded parallelism

This tool:
1. Reads source-lock.json for repository list
2. Creates/updates git --mirror clones
3. Updates mirrors/git/index.json atomically

Usage:
    python sync_git_mirrors.py --lock pinned/rocm/7.2.0/source-lock.json --output mirrors/git
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Dict, Any, Optional


@dataclass
class MirrorStatus:
    """Status of a single mirror"""
    name: str
    remote_url: str
    mirror_path: str
    last_sync: str
    commit_sha: str
    status: str  # "synced" | "failed" | "pending"
    error: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        if d['error'] is None:
            del d['error']
        return d


@dataclass  
class MirrorIndex:
    """Index of all mirrors"""
    version: str
    last_updated: str
    source_lock_sha256: str
    total_count: int
    synced_count: int
    failed_count: int
    mirrors: List[MirrorStatus]
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "version": self.version,
            "last_updated": self.last_updated,
            "source_lock_sha256": self.source_lock_sha256,
            "total_count": self.total_count,
            "synced_count": self.synced_count,
            "failed_count": self.failed_count,
            "mirrors": [m.to_dict() for m in self.mirrors]
        }


class GitMirrorSync:
    """Sync git mirrors with bounded parallelism"""
    
    def __init__(
        self,
        source_lock_path: Path,
        output_dir: Path,
        max_workers: int = 4,
        timeout: int = 600
    ):
        self.source_lock_path = source_lock_path
        self.output_dir = output_dir
        self.max_workers = max_workers
        self.timeout = timeout
        self.source_lock = self._load_source_lock()
        
    def _load_source_lock(self) -> Dict[str, Any]:
        """Load source lock file"""
        with open(self.source_lock_path) as f:
            return json.load(f)
            
    def _mirror_name(self, project_name: str) -> str:
        """Convert project name to mirror directory name"""
        return project_name.replace('/', '_') + '.mirror'
        
    def _sync_single_mirror(self, project: Dict[str, Any]) -> MirrorStatus:
        """Sync a single repository mirror"""
        name = project['name']
        remote_url = project['remote_url']
        commit_sha = project['commit_sha']
        
        mirror_name = self._mirror_name(name)
        mirror_path = self.output_dir / mirror_name
        
        try:
            if mirror_path.exists():
                # Update existing mirror
                result = subprocess.run(
                    ['git', '--git-dir', str(mirror_path), 'fetch', '--all', '--prune'],
                    capture_output=True,
                    text=True,
                    timeout=self.timeout
                )
            else:
                # Create new mirror
                result = subprocess.run(
                    ['git', 'clone', '--mirror', remote_url, str(mirror_path)],
                    capture_output=True,
                    text=True,
                    timeout=self.timeout
                )
                
            if result.returncode != 0:
                return MirrorStatus(
                    name=name,
                    remote_url=remote_url,
                    mirror_path=str(mirror_path),
                    last_sync=datetime.now(timezone.utc).isoformat(),
                    commit_sha=commit_sha,
                    status="failed",
                    error=result.stderr[:500] if result.stderr else "Unknown error"
                )
                
            return MirrorStatus(
                name=name,
                remote_url=remote_url,
                mirror_path=str(mirror_path),
                last_sync=datetime.now(timezone.utc).isoformat(),
                commit_sha=commit_sha,
                status="synced"
            )
            
        except subprocess.TimeoutExpired:
            return MirrorStatus(
                name=name,
                remote_url=remote_url,
                mirror_path=str(mirror_path),
                last_sync=datetime.now(timezone.utc).isoformat(),
                commit_sha=commit_sha,
                status="failed",
                error=f"Timeout after {self.timeout}s"
            )
        except Exception as e:
            return MirrorStatus(
                name=name,
                remote_url=remote_url,
                mirror_path=str(mirror_path),
                last_sync=datetime.now(timezone.utc).isoformat(),
                commit_sha=commit_sha,
                status="failed",
                error=str(e)[:500]
            )
            
    def sync_all(self, run_id: Optional[str] = None) -> MirrorIndex:
        """Sync all mirrors with bounded parallelism"""
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # 1. Sync Git Repositories
        projects = self.source_lock.get('projects', [])
        statuses: List[MirrorStatus] = []
        
        print(f"Syncing {len(projects)} repositories (max {self.max_workers} parallel)...")
        
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            futures = {
                executor.submit(self._sync_single_mirror, proj): proj
                for proj in projects
            }
            
            for future in as_completed(futures):
                proj = futures[future]
                try:
                    status = future.result()
                    statuses.append(status)
                    symbol = "✅" if status.status == "synced" else "❌"
                    print(f"  {symbol} {proj['name']}")
                except Exception as e:
                    statuses.append(MirrorStatus(
                        name=proj['name'],
                        remote_url=proj['remote_url'],
                        mirror_path="",
                        last_sync=datetime.now(timezone.utc).isoformat(),
                        commit_sha=proj['commit_sha'],
                        status="failed",
                        error=str(e)[:500]
                    ))
                    print(f"  ❌ {proj['name']}: {e}")

        # 2. Sync LLVM Project Tarball (Special case for ROCm 7.2.0)
        # We need the full tarball for subdir extraction in Nix
        llvm_rev = "3098435244119c38f6100dbd8d61e56c942a3c00"
        cache_dir = self.output_dir.parent / "cache"
        cache_dir.mkdir(exist_ok=True)
        llvm_tarball = cache_dir / f"llvm-project-{llvm_rev}.tar.gz"
        
        if not llvm_tarball.exists():
            print(f"Downloading LLVM project tarball ({llvm_rev})...")
            url = f"https://github.com/ROCm/llvm-project/archive/{llvm_rev}.tar.gz"
            try:
                subprocess.run(['curl', '-fsSL', '-o', str(llvm_tarball), url], check=True)
                print(f"  ✅ llvm-project tarball")
            except subprocess.CalledProcessError as e:
                print(f"  ❌ llvm-project tarball: {e}")
        else:
            print(f"  ✅ llvm-project tarball (cached)")
                    
        # Sort by name for determinism
        statuses.sort(key=lambda s: s.name)
        
        synced = sum(1 for s in statuses if s.status == "synced")
        failed = sum(1 for s in statuses if s.status == "failed")
        
        index = MirrorIndex(
            version="1.0.0",
            last_updated=datetime.now(timezone.utc).isoformat(),
            source_lock_sha256=self.source_lock.get('lock_sha256', ''),
            total_count=len(statuses),
            synced_count=synced,
            failed_count=failed,
            mirrors=statuses
        )
        
        # Write index atomically
        self._write_index_atomic(index)
        
        # Emit event if run-id provided
        if run_id:
            event = {
                "event": "mirror_sync_complete",
                "run_id": run_id,
                "timestamp": index.last_updated,
                "total": index.total_count,
                "synced": index.synced_count,
                "failed": index.failed_count
            }
            print(json.dumps(event))
            
        return index
        
    def _write_index_atomic(self, index: MirrorIndex):
        """Write index.json atomically (temp + rename)"""
        index_path = self.output_dir / "index.json"
        
        # Write to temp file first
        with tempfile.NamedTemporaryFile(
            mode='w',
            dir=self.output_dir,
            suffix='.json',
            delete=False
        ) as f:
            json.dump(index.to_dict(), f, indent=2)
            f.write('\n')
            temp_path = f.name
            
        # Atomic rename
        os.rename(temp_path, index_path)


def main():
    parser = argparse.ArgumentParser(
        description="Sync Git mirrors with bounded parallelism"
    )
    parser.add_argument(
        "--lock",
        type=Path,
        required=True,
        help="Path to source-lock.json"
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Output directory for mirrors"
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=4,
        help="Max parallel workers"
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=600,
        help="Timeout per repository in seconds"
    )
    parser.add_argument(
        "--run-id",
        type=str,
        help="Run ID for evidence tracking"
    )
    
    args = parser.parse_args()
    
    if not args.lock.exists():
        print(f"Error: Source lock not found: {args.lock}", file=sys.stderr)
        sys.exit(1)
        
    syncer = GitMirrorSync(
        source_lock_path=args.lock,
        output_dir=args.output,
        max_workers=args.workers,
        timeout=args.timeout
    )
    
    index = syncer.sync_all(run_id=args.run_id)
    
    print()
    print(f"Mirror sync complete:")
    print(f"  Total: {index.total_count}")
    print(f"  Synced: {index.synced_count}")
    print(f"  Failed: {index.failed_count}")
    print(f"  Index: {args.output / 'index.json'}")
    
    sys.exit(0 if index.failed_count == 0 else 1)


if __name__ == "__main__":
    main()
