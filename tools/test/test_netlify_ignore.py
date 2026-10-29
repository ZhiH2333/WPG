#!/usr/bin/env python3
"""校验 netlify.toml 的路径忽略覆盖关键游戏目录，且仍保留 preview 跳过。"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOML = ROOT / "netlify.toml"

REQUIRED_PATHS = [
    "project.godot",
    "ui",
    "arena",
    "lobby",
    "locale",
    "player",
    "weapons",
    "tools/deploy",
    "netlify.toml",
]


def main() -> int:
    text = TOML.read_text(encoding="utf-8")
    failures: list[str] = []
    if "deploy-preview" not in text:
        failures.append("缺少 deploy-preview 跳过")
    if "CACHED_COMMIT_REF" not in text:
        failures.append("缺少 CACHED_COMMIT_REF 路径 diff")
    if "git diff --quiet" not in text:
        failures.append("缺少 git diff --quiet 路径忽略")
    for path in REQUIRED_PATHS:
        if path not in text:
            failures.append("ignore 未覆盖: %s" % path)
    if "docs" in text and "docs/" in text.split("git diff")[-1]:
        # docs 不应出现在「触发构建」的路径列表里（出现在注释 OK）
        ignore_block = text.split("ignore", 1)[-1]
        # 粗检：ignore 命令列表里不应把 docs 当触发路径
        if "\n      docs\n" in ignore_block or "\n      docs/" in ignore_block:
            failures.append("docs 不应作为触发构建的路径")
    if failures:
        for item in failures:
            print("[FAIL]", item)
        return 1
    print("[PASS] Netlify ignore 覆盖关键路径且跳过 preview / docs-only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
