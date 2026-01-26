import xml.etree.ElementTree as ET
import subprocess
import json
import concurrent.futures
import os
import sys

XML_FILE = "/home/thenexussidekick/code/test/prd3/repos/ROCm/tools/rocm-build/rocm-7.2.0.xml"
SKIP_LIST = {"aomp", "flang", "hipfort", "omniperf", "rocm-docs"}
RESULTS_FILE = "verified_sources.json"

def verify_component(name, url, rev):
    try:
        cmd = ["nix-prefetch-git", "--url", url, "--rev", rev, "--quiet", "--fetch-submodules"]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        return {
            "name": name,
            "rev": data.get("rev"),
            "sha256": data.get("sha256"),
            "status": "OK"
        }
    except Exception as e:
        return {
            "name": name,
            "error": str(e),
            "status": "FAIL"
        }

def main():
    if not os.path.exists(XML_FILE):
        print(f"Error: XML file not found at {XML_FILE}", flush=True)
        sys.exit(1)

    tree = ET.parse(XML_FILE)
    root = tree.getroot()

    # Find default revision
    default_elem = root.find("default")
    default_rev = default_elem.get("revision") if default_elem is not None else None
    
    if not default_rev:
        print("Error: No default revision found.", flush=True)
        sys.exit(1)
    
    print(f"Default Revision: {default_rev}", flush=True)

    tasks = []
    
    # Parse projects
    for project in root.findall("project"):
        name = project.get("name")
        if not name:
            continue
            
        if name in SKIP_LIST or any(s in name for s in SKIP_LIST):
            continue
            
        rev = project.get("revision", default_rev)
        
        # Construct URL
        # All projects in this XML seem to be under rocm-org (https://github.com/ROCm/)
        # Handle special cases if any, but default to github.com/ROCm/{name}
        if name.startswith("http"):
            url = name
        else:
             url = f"https://github.com/ROCm/{name}"
        
        # Strip path attribute if present in name (some manifests put path in name? no, path is separate)
        
        tasks.append((name, url, rev))

    print(f"Verifying {len(tasks)} components with 48 threads...")
    
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=48) as executor:
        future_to_name = {executor.submit(verify_component, name, url, rev): name for name, url, rev in tasks}
        for future in concurrent.futures.as_completed(future_to_name):
            name = future_to_name[future]
            try:
                data = future.result()
                results.append(data)
                if data["status"] == "OK":
                    print(f"[OK] {name} -> {data['sha256']}")
                else:
                    print(f"[FAIL] {name}: {data.get('error')}")
            except Exception as exc:
                print(f"[FAIL] {name} generated an exception: {exc}")

    # Write results
    with open(RESULTS_FILE, "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"Verification complete. Saved to {RESULTS_FILE}")

if __name__ == "__main__":
    main()
