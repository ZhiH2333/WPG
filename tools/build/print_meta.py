#!/usr/bin/env python3
"""给 GitHub Actions 写 artifact 名和包文件名。

    print_meta.py --prefix                 Dev CD prepare 用：输出 sha / 日期 / 前缀
    print_meta.py <platform>               Dev 命名：WPG_YYYYMMDD_7sha_<platform>.<ext>
    print_meta.py <platform> --release     正式 Release 命名：WPG-vX.Y.Z-<platform>.<ext>

Dev 前缀只算一次（prepare），再通过 WPG_DEV_BUILD_PREFIX 交给所有平台 job，
避免六个 job 各算各的日期 / 短 SHA。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import (  # noqa: E402
    PRESETS,
    dev_artifact_name,
    dev_build_prefix,
    dev_commit_date,
    dev_short_sha,
    git_commit,
    package_basename,
    read_branch_or_env,
)


def print_prefix() -> int:
    sha = git_commit(short=False)
    if not sha or sha == "UNKNOWN":
        print("[FAIL] 读不到 commit SHA（需要在 git checkout 之后运行）", file=sys.stderr)
        return 1
    short_sha = dev_short_sha(sha)
    commit_date = dev_commit_date(sha)
    branch = read_branch_or_env()
    prefix = dev_build_prefix(commit_date, short_sha)
    # 只有 name=value 进 stdout（会被重定向进 GITHUB_OUTPUT），状态行一律走 stderr。
    print("sha=%s" % sha)
    print("short_sha=%s" % short_sha)
    print("commit_date=%s" % commit_date)
    print("branch=%s" % branch)
    print("build_prefix=%s" % prefix)
    print("[PASS] Dev build prefix: %s（branch=%s）" % (prefix, branch), file=sys.stderr)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", nargs="?", choices=sorted(PRESETS.keys()))
    parser.add_argument("--release", action="store_true", help="使用正式 Release 文件名")
    parser.add_argument(
        "--prefix",
        action="store_true",
        help="输出 Dev CD prepare 需要的 sha / 日期 / branch / build_prefix",
    )
    args = parser.parse_args()

    if args.prefix:
        if args.platform:
            parser.error("--prefix 不接受 platform")
        return print_prefix()

    if args.platform is None:
        parser.error("需要指定 platform，或使用 --prefix")

    if args.release:
        artifact_name = "release-%s" % args.platform
    else:
        artifact_name = dev_artifact_name(args.platform)
    print("artifact_name=%s" % artifact_name)
    print("file_name=%s" % package_basename(args.platform, args.release))
    return 0


if __name__ == "__main__":
    sys.exit(main())
