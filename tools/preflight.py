#!/usr/bin/env python3.11
import json
import os
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path

try:
    import resource
except ImportError:  # pragma: no cover - non-POSIX
    resource = None

try:
    import grp
except ImportError:  # pragma: no cover - non-POSIX
    grp = None


def _bytes_to_gb(value: int) -> float:
    return value / (1024 ** 3)


def _format_gb(value: int) -> str:
    return f"{_bytes_to_gb(value):.1f} GB"


def _run_cmd(cmd):
    try:
        result = subprocess.run(
            cmd,
            check=False,
            capture_output=True,
            text=True,
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except FileNotFoundError:
        return 127, "", f"{cmd[0]} not found"


def find_repo_root(start: Path) -> Path | None:
    if (start / ".git").exists() and (start / "flake.nix").exists():
        return start

    rc, out, _ = _run_cmd(["git", "-C", str(start), "rev-parse", "--show-toplevel"])
    if rc == 0:
        root = Path(out)
        if (root / "flake.nix").exists():
            return root

    for parent in [start, *start.parents]:
        if (parent / ".git").exists() and (parent / "flake.nix").exists():
            return parent

    return None


def _read_meminfo_kb() -> dict:
    meminfo = {}
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as handle:
            for line in handle:
                if ":" not in line:
                    continue
                key, value = line.split(":", 1)
                parts = value.strip().split()
                if not parts:
                    continue
                try:
                    meminfo[key] = int(parts[0])
                except ValueError:
                    continue
    except FileNotFoundError:
        return {}
    return meminfo


def _parse_kernel_version(release: str) -> tuple[int, int]:
    parts = release.split(".")
    major = 0
    minor = 0
    try:
        major = int("".join([c for c in parts[0] if c.isdigit()]))
        if len(parts) > 1:
            minor = int("".join([c for c in parts[1] if c.isdigit()]))
    except ValueError:
        return 0, 0
    return major, minor


def _gather_groups() -> set[str]:
    if grp is None:
        return set()
    groups = set()
    for gid in os.getgroups():
        try:
            groups.add(grp.getgrgid(gid).gr_name)
        except KeyError:
            continue
    return groups


def _write_json(path: Path, report: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")


def run_preflight(
    start_dir: Path,
    min_disk_gb: int = 200,
    json_out: Path | None = None,
    force: bool = False,
    no_preflight: bool = False,
) -> int:
    start_time = time.time()
    json_out = json_out or Path("runs/preflight.json")

    checks = []
    hard_fail = False
    has_warnings = False

    def add_check(check_id: str, status: str, message: str, details: dict | None = None):
        nonlocal hard_fail, has_warnings
        if status == "FAIL":
            hard_fail = True
        if status == "WARN":
            has_warnings = True
        checks.append(
            {
                "id": check_id,
                "status": status,
                "message": message,
                "details": details or {},
            }
        )

    if no_preflight:
        add_check(
            "preflight",
            "SKIP",
            "Preflight skipped via --no-preflight",
            {"forced": True},
        )
        report = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "repo_root": None,
            "checks": checks,
            "summary": {
                "pass": 0,
                "warn": 0,
                "fail": 0,
                "skip": 1,
            },
            "elapsed_seconds": round(time.time() - start_time, 2),
            "exit_code": 3,
        }
        _write_json(json_out, report)
        print("⚠️  Preflight skipped (--no-preflight).")
        print(f"JSON report: {json_out}")
        return 3

    repo_root = find_repo_root(start_dir)
    if repo_root is None:
        add_check(
            "repo_root",
            "FAIL",
            "Unable to locate repo root (flake.nix missing). Run from repo root.",
        )
    else:
        add_check(
            "repo_root",
            "PASS",
            f"Repo root: {repo_root}",
            {"path": str(repo_root)},
        )

    required_files = [
        "flake.nix",
        "flake.lock",
        "tools/rb",
        "scripts/jules/enforce_nexus_state.sh",
        "rb",
    ]
    missing = []
    if repo_root is not None:
        for rel in required_files:
            if not (repo_root / rel).exists():
                missing.append(rel)
        if missing:
            add_check(
                "required_files",
                "FAIL",
                "Missing required repo files",
                {"missing": missing},
            )
        else:
            add_check(
                "required_files",
                "PASS",
                "Required repo files present",
                {"files": required_files},
            )
    else:
        add_check(
            "required_files",
            "FAIL",
            "Repo root not found; cannot verify required files",
            {"missing": required_files},
        )

    nix_path = shutil.which("nix")
    if not nix_path:
        add_check(
            "nix_binary",
            "FAIL",
            "nix not found in PATH. Install Nix and enable flakes.",
        )
        nix_version = None
        experimental_features = []
    else:
        rc, out, err = _run_cmd(["nix", "--version"])
        if rc != 0:
            add_check(
                "nix_binary",
                "FAIL",
                f"nix present but failed to run: {err or out}",
            )
            nix_version = None
        else:
            nix_version = out
            add_check(
                "nix_binary",
                "PASS",
                f"{nix_version}",
            )

        experimental_features = []
        rc, out, err = _run_cmd(["nix", "show-config", "--json"])
        if rc == 0:
            try:
                config = json.loads(out) if out else {}
            except json.JSONDecodeError:
                config = {}
            exp = config.get("experimental-features", {})
            value = exp.get("value", "") if isinstance(exp, dict) else ""
            if isinstance(value, str):
                experimental_features = value.split()
            elif isinstance(value, list):
                experimental_features = value
        else:
            rc2, out2, _ = _run_cmd(["nix", "show-config"])
            if rc2 == 0:
                for line in out2.splitlines():
                    if line.strip().startswith("experimental-features"):
                        _, value = line.split("=", 1)
                        experimental_features = value.strip().split()
                        break
            else:
                add_check(
                    "nix_config",
                    "FAIL",
                    f"Unable to read nix config: {err or out or out2}",
                )

        required_features = {"nix-command", "flakes"}
        if required_features.issubset(set(experimental_features)):
            add_check(
                "nix_flakes",
                "PASS",
                "Flakes enabled",
                {"experimental_features": experimental_features},
            )
        else:
            add_check(
                "nix_flakes",
                "FAIL",
                "Flakes not enabled. Set experimental-features = nix-command flakes",
                {"experimental_features": experimental_features},
            )

    if repo_root is not None:
        usage = shutil.disk_usage(repo_root)
        free_gb = _bytes_to_gb(usage.free)
        if free_gb < min_disk_gb:
            add_check(
                "disk_space",
                "FAIL",
                f"Free disk below threshold ({free_gb:.1f} GB < {min_disk_gb} GB)",
                {"free_gb": free_gb, "threshold_gb": min_disk_gb},
            )
        else:
            add_check(
                "disk_space",
                "PASS",
                f"Free disk: {free_gb:.1f} GB",
                {"free_gb": free_gb, "threshold_gb": min_disk_gb},
            )

    system = platform.system()
    release = platform.release()
    if system != "Linux":
        add_check(
            "os_kernel",
            "FAIL",
            f"Unsupported OS: {system}. Linux required.",
            {"system": system, "release": release},
        )
    else:
        major, minor = _parse_kernel_version(release)
        if major and major < 5:
            add_check(
                "os_kernel",
                "WARN",
                f"Kernel {release} is older than recommended (>=5.x)",
                {"system": system, "release": release},
            )
        else:
            add_check(
                "os_kernel",
                "PASS",
                f"Kernel {release}",
                {"system": system, "release": release},
            )

    meminfo = _read_meminfo_kb()
    mem_total_kb = meminfo.get("MemTotal")
    mem_available_kb = meminfo.get("MemAvailable")
    if mem_total_kb:
        add_check(
            "ram",
            "PASS",
            f"RAM total: {mem_total_kb / 1024 / 1024:.1f} GB",
            {
                "total_gb": mem_total_kb / 1024 / 1024,
                "available_gb": mem_available_kb / 1024 / 1024 if mem_available_kb else None,
                "recommended_gb": 64,
            },
        )
    else:
        add_check("ram", "PASS", "RAM info unavailable")

    cpu_count = os.cpu_count() or 0
    add_check(
        "cpu",
        "PASS",
        f"CPU cores: {cpu_count}",
        {"cpu_cores": cpu_count},
    )

    kfd = Path("/dev/kfd")
    dri = Path("/dev/dri")
    if kfd.exists() and dri.exists():
        add_check(
            "rocm_devices",
            "PASS",
            "ROCm device nodes present",
            {"/dev/kfd": True, "/dev/dri": True},
        )
    else:
        add_check(
            "rocm_devices",
            "WARN",
            "ROCm device nodes missing (build OK, runtime may fail)",
            {"/dev/kfd": kfd.exists(), "/dev/dri": dri.exists()},
        )

    groups = _gather_groups()
    missing_groups = [g for g in ("video", "render") if g not in groups]
    if missing_groups:
        add_check(
            "user_groups",
            "WARN",
            "User missing video/render groups",
            {"missing": missing_groups, "groups": sorted(groups)},
        )
    else:
        add_check(
            "user_groups",
            "PASS",
            "User in video/render groups",
            {"groups": sorted(groups)},
        )

    if resource is None:
        add_check("memlock", "WARN", "memlock check unavailable")
    else:
        soft, hard = resource.getrlimit(resource.RLIMIT_MEMLOCK)
        recommended = 64 * 1024 ** 3
        if soft == resource.RLIM_INFINITY or soft >= recommended:
            add_check(
                "memlock",
                "PASS",
                "memlock limit OK",
                {"soft": soft, "hard": hard},
            )
        else:
            add_check(
                "memlock",
                "WARN",
                "memlock limit low; consider 'ulimit -l unlimited'",
                {"soft": soft, "hard": hard, "recommended_bytes": recommended},
            )

    summary = {
        "pass": sum(1 for c in checks if c["status"] == "PASS"),
        "warn": sum(1 for c in checks if c["status"] == "WARN"),
        "fail": sum(1 for c in checks if c["status"] == "FAIL"),
        "skip": sum(1 for c in checks if c["status"] == "SKIP"),
    }

    if hard_fail:
        exit_code = 2
    elif has_warnings:
        exit_code = 3 if force else 2
    else:
        exit_code = 0

    report = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "repo_root": str(repo_root) if repo_root else None,
        "checks": checks,
        "summary": summary,
        "elapsed_seconds": round(time.time() - start_time, 2),
        "exit_code": exit_code,
        "forced": force,
    }

    _write_json(json_out, report)

    print("\nPreflight summary")
    for check in checks:
        status = check["status"]
        msg = check["message"]
        print(f"[{status}] {check['id']}: {msg}")

    if exit_code == 0:
        print("\n✅ Preflight PASSED")
    elif exit_code == 3:
        print("\n⚠️  Preflight warnings overridden (--force)")
    else:
        print("\n❌ Preflight FAILED")

    print(f"JSON report: {json_out}")

    return exit_code


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print("Usage: preflight.py <repo_root>")
        return 2
    return run_preflight(Path(args[0]))


if __name__ == "__main__":
    raise SystemExit(main())
