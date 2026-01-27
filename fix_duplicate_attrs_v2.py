import sys

with open('flake.nix', 'r') as f:
    lines = f.readlines()

new_lines = []
seen_attrs = set()
in_target_packages = False

for line in lines:
    stripped = line.strip()
    
    if 'targetPackages = {' in line:
        in_target_packages = True
        new_lines.append(line)
        continue
        
    if in_target_packages and stripped == '};':
        in_target_packages = False
        new_lines.append(line)
        continue
        
    if in_target_packages:
        if '=' in stripped:
            attr = stripped.split('=')[0].strip()
            if attr in seen_attrs:
                print(f"DEBUG: Skipping duplicate attr: {attr}")
                continue
            seen_attrs.add(attr)
            
    new_lines.append(line)

with open('flake.nix', 'w') as f:
    f.writelines(new_lines)
