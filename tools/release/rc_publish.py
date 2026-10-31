#!/usr/bin/env python3
"""创建 GitHub Pre-release（prerelease=true）。不碰正式 vX.Y.Z Release。"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

from wpg_common import ARTIFACTS_DIR, PLATFORMS, TAG_RE, emit  # noqa: E402
from rc_common import RC_VERSION_RE, rc_package_name  # noqa: E402


def fail(message: str) -> int:
    emit("FAIL", message)
    return 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Publish WPG RC Pre-release")
    parser.add_argument("--version", required=True, help="RC 版本，例如 0.3.0-rc.1")
    parser.add_argument("--sha", required=True, help="构建用的完整 commit SHA")
    parser.add_argument("--notes", default="", help="简短 RC 变更说明")
    parser.add_argument("--test-summary", default="", help="测试结果摘要")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="只校验产物与参数，不调用 gh release create",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    version = args.version.strip()
    sha = args.sha.strip().lower()
    if RC_VERSION_RE.match(version) is None:
        return fail("RC 版本格式必须是 X.Y.Z-rc.N，收到：%s" % version)
    tag = version
    if TAG_RE.match(tag) is not None:
        return fail("RC tag 不得使用正式 vX.Y.Z 格式：%s" % tag)

    if shutil.which("gh") is None and not args.dry_run:
        return fail("Missing: gh")

    files: list[Path] = []
    for key in PLATFORMS:
        path = ARTIFACTS_DIR / rc_package_name(version, key)
        if not path.is_file() or path.stat().st_size == 0:
            return fail("不能发布，缺少 %s" % path.name)
        files.append(path)
    checksums = ARTIFACTS_DIR / "SHA256SUMS.txt"
    if not checksums.is_file() or checksums.stat().st_size == 0:
        return fail("不能发布，缺少 SHA256SUMS.txt")
    files.append(checksums)
    build_info = ARTIFACTS_DIR / "RC_BUILD_INFO.txt"
    if build_info.is_file():
        files.append(build_info)

    built_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    notes_lines = [
        "WPG Release Candidate **%s**" % version,
        "",
        "- Status: **pre-release**（非正式发布）",
        "- Git commit: `%s`" % sha,
        "- Built at (UTC): %s" % built_at,
        "- Platforms: Windows / macOS / Linux / Android APK / Web",
        "",
    ]
    if args.test_summary.strip():
        notes_lines.extend(["### Test results", args.test_summary.strip(), ""])
    if args.notes.strip():
        notes_lines.extend(["### Changes", args.notes.strip(), ""])
    notes_lines.extend(
        [
            "### Notes",
            "- 本包为 RC / 测试用途，不代表正式可用。",
            "- macOS 包未做 Apple signing / notarization。",
            "- Android 在没有正式 keystore 时是 debug 签名 APK。",
            "- 正式 Release 仍只通过 `vX.Y.Z` tag + main HEAD 保护流程发布。",
        ]
    )
    notes = "\n".join(notes_lines)

    if args.dry_run:
        emit("PASS", "dry-run：产物与参数校验通过（tag=%s, files=%d）" % (tag, len(files)))
        print(notes)
        return 0

    view = subprocess.run(
        ["gh", "release", "view", tag, "--json", "isPrerelease,url"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if view.returncode == 0:
        try:
            payload = json.loads(view.stdout or "{}")
        except json.JSONDecodeError:
            return fail("无法解析已有 Release 元数据：%s" % tag)
        if payload.get("isPrerelease") is False:
            return fail("已存在正式 Release %s，拒绝覆盖" % tag)
        delete = subprocess.run(["gh", "release", "delete", tag, "--yes"])
        if delete.returncode != 0:
            return fail("无法替换已有 Pre-release %s" % tag)

    command = [
        "gh",
        "release",
        "create",
        tag,
        "--title",
        "WPG %s" % version,
        "--notes",
        notes,
        "--prerelease",
        "--target",
        sha,
    ]
    command.extend(str(path) for path in files)
    proc = subprocess.run(command)
    if proc.returncode != 0:
        emit("FAIL", "gh release create 失败，未保留半成功 Release")
        return proc.returncode
    emit("PASS", "GitHub Pre-release %s (prerelease)" % tag)
    return 0


if __name__ == "__main__":
    sys.exit(main())
