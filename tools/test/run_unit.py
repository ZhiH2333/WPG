#!/usr/bin/env python3
"""运行所有 unit tests。"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import LOG_DIR, ROOT, emit, find_godot, godot_log_args, run_cmd, Outcome  # noqa: E402


def discover_unit_tests() -> list:
    """发现 tests/unit/ 下的所有 *.gd 测试"""
    unit_dir = ROOT / "tests" / "unit"
    if not unit_dir.is_dir():
        return []
    return sorted(unit_dir.rglob("*.gd"))


def main() -> int:
    godot = find_godot()
    if godot is None:
        emit_outcome(Outcome("FAIL", "Missing: Godot"))
        return 1

    tests = discover_unit_tests()
    if not tests:
        emit("INFO", "没有发现 unit tests")
        return 0

    emit("INFO", f"发现 {len(tests)} 个 unit tests")

    failures = []
    for test in tests:
        test_log = LOG_DIR / f"unit-{test.stem}.log"
        proc = run_cmd(
            [
                str(godot),
                "--headless",
                "--path",
                str(ROOT),
                *godot_log_args(LOG_DIR / f"godot-unit-{test.stem}.log"),
                "--script",
                str(test),
            ],
            log_path=test_log,
            timeout=180,
        )
        output = proc.stdout or ""
        marker = _success_marker(output)
        if proc.returncode != 0 or marker is None:
            failures.append(test.relative_to(ROOT).as_posix())
            emit("FAIL", f"{test.relative_to(ROOT)}: {marker or 'no marker'}")
        else:
            emit("PASS", f"{test.relative_to(ROOT)}")

    if failures:
        emit("FAIL", f"Unit tests 失败: {len(failures)}/{len(tests)}")
        for f in failures:
            print(f"  {f}")
        return 1

    emit("PASS", f"All {len(tests)} unit tests passed")
    return 0


def _success_marker(output: str) -> str | None:
    for line in output.splitlines():
        token = line.strip()
        if token.endswith("_OK") and token.replace("_", "").isalnum():
            return token
    return None


if __name__ == "__main__":
    sys.exit(main())