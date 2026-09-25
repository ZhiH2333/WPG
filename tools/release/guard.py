#!/usr/bin/env python3
"""正式 Release 守门。不通过就非 0，后面的构建和发布都不会跑。"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import (  # noqa: E402
    PRESETS,
    TAG_RE,
    emit,
    git_output,
    preset_exists,
    read_project_version,
    version_is_valid,
)


def fail(message: str) -> int:
    emit("FAIL", message)
    return 1


def main() -> int:
    ref_name = os.environ.get("GITHUB_REF_NAME", "").strip()
    if not ref_name:
        code, ref_name = git_output(["describe", "--tags", "--exact-match"])
        if code != 0:
            return fail("当前没有 Git tag")
    if TAG_RE.match(ref_name) is None:
        return fail("Tag 格式必须是 vX.Y.Z，收到：%s" % ref_name)
    tag_version = ref_name[1:]
    code, head = git_output(["rev-parse", "HEAD"])
    if code != 0:
        return fail("无法解析 HEAD")
    fetch = subprocess.run(
        ["git", "fetch", "origin", "main"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if fetch.returncode != 0:
        emit("FAIL", "无法 fetch origin/main")
        print(fetch.stdout or "")
        return 1
    code, main_head = git_output(["rev-parse", "origin/main"])
    if code != 0:
        return fail("无法解析 origin/main")
    if head != main_head:
        return fail("tag commit != main HEAD（%s != %s）" % (head, main_head))
    emit("PASS", "tag commit == main HEAD")
    version = read_project_version()
    if version is None:
        return fail("project.godot 没有 application/config/version")
    if not version_is_valid(version):
        return fail("project.godot 版本格式不对：%s" % version)
    if version != tag_version:
        return fail("Tag %s 与 project.godot %s 不一致" % (ref_name, version))
    emit("PASS", "version %s" % version)
    for key, name in PRESETS.items():
        if not preset_exists(key):
            return fail("export preset 缺失：%s" % name)
    emit("PASS", "export presets")
    ci = subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / "ci" / "run_ci.py")])
    if ci.returncode != 0:
        return fail("WPG CI checks 未通过")
    emit("PASS", "Release Guard")
    return 0


if __name__ == "__main__":
    sys.exit(main())
