#!/usr/bin/env python3
"""
Generate source-lock.json from ROCm default.xml manifest

This tool:
1. Parses the default.xml manifest from ROCm release
2. Resolves all project refs to commit SHAs
3. Generates source-lock.json with full provenance

Usage:
    python gen_source_lock.py --manifest pinned/rocm/7.2.0/default.xml --output pinned/rocm/7.2.0/source-lock.json
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Dict, Any, Optional
from concurrent.futures import ThreadPoolExecutor, as_completed


@dataclass
class Submodule:
    """Git submodule reference"""
    path: str
    url: str
    commit_sha: str


@dataclass
class Project:
    """ROCm project from manifest"""
    name: str
    remote_url: str
    commit_sha: str
    path: str
    revision_source: str
    submodules: List[Submodule] = field(default_factory=list)
    
    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        if not self.submodules:
            del d['submodules']
        return d


@dataclass
class Blob:
    """External blob/tarball"""
    name: str
    url: str
    sha256: str
    size_bytes: Optional[int] = None
    
    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        if d['size_bytes'] is None:
            del d['size_bytes']
        return d


@dataclass
class SourceLock:
    """Complete source lock structure"""
    rocm_release: str
    manifest_sha256: str
    lock_sha256: str  # Computed after serialization
    generated_at: str
    projects: List[Project]
    blobs: List[Blob] = field(default_factory=list)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "rocm_release": self.rocm_release,
            "manifest_sha256": self.manifest_sha256,
            "lock_sha256": self.lock_sha256,
            "generated_at": self.generated_at,
            "projects": [p.to_dict() for p in self.projects],
            "blobs": [b.to_dict() for b in self.blobs]
        }


class ManifestParser:
    """Parse ROCm default.xml manifest"""
    
    GITHUB_BASE = "https://github.com"
    ROCM_REMOTE = "ROCm"
    
    def __init__(self, manifest_path: Path):
        self.manifest_path = manifest_path
        self.tree = ET.parse(manifest_path)
        self.root = self.tree.getroot()
        self.remotes: Dict[str, str] = {}
        self.default_revision: Optional[str] = None
        self._parse_remotes()
        self._parse_default()
        
    def _parse_remotes(self):
        """Parse remote definitions"""
        for remote in self.root.findall('remote'):
            name = remote.get('name')
            fetch = remote.get('fetch', f'{self.GITHUB_BASE}/')
            self.remotes[name] = fetch
            
    def _parse_default(self):
        """Parse default element"""
        default = self.root.find('default')
        if default is not None:
            self.default_revision = default.get('revision')
            
    def get_projects(self) -> List[Dict[str, Any]]:
        """Extract all projects from manifest"""
        projects = []
        
        for project in self.root.findall('project'):
            name = project.get('name')
            path = project.get('path', name)
            remote = project.get('remote', 'origin')
            revision = project.get('revision', self.default_revision)
            
            # Build remote URL
            remote_base = self.remotes.get(remote, f'{self.GITHUB_BASE}/')
            if not remote_base.endswith('/'):
                remote_base += '/'
            remote_url = f"{remote_base}{name}"
            
            # Normalize GitHub URLs
            if 'github.com' in remote_url and not remote_url.startswith('https://'):
                remote_url = f"https://github.com/{name}"
                
            projects.append({
                'name': name,
                'path': path,
                'remote_url': remote_url,
                'revision': revision,
                'revision_source': 'default.xml'
            })
            
        return projects


class SHAResolver:
    """Resolve git refs to commit SHAs"""
    
    SHA_PATTERN = re.compile(r'^[0-9a-f]{40}$')
    
    @classmethod
    def is_sha(cls, ref: str) -> bool:
        """Check if ref is already a SHA"""
        return bool(cls.SHA_PATTERN.match(ref))
    
    @classmethod
    def resolve_ref(cls, remote_url: str, ref: str) -> Optional[str]:
        """Resolve a git ref to SHA via ls-remote"""
        if cls.is_sha(ref):
            return ref
            
        # Inject GITHUB_TOKEN if available to avoid interactive prompts
        auth_url = remote_url
        github_token = os.environ.get("GITHUB_TOKEN")
        if github_token and remote_url.startswith("https://github.com"):
            auth_url = remote_url.replace("https://github.com", f"https://{github_token}@github.com")

        try:
            # Try tag first
            result = subprocess.run(
                ['git', 'ls-remote', '--tags', auth_url, f'refs/tags/{ref}'],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0 and result.stdout.strip():
                sha = result.stdout.strip().split()[0]
                if cls.is_sha(sha):
                    return sha
                    
            # Try branch
            result = subprocess.run(
                ['git', 'ls-remote', '--heads', auth_url, f'refs/heads/{ref}'],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0 and result.stdout.strip():
                sha = result.stdout.strip().split()[0]
                if cls.is_sha(sha):
                    return sha
                    
        except subprocess.TimeoutExpired:
            pass
        except Exception as e:
            # Use original URL in error message to avoid leaking token
            print(f"Warning: Failed to resolve {ref} from {remote_url}: {e}", file=sys.stderr)
            
        return None


def compute_file_hash(path: Path) -> str:
    """Compute SHA256 hash of file"""
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def generate_source_lock(
    manifest_path: Path,
    rocm_release: str,
    resolve_shas: bool = True,
    max_workers: int = 8
) -> SourceLock:
    """Generate source-lock.json from manifest"""
    
    # Compute manifest hash
    manifest_sha256 = compute_file_hash(manifest_path)
    
    # Parse manifest
    parser = ManifestParser(manifest_path)
    raw_projects = parser.get_projects()
    
    projects = []
    
    if resolve_shas:
        # Resolve refs in parallel
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {}
            for proj in raw_projects:
                if not SHAResolver.is_sha(proj['revision'] or ''):
                    future = executor.submit(
                        SHAResolver.resolve_ref,
                        proj['remote_url'],
                        proj['revision']
                    )
                    futures[future] = proj
                else:
                    projects.append(Project(
                        name=proj['name'],
                        remote_url=proj['remote_url'],
                        commit_sha=proj['revision'],
                        path=proj['path'],
                        revision_source=proj['revision_source']
                    ))
                    
            for future in as_completed(futures):
                proj = futures[future]
                sha = future.result()
                projects.append(Project(
                    name=proj['name'],
                    remote_url=proj['remote_url'],
                    commit_sha=sha or proj['revision'],
                    path=proj['path'],
                    revision_source=proj['revision_source']
                ))
    else:
        # Use revisions as-is (for offline mode)
        for proj in raw_projects:
            projects.append(Project(
                name=proj['name'],
                remote_url=proj['remote_url'],
                commit_sha=proj['revision'] or '',
                path=proj['path'],
                revision_source=proj['revision_source']
            ))
    
    # Sort by name for determinism
    projects.sort(key=lambda p: p.name)
    
    lock = SourceLock(
        rocm_release=rocm_release,
        manifest_sha256=manifest_sha256,
        lock_sha256="",  # Computed below
        generated_at=datetime.now(timezone.utc).isoformat(),
        projects=projects,
        blobs=[]  # Blobs added separately
    )
    
    # Compute lock hash (without lock_sha256 field)
    lock_data = lock.to_dict()
    lock_data['lock_sha256'] = ''
    lock_json = json.dumps(lock_data, sort_keys=True, separators=(',', ':'))
    lock.lock_sha256 = hashlib.sha256(lock_json.encode()).hexdigest()
    
    return lock


def main():
    parser = argparse.ArgumentParser(
        description="Generate source-lock.json from ROCm manifest"
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        required=True,
        help="Path to default.xml manifest"
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Output path for source-lock.json"
    )
    parser.add_argument(
        "--release",
        type=str,
        default="7.2.0",
        help="ROCm release version"
    )
    parser.add_argument(
        "--no-resolve",
        action="store_true",
        help="Don't resolve refs to SHAs (offline mode)"
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=8,
        help="Max parallel workers for SHA resolution"
    )
    parser.add_argument(
        "--run-id",
        type=str,
        help="Run ID for evidence tracking"
    )
    
    args = parser.parse_args()
    
    if not args.manifest.exists():
        print(f"Error: Manifest not found: {args.manifest}", file=sys.stderr)
        sys.exit(1)
        
    print(f"Parsing manifest: {args.manifest}")
    print(f"ROCm release: {args.release}")
    
    lock = generate_source_lock(
        manifest_path=args.manifest,
        rocm_release=args.release,
        resolve_shas=not args.no_resolve,
        max_workers=args.workers
    )
    
    # Write output
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, 'w') as f:
        json.dump(lock.to_dict(), f, indent=2)
        f.write('\n')
        
    # Write hash file
    hash_file = args.output.with_suffix('.sha256')
    with open(hash_file, 'w') as f:
        f.write(f"{lock.lock_sha256}  {args.output.name}\n")
        
    print(f"Generated: {args.output}")
    print(f"Hash file: {hash_file}")
    print(f"Projects: {len(lock.projects)}")
    print(f"Lock SHA256: {lock.lock_sha256[:16]}...")
    
    # Emit event if run-id provided
    if args.run_id:
        event = {
            "event": "lock_generated",
            "run_id": args.run_id,
            "timestamp": lock.generated_at,
            "manifest": str(args.manifest),
            "output": str(args.output),
            "project_count": len(lock.projects),
            "lock_sha256": lock.lock_sha256
        }
        print(json.dumps(event))


if __name__ == "__main__":
    main()
