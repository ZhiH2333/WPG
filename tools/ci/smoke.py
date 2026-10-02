#!/usr/bin/env python3
"""加载主场景，并运行仓库里已有的自动测试。没有额外测试时明确说明，不假装有测试。"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import (  # noqa: E402
    LOG_DIR,
    ROOT,
    emit,
    emit_outcome,
    find_godot,
    godot_log_args,
    run_cmd,
    Outcome,
)


def automated_tests() -> list:
    found = []
    tests_dir = ROOT / "tests"
    if tests_dir.is_dir():
        found.extend(tests_dir.rglob("*.gd"))
    for path in ROOT.rglob("*_test.gd"):
        if path not in found:
            found.append(path)
    return sorted(found)


def import_project(godot: Path) -> int:
    """全新 checkout 没有 .godot/，必须先 import 生成 global_script_class_cache.cfg。
    否则所有 class_name 类型在 --script 运行时无法解析，测试会 parse error。
    smoke 是独立 job，不能依赖 validate job 的 import 产物。"""
    log_path = LOG_DIR / "smoke-import.log"
    proc = run_cmd(
        [
            str(godot),
            "--headless",
            "--path",
            str(ROOT),
            *godot_log_args(LOG_DIR / "godot-smoke-import.log"),
            "--import",
            "--quit",
        ],
        log_path=log_path,
    )
    output = proc.stdout or ""
    if proc.returncode != 0 or "SCRIPT ERROR" in output or "Parse Error" in output:
        emit_outcome(Outcome("FAIL", "Godot import 失败，日志：%s" % log_path))
        tail = "\n".join(output.splitlines()[-40:])
        if tail:
            print(tail)
        return 1
    emit("PASS", "Godot import")
    return 0


def main() -> int:
    godot = find_godot()
    if godot is None:
        emit_outcome(Outcome("FAIL", "Missing: Godot"))
        return 1
    if import_project(godot) != 0:
        return 1
    script = ROOT / "tools/ci/smoke_load.gd"
    log_path = LOG_DIR / "smoke.log"
    proc = run_cmd(
        [
            str(godot),
            "--headless",
            "--path",
            str(ROOT),
            *godot_log_args(LOG_DIR / "godot-smoke.log"),
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
                *godot_log_args(LOG_DIR / ("godot-test-%s.log" % test.stem)),
                "--script",
                str(test),
            ],
            log_path=test_log,
            timeout=180,
        )
        output = test_proc.stdout or ""
        # 测试必须自己打印 *_OK 成功标记。缺标记 = 脚本未真正跑完（parse error /
        # 提前退出），不能因为 Godot 退出码恰为 0 就当成通过，否则会掩盖 CI 失败。
        marker = _success_marker(output)
        if test_proc.returncode != 0 or marker is None:
            failures.append(test.relative_to(ROOT).as_posix())
    if failures:
        emit("FAIL", "自动测试失败：%s" % ", ".join(failures))
        return 1
    emit("PASS", "automated tests：%d" % len(tests))
    return 0


def _success_marker(output: str) -> str:
    for line in output.splitlines():
        token = line.strip()
        if token.endswith("_OK") and token.replace("_", "").isalnum():
            return token
    return None


if __name__ == "__main__":
    sys.exit(main())
