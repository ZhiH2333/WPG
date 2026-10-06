#!/usr/bin/env python3
"""按 Windows、macOS、Linux、Android、Web 顺序构建。任一不是 PASS 则整体失败。

`--platform ios` 可以单独跑本地 Personal Team development 构建；默认（不带
--platform）仍然只跑正式 Release 的五个平台，iOS 不进 stable release 流程。
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import EXIT_BLOCKED, PLATFORMS, PRESETS, emit  # noqa: E402


def status_from_code(code: int) -> str:
    if code == 0:
        return "PASS"
    if code == EXIT_BLOCKED:
        return "BLOCKED"
    return "FAIL"


def main() -> int:
    parser = argparse.ArgumentParser(description="构建 WPG 平台包")
    parser.add_argument("--release", action="store_true", help="使用正式 Release 文件名")
    parser.add_argument(
        "--platform",
        default="all",
        choices=["all", *sorted(PRESETS.keys())],
        help="默认 all = windows/macos/linux/android/web；ios 只做本地 development 构建",
    )
    args = parser.parse_args()
    platform_keys = PLATFORMS if args.platform == "all" else (args.platform,)
    python = sys.executable
    script = Path(__file__).resolve().parent / "export_platform.py"
    results = []
    for platform_key in platform_keys:
        print("", flush=True)
        print("== %s ==" % platform_key, flush=True)
        build_args = [python, str(script), platform_key]
        if args.release:
            build_args.append("--release")
        proc = subprocess.run(build_args)
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
