#!/usr/bin/env python3
"""加载主场景，并运行仓库里已有的自动测试。没有额外测试时明确说明，不假装有测试。"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import LOG_DIR, ROOT, emit, emit_outcome, find_godot, run_cmd, Outcome  # noqa: E402


def automated_tests() -> list:
    found = []
    tests_dir = ROOT / "tests"
    if tests_dir.is_dir():
        found.extend(tests_dir.rglob("*.gd"))
    for path in ROOT.rglob("*_test.gd"):
        if path not in found:
            found.append(path)
    return sorted(found)


def main() -> int:
    godot = find_godot()
    if godot is None:
        emit_outcome(Outcome("FAIL", "Missing: Godot"))
        return 1
    script = ROOT / "tools/ci/smoke_load.gd"
    log_path = LOG_DIR / "smoke.log"
    proc = run_cmd(
        [
            str(godot),
            "--headless",
            "--path",
            str(ROOT),
            "--script",
            str(script),
            "--quit",
        ],
        log_path=log_path,
    )
    output = proc.stdout or ""
    if proc.returncode != 0 or "SMOKE_OK" not in output:
        emit_outcome(Outcome("FAIL", "Smoke Test 失败，日志：%s" % log_path))
        tail = "\n".join(output.splitlines()[-40:])
        if tail:
            print(tail)
        return 1
    emit("PASS", "Smoke Test（main_menu 可加载）")
    tests = automated_tests()
    if not tests:
        emit("INFO", "仓库没有 tests/ 或 *_test.gd，没有额外自动测试可跑")
        emit("PASS", "automated tests：0")
        return 0
    failures = []
    for test in tests:
        test_log = LOG_DIR / ("test-%s.log" % test.stem)
        test_proc = run_cmd(
            [
                str(godot),
                "--headless",
                "--path",
                str(ROOT),
                "--script",
                str(test),
                "--quit",
            ],
            log_path=test_log,
        )
        if test_proc.returncode != 0:
            failures.append(test.relative_to(ROOT).as_posix())
    if failures:
        emit("FAIL", "自动测试失败：%s" % ", ".join(failures))
        return 1
    emit("PASS", "automated tests：%d" % len(tests))
    return 0


if __name__ == "__main__":
    sys.exit(main())
