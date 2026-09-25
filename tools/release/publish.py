#!/usr/bin/env python3
"""五个正式包和 SHA256SUMS.txt 都在时，才创建 GitHub Release。"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import ARTIFACTS_DIR, PLATFORMS, TAG_RE, emit, package_basename, read_project_version  # noqa: E402


def main() -> int:
    if shutil.which("gh") is None:
        emit("FAIL", "Missing: gh")
        return 1
    ref_name = os.environ.get("GITHUB_REF_NAME", "").strip()
    version = read_project_version()
    if TAG_RE.match(ref_name) is None:
        emit("FAIL", "GITHUB_REF_NAME 不是 vX.Y.Z：%s" % ref_name)
        return 1
    if version is None or ref_name != "v%s" % version:
        emit("FAIL", "Tag 与 project.godot 不一致")
        return 1
    files = [ARTIFACTS_DIR / package_basename(key, release=True) for key in PLATFORMS]
    files.append(ARTIFACTS_DIR / "SHA256SUMS.txt")
    for path in files:
        if not path.is_file() or path.stat().st_size == 0:
            emit("FAIL", "不能发布，缺少 %s" % path.name)
            return 1
    notes = "\n".join(
        [
            "WPG %s" % ref_name,
            "",
            "Windows / macOS / Linux / Android APK / Web",
            "macOS 包未做 Apple signing / notarization。",
            "Android 在没有正式 keystore 时是 debug 签名 APK。",
        ]
    )
    command = [
        "gh",
        "release",
        "create",
        ref_name,
        "--title",
        ref_name,
        "--notes",
        notes,
        "--verify-tag",
    ]
    command.extend(str(path) for path in files)
    proc = subprocess.run(command)
    if proc.returncode != 0:
        emit("FAIL", "gh release create 失败，未保留半成功 Release")
        return proc.returncode
    emit("PASS", "GitHub Release %s" % ref_name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
