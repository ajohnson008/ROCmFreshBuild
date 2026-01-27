#!/usr/bin/env python3.11
"""
Sync Blobs - Download external blobs to content-addressed store

This tool:
1. Reads blob definitions from source-lock.json or blobs.json
2. Downloads to content-addressed store (mirrors/blobs/<hashType>/<hash>)
3. Updates mirrors/blobs/index.json atomically

The content-addressed layout supports hashed-mirror fetch-by-hash patterns:
  mirrors/blobs/sha256/<hash> -> file contents

Usage:
    python sync_blobs.py --lock pinned/rocm/7.2.0/source-lock.json --output mirrors/blobs
"""

import argparse
import hashlib
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
import urllib.request
import urllib.error


@dataclass
class BlobStatus:
    """Status of a single blob"""
    name: str
    url: str
    sha256: str
    store_path: str
    size_bytes: int
    last_sync: str
    status: str  # "synced" | "failed" | "verified"
    error: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        if d['error'] is None:
            del d['error']
        return d


@dataclass
class BlobIndex:
    """Index of all blobs"""
    version: str
    last_updated: str
    hash_type: str
    total_count: int
    synced_count: int
    failed_count: int
    total_size_bytes: int
    blobs: List[BlobStatus]
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "version": self.version,
            "last_updated": self.last_updated,
            "hash_type": self.hash_type,
            "total_count": self.total_count,
            "synced_count": self.synced_count,
            "failed_count": self.failed_count,
            "total_size_bytes": self.total_size_bytes,
            "blobs": [b.to_dict() for b in self.blobs]
        }


