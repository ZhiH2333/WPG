#!/usr/bin/env python3
"""Netlify 的构建入口：装 Godot、导出 Web、复检产物。

Netlify 的 Git 集成在 `dev` 有新 commit 时执行这个脚本（见仓库根 `netlify.toml`），
它把 `build/web/raw` 当 publish 目录直接发成正式站，所以这里不碰任何 Netlify
凭据，也不需要 GitHub Actions。

本地复现同一条链路：

    python3 tools/deploy/netlify_build.py

为什么不直接写两条命令：`install_godot.py` 只会把编辑器路径写进 GitHub Actions 的
`GITHUB_ENV` / `GITHUB_PATH`。Netlify 上没有这两个变量，所以这里自己把路径接进
`GODOT_BIN`，并显式指定 Godot 的下载目录，免得落在不确定的临时目录里。
"""

from __future__ import annotations

import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import ROOT, Outcome, emit, emit_outcome, web_package_problem  # noqa: E402

INSTALL_SCRIPT = ROOT / "tools/ci/install_godot.py"
EXPORT_SCRIPT = ROOT / "tools/build/export_platform.py"
PUBLISH_DIR = ROOT / "build/web/raw"
# 编辑器与下载的压缩包放这里。必须在 build/ 下面（已在 .gitignore 里）。
GODOT_TEMP = ROOT / "build/netlify-godot"


def run_streaming(
    args: List[str], env: Optional[Dict[str, str]] = None
) -> Tuple[int, List[str]]:
    """边跑边把输出写进 Netlify 的部署日志，同时留一份给调用方解析。

    部署日志是 Netlify 上唯一能看到的东西，不能等好几分钟才一次性吐出来。
    """
    merged = os.environ.copy()
    if env:
        merged.update(env)
    print("+ %s" % " ".join(args), flush=True)
    proc = subprocess.Popen(
        args,
        cwd=str(ROOT),
        env=merged,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
    )
    lines: List[str] = []
    assert proc.stdout is not None
    for line in proc.stdout:
        print(line, end="", flush=True)
        lines.append(line.rstrip("\n"))
    return proc.wait(), lines


def find_installed_editor(lines: List[str]) -> Optional[Path]:
    """install_godot.py 最后会单独打一行编辑器绝对路径。"""
    for line in reversed(lines):
        candidate = Path(line.strip())
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def missing_from_ldd(text: str) -> List[str]:
    """从 `ldd` 输出里挑出 `=> not found` 的库名。"""
    missing = set()
    for line in text.splitlines():
        if "not found" not in line:
            continue
        name = line.split("=>")[0].strip()
        if name:
            missing.add(name)
    return sorted(missing)


def linux_lib_problem(godot: Path) -> Optional[str]:
    """Linux 上提前报告缺动态库。

    Netlify 的构建镜像不能 apt-get。缺库时 Godot 只会以
    "error while loading shared libraries" 死掉，日志很难读；这里先把名字列出来，
    省得去猜。
    """
    if platform.system() != "Linux" or shutil.which("ldd") is None:
        return None
    proc = subprocess.run(
        ["ldd", str(godot)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    missing = missing_from_ldd(proc.stdout or "")
    if not missing:
        return None
    return (
        "Godot 在这台机器上加载不了，缺动态库：%s。"
        "Netlify 的构建镜像不能 apt-get，需要换 Godot 的安装方式或者改回 GitHub Actions 构建。"
        % ", ".join(missing)
    )


def main() -> int:
    code, lines = run_streaming(
        [sys.executable, str(INSTALL_SCRIPT)], env={"RUNNER_TEMP": str(GODOT_TEMP)}
    )
    if code != 0:
        emit_outcome(Outcome("FAIL", "install_godot.py 失败（exit %s）" % code))
        return 1
    godot = find_installed_editor(lines)
    if godot is None:
        emit_outcome(Outcome("FAIL", "install_godot.py 没有输出可执行的 Godot 路径"))
        return 1
    emit("INFO", "Godot: %s" % godot)

    lib_problem = linux_lib_problem(godot)
    if lib_problem is not None:
        emit_outcome(Outcome("FAIL", lib_problem))
        return 1

    code, _ = run_streaming(
        [sys.executable, str(EXPORT_SCRIPT), "web"], env={"GODOT_BIN": str(godot)}
    )
    if code != 0:
        emit_outcome(Outcome("FAIL", "Web 导出失败（exit %s）" % code))
        return 1

    problem = web_package_problem(PUBLISH_DIR, prefix="Netlify publish 目录")
    if problem is not None:
        emit_outcome(Outcome("FAIL", problem))
        return 1
    files = [path for path in PUBLISH_DIR.rglob("*") if path.is_file()]
    total = sum(path.stat().st_size for path in files)
    emit_outcome(
        Outcome(
            "PASS",
            "Netlify publish 就绪：%s（%d 个文件，%.1f MB）"
            % (PUBLISH_DIR.relative_to(ROOT), len(files), total / 1048576.0),
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
