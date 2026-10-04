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
    game_category_outcome,
    package_basename,
    platform_prereq,
    run_cmd,
    web_package_problem,
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
    """导出后、注入 favicon 之前的第一道检查，判断在 wpg_common。"""
    problem = web_package_problem(folder)
    if problem is not None:
        return Outcome("FAIL", problem)
    files = [path for path in folder.rglob("*") if path.is_file()]
    return Outcome("PASS", "Web package 文件数 %d" % len(files))


def apply_web_theme_icons(folder: Path) -> Outcome:
    """给 Web 包补上跟随深浅色的 favicon。

    Godot 只按 `application/config/icon` 写一份 `<name>.icon.png`（浅色）。这里把
    `icons/web/favicon-light.png` / `favicon-dark.png` 放进包内，并在 <head> 里加
    带 `prefers-color-scheme` 的 <link>，浏览器标签页就会跟着系统深浅色切换。
    """
    index = folder / "index.html"
    if not index.is_file():
        return Outcome("FAIL", "Web 导出缺少 index.html")
    source = ROOT / "icons" / "web"
    light = source / "favicon-light.png"
    dark = source / "favicon-dark.png"
    missing = [path.name for path in (light, dark) if not path.is_file()]
    if missing:
        return Outcome(
            "FAIL",
            "缺少 %s，请先运行 python3 tools/icons/generate_icons.py" % ", ".join(missing),
        )
    shutil.copy2(light, folder / light.name)
    shutil.copy2(dark, folder / dark.name)

    html = index.read_text(encoding="utf-8")
    if dark.name in html:
        return Outcome("PASS", "Web 深浅色 favicon 已就绪")
    if "</head>" not in html:
        return Outcome("FAIL", "index.html 没有 </head>，无法注入深浅色 favicon")
    links = (
        '<link rel="icon" type="image/png" href="%s" media="(prefers-color-scheme: light)">\n' % light.name
        + '<link rel="icon" type="image/png" href="%s" media="(prefers-color-scheme: dark)">\n' % dark.name
    )
    index.write_text(html.replace("</head>", links + "</head>", 1), encoding="utf-8")
    return Outcome("PASS", "Web 深浅色 favicon 已注入")


def apply_linux_game_entry(folder: Path) -> Outcome:
    """给 Linux 包写 .desktop，让启动器把它归到 Games。

    Linux 没有 APK 那种 `isGame` 标志；桌面环境靠 `.desktop` 的
    `Categories=Game;` 决定“游戏”归类与手柄相关行为，所以这里补一份。
    """
    binary = folder / "WPG.x86_64"
    if not binary.is_file():
        candidates = [
            path for path in folder.iterdir() if path.is_file() and path.suffix != ".pck"
        ]
        if not candidates:
            return Outcome("FAIL", "Linux 导出目录找不到可执行文件")
        binary = candidates[0]
    binary.chmod(binary.stat().st_mode | 0o755)
    entry = folder / "WPG.desktop"
    entry.write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=WPG\n"
        "Comment=WPG - Game\n"
        "Exec=%s\n"
        "Icon=wpg\n"
        "Terminal=false\n"
        "Categories=Game;\n"
        "Keywords=game;\n" % binary.name,
        encoding="utf-8",
    )
    return Outcome("PASS", "Linux .desktop 已写入 Categories=Game;")


def apply_web_game_markers(folder: Path) -> Outcome:
    """给 Web 包补上游戏相关的 meta 标记。

    部分浏览器 / 启动器（尤其是移动端“添加到主屏幕”）靠这些标记判断网页是不是
    游戏，缺失时不会进入游戏模式。
    """
    index = folder / "index.html"
    if not index.is_file():
        return Outcome("FAIL", "Web 导出缺少 index.html")
    html = index.read_text(encoding="utf-8")
    if "wpg-game-markers" in html:
        return Outcome("PASS", "Web 游戏标记已就绪")
    if "</head>" not in html:
        return Outcome("FAIL", "index.html 没有 </head>，无法注入游戏标记")
    markers = (
        "<!-- wpg-game-markers -->\n"
        '<meta name="application-name" content="WPG">\n'
        '<meta name="apple-mobile-web-app-capable" content="yes">\n'
        '<meta name="mobile-web-app-capable" content="yes">\n'
        '<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">\n'
        '<meta name="apple-mobile-web-app-title" content="WPG">\n'
        '<meta name="theme-color" content="#1f1f24">\n'
        '<meta property="og:type" content="game">\n'
        '<meta name="description" content="WPG - Game">\n'
    )
    index.write_text(html.replace("</head>", markers + "</head>", 1), encoding="utf-8")
    return Outcome("PASS", "Web 游戏标记已注入")


def main() -> int:
    args = parse_args()
    platform_key = args.platform
    prereq = platform_prereq(platform_key)
    if prereq.status != "PASS":
        emit_outcome(prereq)
        return prereq.exit_code
    category = game_category_outcome()
    emit_outcome(category)
    if category.status != "PASS":
        return category.exit_code
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
        theme = apply_web_theme_icons(raw)
        emit_outcome(theme)
        if theme.status != "PASS":
            return theme.exit_code
        markers = apply_web_game_markers(raw)
        emit_outcome(markers)
        if markers.status != "PASS":
            return markers.exit_code
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
        if platform_key == "linux":
            entry = apply_linux_game_entry(raw)
            emit_outcome(entry)
            if entry.status != "PASS":
                return entry.exit_code
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
