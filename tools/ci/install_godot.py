#!/usr/bin/env python3
"""在 CI runner 上下载与仓库锁定的 Godot 4.6.2 编辑器和导出模板。"""

from __future__ import annotations

import os
import platform
import shutil
import stat
import sys
import zipfile
from pathlib import Path
from urllib.request import urlretrieve

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import GODOT_RELEASE_TAG, GODOT_TEMPLATE_DIR_NAME, emit  # noqa: E402


RELEASE_BASE = (
    "https://github.com/godotengine/godot/releases/download/%s" % GODOT_RELEASE_TAG
)


def editor_asset() -> str:
    system = platform.system()
    if system == "Linux":
        return "Godot_v4.6.2-stable_linux.x86_64.zip"
    if system == "Darwin":
        return "Godot_v4.6.2-stable_macos.universal.zip"
    if system == "Windows":
        return "Godot_v4.6.2-stable_win64.exe.zip"
    raise SystemExit("[FAIL] 不支持的 CI 系统：%s" % system)


def install_root() -> Path:
    root = os.environ.get("RUNNER_TEMP") or os.environ.get("TMPDIR") or "/tmp"
    return Path(root) / "wpg-godot"


def template_dir() -> Path:
    system = platform.system()
    if system == "Darwin":
        base = Path.home() / "Library/Application Support/Godot/export_templates"
    elif system == "Windows":
        base = Path(os.environ["APPDATA"]) / "Godot/export_templates"
    else:
        base = Path.home() / ".local/share/godot/export_templates"
    return base / GODOT_TEMPLATE_DIR_NAME


def download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    emit("INFO", "下载 %s" % url)
    urlretrieve(url, destination)


def make_executable(path: Path) -> None:
    mode = path.stat().st_mode
    path.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def install_editor(root: Path) -> Path:
    asset = editor_asset()
    archive = root / asset
    download("%s/%s" % (RELEASE_BASE, asset), archive)
    extract = root / "editor"
    if extract.exists():
        shutil.rmtree(extract)
    extract.mkdir(parents=True)
    with zipfile.ZipFile(archive) as zipped:
        zipped.extractall(extract)
    system = platform.system()
    if system == "Darwin":
        binary = next(extract.rglob("Godot"))
    elif system == "Windows":
        binary = next(extract.glob("*.exe"))
    else:
        binary = next(path for path in extract.iterdir() if path.is_file())
    make_executable(binary)
    return binary


def extract_templates(archive: Path, destination: Path) -> None:
    """官方 .tpz 的文件在 templates/ 下面，Godot 要的是版本目录里直接放 version.txt。"""
    with zipfile.ZipFile(archive) as zipped:
        names = [name for name in zipped.namelist() if not name.endswith("/")]
        if "templates/version.txt" in names:
            prefix = "templates/"
        elif "version.txt" in names:
            prefix = ""
        else:
            sample = "\n".join(names[:40])
            raise SystemExit(
                "[FAIL] 导出模板压缩包里没有 version.txt。包内前若干项：\n%s" % sample
            )
        for info in zipped.infolist():
            name = info.filename
            if name.endswith("/") or not name.startswith(prefix):
                continue
            relative = name[len(prefix):]
            if not relative:
                continue
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with zipped.open(info) as source, target.open("wb") as output:
                shutil.copyfileobj(source, output)


def install_templates() -> None:
    root = install_root()
    archive = root / "templates.tpz"
    download("%s/Godot_v4.6.2-stable_export_templates.tpz" % RELEASE_BASE, archive)
    destination = template_dir()
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    extract_templates(archive, destination)
    version_file = destination / "version.txt"
    if not version_file.is_file():
        raise SystemExit("[FAIL] 导出模板解压后没有 version.txt：%s" % destination)
    emit("PASS", "Export Templates -> %s" % destination)


def main() -> int:
    root = install_root()
    root.mkdir(parents=True, exist_ok=True)
    binary = install_editor(root)
    install_templates()
    github_env = os.environ.get("GITHUB_ENV")
    if github_env:
        with open(github_env, "a", encoding="utf-8") as handle:
            handle.write("GODOT_BIN=%s\n" % binary)
    github_path = os.environ.get("GITHUB_PATH")
    if github_path:
        with open(github_path, "a", encoding="utf-8") as handle:
            handle.write(str(binary.parent) + "\n")
    emit("PASS", "Godot -> %s" % binary)
    print(binary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
