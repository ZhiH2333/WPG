#!/usr/bin/env python3
"""按 Windows、macOS、Linux、Android、Web 顺序构建。任一不是 PASS 则整体失败。"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import EXIT_BLOCKED, PLATFORMS, emit  # noqa: E402


def status_from_code(code: int) -> str:
    if code == 0:
        return "PASS"
    if code == EXIT_BLOCKED:
        return "BLOCKED"
    return "FAIL"


def main() -> int:
    release_flag = "--release" in sys.argv[1:]
    python = sys.executable
    script = Path(__file__).resolve().parent / "export_platform.py"
    results = []
    for platform_key in PLATFORMS:
        print("", flush=True)
        print("== %s ==" % platform_key, flush=True)
        args = [python, str(script), platform_key]
        if release_flag:
            args.append("--release")
        proc = subprocess.run(args)
        results.append((platform_key, status_from_code(proc.returncode)))
    print("", flush=True)
    print("Build All Platforms", flush=True)
    failed = False
    for platform_key, status in results:
        emit(status, platform_key)
        if status != "PASS":
            failed = True
    if failed:
        emit("FAIL", "Build All Platforms")
        return 1
    emit("PASS", "Build All Platforms")
    return 0


if __name__ == "__main__":
    sys.exit(main())
