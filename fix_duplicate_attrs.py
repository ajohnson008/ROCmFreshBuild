import sys

with open('flake.nix', 'r') as f:
    lines = f.readlines()

# Find the mkPackagesForTarget block
start_idx = -1
end_idx = -1
for i, line in enumerate(lines):
    if 'mkPackagesForTarget = target:' in line:
        start_idx = i
    if start_idx != -1 and 'in targetPackages;' in line:
        end_idx = i
        break

if start_idx == -1 or end_idx == -1:
    print("Could not find mkPackagesForTarget block")
    sys.exit(1)

# Extract lines within the targetPackages = { ... }; block
target_packages_start = -1
target_packages_end = -1
for i in range(start_idx, end_idx):
    if 'targetPackages = {' in lines[i]:
        target_packages_start = i + 1
    if target_packages_start != -1 and '};' in lines[i] and i > target_packages_start:
        # Heuristic: the first }; that matches indentation
        if lines[i].strip() == '};':
             target_packages_end = i
             break

if target_packages_start == -1 or target_packages_end == -1:
    print("Could not find targetPackages block content")
    sys.exit(1)

content_lines = lines[target_packages_start:target_packages_end]
seen_attrs = set()
unique_lines = []

for line in content_lines:
    stripped = line.strip()
    if '=' in stripped:
        attr = stripped.split('=')[0].strip()
        if attr in seen_attrs:
            print(f"DEBUG: Removing duplicate attr: {attr}")
            continue
        seen_attrs.add(attr)
    unique_lines.append(line)

# Reconstruct flake.nix
final_lines = lines[:target_packages_start] + unique_lines + lines[target_packages_end:]

with open('flake.nix', 'w') as f:
    f.writelines(final_lines)
