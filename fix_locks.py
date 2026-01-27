import json
import os
import subprocess
import hashlib

LOCK_FILE = "pinned/rocm/7.2.0/source-lock.json"
HASH_FILE = "pinned/rocm/7.2.0/source-lock.sha256"
MIRROR_ROOT = "mirrors/git"

with open(LOCK_FILE) as f:
    data = json.load(f)

changed = False

for proj in data.get("projects", []):
    commit = proj.get("commit_sha", "")
    # Check if hex string of length 40
    is_sha = len(commit) == 40 and all(c in "0123456789abcdef" for c in commit.lower())
    
    if not is_sha: 
        name = proj["name"]
        tag = commit
        mirror_name = name.replace("/", "_") + ".mirror"
        mirror_path = os.path.join(MIRROR_ROOT, mirror_name)
        
        if os.path.exists(mirror_path):
            try:
                # Get SHA for the tag
                cmd = ["git", "rev-parse", tag]
                res = subprocess.run(cmd, cwd=mirror_path, capture_output=True, text=True, check=False)
                if res.returncode != 0:
                    # Fallback to HEAD
                    print(f"Tag {tag} not found for {name}, falling back to HEAD")
                    cmd = ["git", "rev-parse", "HEAD"]
                    res = subprocess.run(cmd, cwd=mirror_path, capture_output=True, text=True, check=True)
                
                sha = res.stdout.strip()
                print(f"Fixed {name}: {tag} -> {sha}")
                proj["commit_sha"] = sha
                changed = True
            except Exception as e:
                print(f"Failed to resolve {tag} for {name}: {e}")
        else:
            print(f"Mirror not found for {name} at {mirror_path}")

if changed:
    with open(LOCK_FILE, "w") as f:
        json.dump(data, f, indent=2)
    
    # Update hash
    with open(LOCK_FILE, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    with open(HASH_FILE, "w") as f:
        f.write(digest + "  source-lock.json\n")
    print("Updated source-lock.json and hash.")
else:
    print("No changes needed.")
