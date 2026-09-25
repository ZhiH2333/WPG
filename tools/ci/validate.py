#!/usr/bin/env python3
"""Godot headless import + 脚本 parse。失败返回非 0。"""

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
    godot_version_line,
    godot_version_ok,
    run_cmd,
    Outcome,
)


def collect_scripts() -> list:
    scripts = []
    for path in ROOT.rglob("*.gd"):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(".godot/") or rel.startswith("build/") or rel.startswith("artifacts/"):
            continue
        scripts.append(path)
    return sorted(scripts)


def main() -> int:
    godot = find_godot()
    if godot is None:
        emit_outcome(Outcome("FAIL", "Missing: Godot"))
        return 1
    version_line = godot_version_line(godot)
    if not godot_version_ok(version_line):
        emit_outcome(Outcome("FAIL", "Godot 版本不符：%s" % version_line))
        return 1
    emit("INFO", "Godot %s" % version_line)
    log_path = LOG_DIR / "validate-import.log"
    proc = run_cmd(
        [str(godot), "--headless", "--path", str(ROOT), "--import", "--quit"],
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
    failures = []
    for script in collect_scripts():
        check_log = LOG_DIR / "validate-check.log"
        check = run_cmd(
            [
                str(godot),
                "--headless",
                "--path",
                str(ROOT),
                "--check-only",
                "--script",
                str(script),
                "--quit",
            ],
            log_path=check_log,
        )
        text = check.stdout or ""
        if check.returncode != 0 or "Parse Error" in text or "SCRIPT ERROR" in text:
            failures.append(script.relative_to(ROOT).as_posix())
    if failures:
        emit_outcome(Outcome("FAIL", "脚本 parse 失败：%s" % ", ".join(failures)))
        return 1
    emit("PASS", "Godot parse（%d 个脚本）" % len(collect_scripts()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
