#!/usr/bin/env python3
"""运行所有 E2E tests。

用法：python3 tools/test/run_e2e.py [p2p_hole_punch|rendezvous|lan_e2e|lan_ui|all]
"""

from __future__ import annotations

import argparse
import sys
import subprocess
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import LOG_DIR, ROOT, emit, find_godot, godot_log_args, run_cmd  # noqa: E402


E2E_DIR = ROOT / "tools" / "e2e"


def run_e2e_python(name: str, script: Path, args: list = None) -> tuple[bool, str]:
    """运行 Python E2E 测试，返回 (success, output)"""
    if not script.is_file():
        return False, f"Script not found: {script}"

    godot = find_godot()
    if godot is None:
        return False, "Missing: Godot"

    cmd = [sys.executable, str(script)]
    if args:
        cmd.extend(args)

    emit("INFO", f"Running E2E: {name}")
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=180,
        )
        output = proc.stdout + proc.stderr
        success = proc.returncode == 0
        if success:
            emit("PASS", f"E2E {name} OK")
        else:
            emit("FAIL", f"E2E {name} FAILED (exit {proc.returncode})")
            for line in output.splitlines()[-50:]:
                print(f"  {line}")
        return success, output
    except subprocess.TimeoutExpired:
        emit("FAIL", f"E2E {name} TIMEOUT")
        return False, "TIMEOUT"
    except Exception as e:
        emit("FAIL", f"E2E {name} ERROR: {e}")
        return False, str(e)


def run_e2e_godot(name: str, script: Path, args: list = None) -> tuple[bool, str]:
    """运行 Godot E2E 测试，返回 (success, output)"""
    if not script.is_file():
        return False, f"Script not found: {script}"

    godot = find_godot()
    if godot is None:
        return False, "Missing: Godot"

    cmd = [
        str(godot),
        "--headless",
        "--path", str(ROOT),
        *godot_log_args(LOG_DIR / f"e2e-{name}.log"),
        "--script", str(script),
    ]
    if args:
        cmd.extend(["--"] + args)

    emit("INFO", f"Running E2E: {name}")
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=180,
        )
        output = proc.stdout + proc.stderr
        success = proc.returncode == 0
        if success:
            emit("PASS", f"E2E {name} OK")
        else:
            emit("FAIL", f"E2E {name} FAILED (exit {proc.returncode})")
            for line in output.splitlines()[-50:]:
                print(f"  {line}")
        return success, output
    except subprocess.TimeoutExpired:
        emit("FAIL", f"E2E {name} TIMEOUT")
        return False, "TIMEOUT"
    except Exception as e:
        emit("FAIL", f"E2E {name} ERROR: {e}")
        return False, str(e)


def main() -> int:
    parser = argparse.ArgumentParser(description="WPG E2E Test Runner")
    parser.add_argument(
        "suite",
        nargs="?",
        default="all",
        choices=["p2p_hole_punch", "rendezvous", "lan_e2e", "lan_ui", "all"],
        help="E2E test suite to run",
    )
    args = parser.parse_args()

    suites = {
        "p2p_hole_punch": ("python", E2E_DIR / "p2p_hole_punch" / "run.py"),
        "rendezvous": ("python", E2E_DIR / "rendezvous" / "run.py"),
        "lan_e2e": ("godot", E2E_DIR / "lan" / "run.gd"),
        "lan_ui": ("python", E2E_DIR / "lan" / "ui_run.py"),
    }

    if args.suite == "all":
        to_run = list(suites.items())
    else:
        to_run = [(args.suite, suites[args.suite])]

    results = {}
    for name, (runner_type, script) in to_run:
        if runner_type == "python":
            success, output = run_e2e_python(name, script)
        else:
            success, output = run_e2e_godot(name, script)
        results[name] = (success, output)

    # Summary
    print()
    print("=" * 50)
    print("E2E Test Summary")
    print("=" * 50)
    all_passed = True
    for name, (success, _) in results.items():
        status = "PASS" if success else "FAIL"
        print(f"  {name}: {status}")
        if not success:
            all_passed = False

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())