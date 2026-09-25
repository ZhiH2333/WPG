#!/usr/bin/env python3
"""为正式 Release 的 5 个包生成 SHA256SUMS.txt。缺任何一个就失败。"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import ARTIFACTS_DIR, PLATFORMS, emit, package_basename, write_sha256sums  # noqa: E402


def main() -> int:
    paths = []
    for platform_key in PLATFORMS:
        path = ARTIFACTS_DIR / package_basename(platform_key, release=True)
        if not path.is_file() or path.stat().st_size == 0:
            emit("FAIL", "缺少正式包：%s" % path.name)
            return 1
        paths.append(path)
        emit("PASS", path.name)
    destination = ARTIFACTS_DIR / "SHA256SUMS.txt"
    write_sha256sums(paths, destination)
    emit("PASS", destination.name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
