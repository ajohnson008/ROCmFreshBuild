#!/usr/bin/env python3
import re
import os
import sys

def main():
    agents_file = "AGENTS.md"
    if not os.path.exists(agents_file):
        print(f"❌ {agents_file} not found!")
        sys.exit(1)

    with open(agents_file, "r") as f:
        content = f.read()

    # Find all "Assigned Documents" sections
    assigned_docs_sections = re.findall(r"\*\*Assigned Documents\*\*:(.*?)(?=\n\n|\Z)", content, re.DOTALL)

    missing_files = []

    print("🔍 Auditing Assigned Documents in AGENTS.md...")

    for section in assigned_docs_sections:
        # Extract filenames in backticks
        filenames = re.findall(r"- `(.*?)`", section)
        for filename in filenames:
            if not os.path.exists(filename):
                print(f"❌ Missing reference: {filename}")
                missing_files.append(filename)
            else:
                print(f"✅ Found: {filename}")

    if missing_files:
        print(f"\n🚨 Audit FAILED. {len(missing_files)} missing references found.")
        sys.exit(1)
    else:
        print("\n✅ Audit PASSED. All references found.")
        sys.exit(0)

if __name__ == "__main__":
    main()
