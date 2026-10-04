#!/usr/bin/env python3
"""统一测试入口：运行所有测试层级。

用法：
  python3 tools/test/run_all.py unit
  python3 tools/test/run_all.py integration
  python3 tools/test/run_all.py e2e
  python3 tools/test/run_all.py e2e p2p_hole_punch
  python3 tools/test/run_all.py validate
  python3 tools/test/run_all.py architecture
  python3 tools/test/run_all.py smoke
  python3 tools/test/run_all.py all
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import LOG_DIR, ROOT, emit, find_godot, godot_log_args, run_cmd, Outcome  # noqa: E402


TOOLS_DIR = ROOT / "tools"
TEST_DIR = TOOLS_DIR / "test"
CI_DIR = TOOLS_DIR / "ci"


def run_python_script(script: Path, args: list = None, timeout: int = 300) -> tuple[bool, str]:
    """运行 Python 脚本，返回 (success, output)"""
    if not script.is_file():
        return False, f"Script not found: {script}"

    cmd = [sys.executable, str(script)]
    if args:
        cmd.extend(args)

    try:
        proc = subprocess.run(
            cmd,
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        output = proc.stdout + proc.stderr
        return proc.returncode == 0, output
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT"
    except Exception as e:
        return False, str(e)


def run_unit() -> tuple[bool, str]:
    """运行所有 unit tests"""
    return run_python_script(TEST_DIR / "run_unit.py", timeout=600)


def run_integration() -> tuple[bool, str]:
    """运行所有 integration tests"""
    return run_python_script(TEST_DIR / "run_integration.py", timeout=600)


def run_e2e(suite: str = "all") -> tuple[bool, str]:
    """运行 E2E tests"""
    return run_python_script(TEST_DIR / "run_e2e.py", [suite], timeout=600)


def run_validate() -> tuple[bool, str]:
    """运行 validate"""
    return run_python_script(CI_DIR / "validate.py", timeout=180)


def run_architecture() -> tuple[bool, str]:
    """运行 architecture guard"""
    return run_python_script(CI_DIR / "architecture.py", timeout=60)


def run_smoke() -> tuple[bool, str]:
    """运行 smoke test"""
    return run_python_script(CI_DIR / "smoke.py", timeout=300)


def run_ci() -> tuple[bool, str]:
    """运行完整 CI pipeline (validate + architecture + smoke)"""
    return run_python_script(CI_DIR / "run_ci.py", timeout=600)


def main() -> int:
    parser = argparse.ArgumentParser(description="WPG Unified Test Runner")
    parser.add_argument(
        "command",
        choices=["unit", "integration", "e2e", "validate", "architecture", "smoke", "ci", "all"],
        help="Test command to run",
    )
    parser.add_argument(
        "suite",
        nargs="?",
        default="all",
        help="E2E suite to run (for e2e command)",
    )
    args = parser.parse_args()

    commands = {
        "unit": lambda: run_unit(),
        "integration": lambda: run_integration(),
        "e2e": lambda: run_e2e(args.suite),
        "validate": lambda: run_validate(),
        "architecture": lambda: run_architecture(),
        "smoke": lambda: run_smoke(),
        "ci": lambda: run_ci(),
        "all": lambda: run_all(),
    }

    if args.command not in commands:
        emit("FAIL", f"Unknown command: {args.command}")
        return 1

    emit("INFO", f"Running: {args.command}" + (f" {args.suite}" if args.command == "e2e" else ""))

    success, output = commands[args.command]()

    # Print output
    if output:
        for line in output.splitlines():
            print(line)

    if success:
        emit("PASS", f"{args.command} completed successfully")
        return 0
    else:
        emit("FAIL", f"{args.command} failed")
        return 1


def run_all() -> tuple[bool, str]:
    """运行所有测试：unit -> integration -> e2e -> validate -> architecture -> smoke"""
    results = {}

    # Unit tests
    emit("INFO", "=== Running Unit Tests ===")
    success, output = run_unit()
    results["unit"] = success
    if output:
        for line in output.splitlines():
            print(line)

    # Integration tests
    emit("INFO", "=== Running Integration Tests ===")
    success, output = run_integration()
    results["integration"] = success
    if output:
        for line in output.splitlines():
            print(line)

    # E2E tests
    emit("INFO", "=== Running E2E Tests ===")
    success, output = run_e2e("all")
    results["e2e"] = success
    if output:
        for line in output.splitlines():
            print(line)

    # Validate
    emit("INFO", "=== Running Validate ===")
    success, output = run_validate()
    results["validate"] = success
    if output:
        for line in output.splitlines():
            print(line)

    # Architecture
    emit("INFO", "=== Running Architecture ===")
    success, output = run_architecture()
    results["architecture"] = success
    if output:
        for line in output.splitlines():
            print(line)

    # Smoke
    emit("INFO", "=== Running Smoke ===")
    success, output = run_smoke()
    results["smoke"] = success
    if output:
        for line in output.splitlines():
            print(line)

    # Summary
    print()
    print("=" * 50)
    print("Full Test Suite Summary")
    print("=" * 50)
    all_passed = True
    for name, passed in results.items():
        status = "PASS" if passed else "FAIL"
        print(f"  {name}: {status}")
        if not passed:
            all_passed = False

    return all_passed, ""


if __name__ == "__main__":
    sys.exit(main())