class BlobSync:
    """Sync blobs with content-addressed storage"""
    
    HASH_TYPE = "sha256"
    
    def __init__(
        self,
        source_lock_path: Path,
        output_dir: Path,
        max_workers: int = 4,
        timeout: int = 300
    ):
        self.source_lock_path = source_lock_path
        self.output_dir = output_dir
        self.hash_dir = output_dir / self.HASH_TYPE
        self.max_workers = max_workers
        self.timeout = timeout
        self.source_lock = self._load_source_lock()
        
    def _load_source_lock(self) -> Dict[str, Any]:
        """Load source lock file"""
        with open(self.source_lock_path) as f:
            return json.load(f)
            
    def _compute_sha256(self, file_path: Path) -> str:
        """Compute SHA256 hash of file"""
        sha256 = hashlib.sha256()
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(65536), b''):
                sha256.update(chunk)
        return sha256.hexdigest()
        
    def _download_blob(self, url: str, dest: Path) -> int:
        """Download blob using curl (more reliable for large files)"""
        result = subprocess.run(
            [
                'curl', '-fsSL',
                '--retry', '3',
                '--retry-delay', '5',
                '-o', str(dest),
                url
            ],
            capture_output=True,
            text=True,
            timeout=self.timeout
        )
        
        if result.returncode != 0:
            raise Exception(f"curl failed: {result.stderr}")
            
        return dest.stat().st_size
        
    def _sync_single_blob(self, blob: Dict[str, Any]) -> BlobStatus:
        """Sync a single blob to content-addressed store"""
        name = blob['name']
        url = blob['url']
        expected_sha256 = blob['sha256']
        expected_size = blob.get('size_bytes')
        
        store_path = self.hash_dir / expected_sha256
        
        try:
            # Check if already exists and verified
            if store_path.exists():
                actual_sha256 = self._compute_sha256(store_path)
                if actual_sha256 == expected_sha256:
                    return BlobStatus(
                        name=name,
                        url=url,
                        sha256=expected_sha256,
                        store_path=str(store_path),
                        size_bytes=store_path.stat().st_size,
                        last_sync=datetime.now(timezone.utc).isoformat(),
                        status="verified"
                    )
                else:
                    # Hash mismatch, re-download
                    store_path.unlink()
                    
            # Download to temp file
            self.hash_dir.mkdir(parents=True, exist_ok=True)
            
            with tempfile.NamedTemporaryFile(
                dir=self.hash_dir,
                delete=False
            ) as tmp:
                tmp_path = Path(tmp.name)
                
            size = self._download_blob(url, tmp_path)
            
            # Verify hash
            actual_sha256 = self._compute_sha256(tmp_path)
            if actual_sha256 != expected_sha256:
                tmp_path.unlink()
                return BlobStatus(
                    name=name,
                    url=url,
                    sha256=expected_sha256,
                    store_path="",
                    size_bytes=0,
                    last_sync=datetime.now(timezone.utc).isoformat(),
                    status="failed",
                    error=f"Hash mismatch: expected {expected_sha256[:16]}..., got {actual_sha256[:16]}..."
                )
                
            # Atomic move to final location
            os.rename(tmp_path, store_path)
            
            return BlobStatus(
                name=name,
                url=url,
                sha256=expected_sha256,
                store_path=str(store_path),
                size_bytes=size,
                last_sync=datetime.now(timezone.utc).isoformat(),
                status="synced"
            )
            
        except subprocess.TimeoutExpired:
            return BlobStatus(
                name=name,
                url=url,
                sha256=expected_sha256,
                store_path="",
                size_bytes=0,
                last_sync=datetime.now(timezone.utc).isoformat(),
                status="failed",
                error=f"Timeout after {self.timeout}s"
            )
        except Exception as e:
            return BlobStatus(
                name=name,
                url=url,
                sha256=expected_sha256,
                store_path="",
                size_bytes=0,
                last_sync=datetime.now(timezone.utc).isoformat(),
                status="failed",
                error=str(e)[:500]
            )
            
    def sync_all(self, run_id: Optional[str] = None) -> BlobIndex:
        """Sync all blobs with bounded parallelism"""
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        blobs = self.source_lock.get('blobs', [])
        
        if not blobs:
            print("No blobs defined in source-lock.json")
            return BlobIndex(
                version="1.0.0",
                last_updated=datetime.now(timezone.utc).isoformat(),
                hash_type=self.HASH_TYPE,
                total_count=0,
                synced_count=0,
                failed_count=0,
                total_size_bytes=0,
                blobs=[]
            )
            
        statuses: List[BlobStatus] = []
        
        print(f"Syncing {len(blobs)} blobs (max {self.max_workers} parallel)...")
        
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            futures = {
                executor.submit(self._sync_single_blob, blob): blob
                for blob in blobs
            }
            
            for future in as_completed(futures):
                blob = futures[future]
                try:
                    status = future.result()
                    statuses.append(status)
                    symbol = "✅" if status.status in ("synced", "verified") else "❌"
                    print(f"  {symbol} {blob['name']}")
                except Exception as e:
                    statuses.append(BlobStatus(
                        name=blob['name'],
                        url=blob['url'],
                        sha256=blob['sha256'],
                        store_path="",
                        size_bytes=0,
                        last_sync=datetime.now(timezone.utc).isoformat(),
                        status="failed",
                        error=str(e)[:500]
                    ))
                    print(f"  ❌ {blob['name']}: {e}")
                    
        # Sort by name for determinism
        statuses.sort(key=lambda s: s.name)
        
        synced = sum(1 for s in statuses if s.status in ("synced", "verified"))
        failed = sum(1 for s in statuses if s.status == "failed")
        total_size = sum(s.size_bytes for s in statuses)
        
        index = BlobIndex(
            version="1.0.0",
            last_updated=datetime.now(timezone.utc).isoformat(),
            hash_type=self.HASH_TYPE,
            total_count=len(statuses),
            synced_count=synced,
            failed_count=failed,
            total_size_bytes=total_size,
            blobs=statuses
        )
        
        # Write index atomically
        self._write_index_atomic(index)
        
        # Emit event if run-id provided
        if run_id:
            event = {
                "event": "blob_sync_complete",
                "run_id": run_id,
                "timestamp": index.last_updated,
                "total": index.total_count,
                "synced": index.synced_count,
                "failed": index.failed_count,
                "total_size_bytes": index.total_size_bytes
            }
            print(json.dumps(event))
            
        return index
        
    def _write_index_atomic(self, index: BlobIndex):
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
        description="Sync blobs to content-addressed store"
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
        help="Output directory for blobs"
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
        default=300,
        help="Timeout per blob in seconds"
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
        
    syncer = BlobSync(
        source_lock_path=args.lock,
        output_dir=args.output,
        max_workers=args.workers,
        timeout=args.timeout
    )
    
    index = syncer.sync_all(run_id=args.run_id)
    
    print()
    print(f"Blob sync complete:")
    print(f"  Total: {index.total_count}")
    print(f"  Synced: {index.synced_count}")
    print(f"  Failed: {index.failed_count}")
    print(f"  Size: {index.total_size_bytes / (1024*1024):.1f} MB")
    print(f"  Index: {args.output / 'index.json'}")
    
    sys.exit(0 if index.failed_count == 0 else 1)


if __name__ == "__main__":
    main()
