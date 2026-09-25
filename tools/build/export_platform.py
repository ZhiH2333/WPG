#!/usr/bin/env python3
"""导出一个平台。成功把包放到 build/<platform>/ 和 artifacts/。"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import (  # noqa: E402
    ARTIFACTS_DIR,
    BUILD_DIR,
    LOG_DIR,
    PRESETS,
    ROOT,
    android_env,
    emit,
    emit_outcome,
    find_godot,
    package_basename,
    platform_prereq,
    run_cmd,
    zip_directory,
    Outcome,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="导出一个 WPG 平台包")
    parser.add_argument("platform", choices=sorted(PRESETS.keys()))
    parser.add_argument("--release", action="store_true", help="使用正式 Release 文件名")
    return parser.parse_args()


def export_binary_name(platform_key: str) -> str:
    if platform_key == "windows":
        return "WPG.exe"
    if platform_key == "linux":
        return "WPG.x86_64"
    if platform_key == "macos":
        return "WPG.app"
    if platform_key == "android":
        return "WPG.apk"
    return "index.html"


def web_package_ok(folder: Path) -> Outcome:
    files = [path for path in folder.rglob("*") if path.is_file()]
    names = [path.name for path in files]
    if "index.html" not in names:
        return Outcome("FAIL", "Web 导出没有 index.html")
    extras = [name for name in names if name != "index.html"]
    if not extras:
        return Outcome("FAIL", "Web 导出只有 HTML，不是完整包")
    interesting = (".js", ".wasm", ".pck", ".png", ".icon", ".audio")
    if not any(name.endswith(interesting) or ".wasm" in name or ".pck" in name for name in names):
        return Outcome("FAIL", "Web 导出缺少 wasm/js/pck：%s" % ", ".join(names))
    return Outcome("PASS", "Web package 文件数 %d" % len(files))


def main() -> int:
    args = parse_args()
    platform_key = args.platform
    prereq = platform_prereq(platform_key)
    if prereq.status != "PASS":
        emit_outcome(prereq)
        return prereq.exit_code
    godot = find_godot()
    assert godot is not None
    work = BUILD_DIR / platform_key
    raw = work / "raw"
    if raw.exists():
        shutil.rmtree(raw)
    raw.mkdir(parents=True)
    binary_name = export_binary_name(platform_key)
    export_path = raw / binary_name
    log_path = LOG_DIR / ("export-%s.log" % platform_key)
    use_debug = platform_key == "android" and not os_release_keystore()
    mode = "--export-debug" if use_debug else "--export-release"
    if use_debug:
        emit("INFO", "Android 没有正式 keystore，使用 debug 签名 APK。密钥不会写入 Git。")
    env = android_env() if platform_key == "android" else None
    proc = run_cmd(
        [
            str(godot),
            "--headless",
            "--path",
            str(ROOT),
            mode,
            PRESETS[platform_key],
            str(export_path),
        ],
        env=env,
        log_path=log_path,
    )
    output = proc.stdout or ""
    if proc.returncode != 0:
        emit_outcome(Outcome("FAIL", "%s 导出失败，日志：%s" % (platform_key, log_path)))
        tail = "\n".join(output.splitlines()[-50:])
        if tail:
            print(tail)
        return 1
    package_name = package_basename(platform_key, args.release)
    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
    destination = ARTIFACTS_DIR / package_name
    if platform_key == "android":
        apk_files = list(raw.glob("*.apk"))
        if not apk_files:
            emit_outcome(Outcome("FAIL", "Android 导出没有生成 apk，日志：%s" % log_path))
            return 1
        shutil.copy2(apk_files[0], destination)
        shutil.copy2(destination, work / package_name)
    elif platform_key == "web":
        check = web_package_ok(raw)
        if check.status != "PASS":
            emit_outcome(check)
            return check.exit_code
        zip_directory(raw, destination)
        shutil.copy2(destination, work / package_name)
        emit_outcome(check)
    elif platform_key == "macos":
        app_dir = raw / "WPG.app"
        if not app_dir.is_dir():
            apps = list(raw.glob("*.app"))
            if not apps:
                emit_outcome(Outcome("FAIL", "macOS 导出没有 .app，日志：%s" % log_path))
                return 1
            app_dir = apps[0]
        zip_directory(app_dir, destination)
        shutil.copy2(destination, work / package_name)
    else:
        produced = [path for path in raw.iterdir() if path.is_file() or path.is_dir()]
        if not produced:
            emit_outcome(Outcome("FAIL", "%s 导出目录为空，日志：%s" % (platform_key, log_path)))
            return 1
        zip_directory(raw, destination)
        shutil.copy2(destination, work / package_name)
    if not destination.is_file() or destination.stat().st_size == 0:
        emit_outcome(Outcome("FAIL", "包文件为空：%s" % destination))
        return 1
    emit("PASS", "%s -> %s" % (platform_key, destination.relative_to(ROOT)))
    return 0


def os_release_keystore() -> bool:
    import os

    return bool(os.environ.get("WPG_ANDROID_KEYSTORE", "").strip())


if __name__ == "__main__":
    sys.exit(main())
