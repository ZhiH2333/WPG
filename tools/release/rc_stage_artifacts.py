#!/usr/bin/env python3
"""把正式命名的导出包改名为 RC 产物，并写 RC_BUILD_INFO.txt。"""

from __future__ import annotations

import argparse
import hashlib
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

from wpg_common import ARTIFACTS_DIR, PLATFORMS, emit, package_basename  # noqa: E402
from rc_common import RC_VERSION_RE, rc_package_name  # noqa: E402


def fail(message: str) -> int:
    emit("FAIL", message)
    return 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Stage RC artifacts")
    parser.add_argument("--version", required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--test-summary", default="")
    parser.add_argument("--notes", default="")
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    args = parse_args()
    version = args.version.strip()
    sha = args.sha.strip().lower()
    if RC_VERSION_RE.match(version) is None:
        return fail("RC 版本格式必须是 X.Y.Z-rc.N，收到：%s" % version)

    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
    staged: list[Path] = []
    for key in PLATFORMS:
        src = ARTIFACTS_DIR / package_basename(key, release=True)
        if not src.is_file():
            return fail("缺少正式命名产物：%s" % src.name)
        dst = ARTIFACTS_DIR / rc_package_name(version, key)
        if dst.exists():
            dst.unlink()
        src.replace(dst)
        staged.append(dst)
        emit("PASS", "staged %s" % dst.name)

    lines = ["%s  %s" % (sha256_file(path), path.name) for path in staged]
    checksums = ARTIFACTS_DIR / "SHA256SUMS.txt"
    checksums.write_text("\n".join(lines) + "\n", encoding="utf-8")
    emit("PASS", "SHA256SUMS.txt")

    info = ARTIFACTS_DIR / "RC_BUILD_INFO.txt"
    info.write_text(
        "\n".join(
            [
                "version=%s" % version,
                "git_sha=%s" % sha,
                "built_at_utc=%s"
                % datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "platforms=%s" % ",".join(PLATFORMS),
                "test_summary=%s" % args.test_summary.replace("\n", " ").strip(),
                "notes=%s" % args.notes.replace("\n", " ").strip(),
                "prerelease=true",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    emit("PASS", "RC_BUILD_INFO.txt")
    return 0


if __name__ == "__main__":
    sys.exit(main())
