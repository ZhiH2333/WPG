#!/usr/bin/env python3
"""给 GitHub Actions 写 artifact 名和包文件名。"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import PRESETS, github_artifact_name, package_basename  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=sorted(PRESETS.keys()))
    parser.add_argument("--release", action="store_true")
    args = parser.parse_args()
    print("artifact_name=%s" % github_artifact_name(args.platform))
    print("file_name=%s" % package_basename(args.platform, args.release))
    return 0


if __name__ == "__main__":
    sys.exit(main())
