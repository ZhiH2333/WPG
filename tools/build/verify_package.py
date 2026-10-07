#!/usr/bin/env python3
"""导出结束后、上传 artifact 之前的产物校验。

不满足就非 0 退出 —— GitHub Actions 里绝不能出现「文件没生成但 workflow 还是绿的」。

    python3 tools/build/verify_package.py <platform> [--release]

校验内容：
  1. artifacts/ 里有对应的包，且非空
  2. zip / apk 结构合法
  3. 平台关键内容真的在里面（Web 有 index.html + wasm/js/pck，iOS 有 .app 和
     .xcodeproj，Windows 有 exe，macOS 有 Info.plist，Android 有 manifest）
"""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import (  # noqa: E402
    ARTIFACTS_DIR,
    EXIT_FAIL,
    EXIT_PASS,
    PRESETS,
    emit,
    package_basename,
    web_package_problem,
)


def open_zip(path: Path) -> Tuple[Optional[zipfile.ZipFile], Optional[str]]:
    if not zipfile.is_zipfile(path):
        return None, "%s 不是合法 zip" % path.name
    try:
        archive = zipfile.ZipFile(path)
    except zipfile.BadZipFile as error:
        return None, "%s zip 损坏：%s" % (path.name, error)
    bad = archive.testzip()
    if bad is not None:
        archive.close()
        return None, "%s 里有损坏条目：%s" % (path.name, bad)
    return archive, None


def has_suffix(names: List[str], suffix: str) -> bool:
    return any(name.endswith(suffix) for name in names)


def platform_problem(platform_key: str, names: List[str]) -> Optional[str]:
    if platform_key == "windows":
        if not has_suffix(names, ".exe"):
            return "Windows 包里没有 .exe"
    elif platform_key == "linux":
        if not has_suffix(names, ".x86_64") and not has_suffix(names, ".desktop"):
            return "Linux 包里没有可执行文件 / .desktop"
    elif platform_key == "macos":
        if not (has_suffix(names, "Contents/Info.plist") or has_suffix(names, "WPG.app/Info.plist")):
            return "macOS 包里没有 Contents/Info.plist"
    elif platform_key == "android":
        if "AndroidManifest.xml" not in names:
            return "APK 里没有 AndroidManifest.xml"
        if not has_suffix(names, ".dex") and not any(n.startswith("lib/") for n in names):
            return "APK 里没有 classes.dex / lib/，不是可安装的包"
    elif platform_key == "ios":
        if not has_suffix(names, "WPG.app/Info.plist"):
            return "iOS 包里没有 WPG.app/Info.plist（unsigned CI package 至少要有 .app）"
        if "WPG.xcodeproj/project.pbxproj" not in names:
            return "iOS 包里没有 WPG.xcodeproj/project.pbxproj"
    return None


def verify_web_zip(path: Path) -> Optional[str]:
    """解压后用 wpg_common.web_package_problem 复检：必须有 index.html + wasm/js/pck。"""
    work = Path(tempfile.mkdtemp(prefix="wpg-web-verify-"))
    try:
        with zipfile.ZipFile(path) as archive:
            archive.extractall(work)
        return web_package_problem(work, prefix="Web 包")
    except zipfile.BadZipFile as error:
        return "Web 包解压失败：%s" % error
    finally:
        shutil.rmtree(work, ignore_errors=True)


def verify(platform_key: str, release: bool) -> int:
    name = package_basename(platform_key, release)
    path = ARTIFACTS_DIR / name
    if not path.is_file():
        emit("FAIL", "缺少产物：%s" % path)
        return EXIT_FAIL
    size = path.stat().st_size
    if size <= 0:
        emit("FAIL", "产物为空：%s" % path)
        return EXIT_FAIL

    if path.suffix == ".zip":
        archive, problem = open_zip(path)
        if problem is not None:
            emit("FAIL", problem)
            return EXIT_FAIL
        names = archive.namelist()
        archive.close()
        if not names:
            emit("FAIL", "%s 是空 zip" % name)
            return EXIT_FAIL
        failure = platform_problem(platform_key, names)
        if failure is not None:
            emit("FAIL", "%s：%s" % (name, failure))
            return EXIT_FAIL
        if platform_key == "web":
            failure = verify_web_zip(path)
            if failure is not None:
                emit("FAIL", failure)
                return EXIT_FAIL
    elif path.suffix == ".apk":
        archive, problem = open_zip(path)
        if problem is not None:
            emit("FAIL", problem)
            return EXIT_FAIL
        names = archive.namelist()
        archive.close()
        failure = platform_problem("android", names)
        if failure is not None:
            emit("FAIL", "%s：%s" % (name, failure))
            return EXIT_FAIL
    else:
        emit("FAIL", "不认识的产物扩展名：%s" % name)
        return EXIT_FAIL

    emit("PASS", "%s（%d 字节）" % (name, size))
    return EXIT_PASS


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=sorted(PRESETS.keys()))
    parser.add_argument("--release", action="store_true")
    args = parser.parse_args()
    return verify(args.platform, args.release)


if __name__ == "__main__":
    sys.exit(main())
