#!/usr/bin/env python3
"""Dev CD aggregate：生成 SHA256SUMS 与 manifest.json。

    python3 tools/build/dev_meta.py [--sha <完整 sha>] [--branch <分支>]

前置条件：六个平台的包都已经在 artifacts/ 里（aggregate job 用 download-artifact
把六个唯一 artifact 合并进来）。缺任何一个、或者 --sha 和实际 checkout 对不上，
都非 0 退出——绝不生成「少一个平台也照样绿」的 checksum。

只写工作区里的 artifacts/，不创建 Release、不打 tag、不 commit、不 push。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import (  # noqa: E402
    ARTIFACTS_DIR,
    DEV_PLATFORMS,
    EXIT_FAIL,
    EXIT_PASS,
    GODOT_VERSION,
    dev_build_prefix,
    dev_checksums_name,
    dev_commit_date,
    dev_manifest_name,
    dev_package_basename,
    dev_short_sha,
    emit,
    git_branch,
    git_commit,
    read_branch_or_env,
    sha256_file,
    write_sha256sums,
)


def collect(prefix: str) -> List[Path]:
    paths: List[Path] = []
    failed = False
    for platform_key in DEV_PLATFORMS:
        path = ARTIFACTS_DIR / dev_package_basename(platform_key)
        if not path.is_file() or path.stat().st_size == 0:
            emit("FAIL", "缺少 Dev 包：%s" % path.name)
            failed = True
            continue
        emit("PASS", path.name)
        paths.append(path)
    if failed:
        return []
    return paths


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sha", default="", help="预期的完整 commit SHA（与实际 checkout 比对）")
    parser.add_argument("--branch", default="", help="分支名；留空则读 WPG_DEV_BRANCH / git")
    args = parser.parse_args()

    commit = git_commit(short=False)
    if not commit or commit == "UNKNOWN":
        emit("FAIL", "读不到 commit SHA（需要在 git checkout 之后运行）")
        return EXIT_FAIL
    if args.sha and commit != args.sha:
        emit(
            "FAIL",
            "checkout 的 commit 与 CI commit 不一致：%s != %s" % (commit, args.sha),
        )
        return EXIT_FAIL

    short_commit = dev_short_sha(commit)
    commit_date = dev_commit_date(commit)
    branch = args.branch or read_branch_or_env()
    prefix = dev_build_prefix(commit_date, short_commit)

    if prefix != dev_build_prefix():
        emit("FAIL", "前缀不一致：%s != %s" % (prefix, dev_build_prefix()))
        return EXIT_FAIL

    emit("INFO", "Dev build prefix: %s" % prefix)

    paths = collect(prefix)
    if not paths:
        emit("FAIL", "Dev 六平台产物不完整，不生成 SHA256SUMS / manifest")
        return EXIT_FAIL

    sums = ARTIFACTS_DIR / dev_checksums_name()
    write_sha256sums(paths, sums)
    emit("PASS", sums.name)

    entries: List[Dict[str, object]] = []
    by_name = {path.name: path for path in paths}
    for platform_key in DEV_PLATFORMS:
        filename = dev_package_basename(platform_key)
        path = by_name[filename]
        entries.append(
            {
                "platform": platform_key,
                "filename": filename,
                "sha256": sha256_file(path),
                "size_bytes": path.stat().st_size,
            }
        )

    manifest = {
        "project": "WPG",
        "branch": branch,
        "commit": commit,
        "short_commit": short_commit,
        "commit_date": commit_date,
        "godot": GODOT_VERSION,
        "build_type": "dev",
        "platforms": entries,
    }
    manifest_path = ARTIFACTS_DIR / dev_manifest_name()
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    emit("PASS", manifest_path.name)
    emit("PASS", "Dev metadata（%d 个平台）" % len(entries))
    return EXIT_PASS


if __name__ == "__main__":
    sys.exit(main())
