#!/usr/bin/env python3
"""导出一个平台。成功把包放到 build/<platform>/ 和 artifacts/。

iOS 只做**本地 Personal Team development 构建**：
    Godot 导出 Xcode project
    → xcodebuild Automatic Signing 出 .app
    → -exportArchive 出 development .ipa
不实现也不暗示 App Store / TestFlight / Ad Hoc 分发。
"""

from __future__ import annotations

import argparse
import plistlib
import re
import shutil
import sys
import zipfile
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import (  # noqa: E402
    ARTIFACTS_DIR,
    BUILD_DIR,
    EXIT_BLOCKED,
    EXIT_FAIL,
    EXIT_PASS,
    EXPORT_PRESETS,
    IOS_CONFIGURATION_ALIASES,
    IOS_UNSUPPORTED_CONFIGURATIONS,
    LOG_DIR,
    PRESETS,
    ROOT,
    android_env,
    emit,
    emit_outcome,
    find_godot,
    game_category_outcome,
    ios_artifact_basename,
    ios_bundle_identifier,
    ios_preflight,
    ios_team_id,
    package_basename,
    platform_prereq,
    preset_index,
    preset_options,
    run_cmd,
    web_package_problem,
    zip_directory,
    IosCheck,
    Outcome,
)


class StageFailure(Exception):
    """带阶段名的失败：报告必须说清楚挂在哪一步。"""

    def __init__(self, stage: str, message: str, exit_code: int = EXIT_FAIL):
        super().__init__(message)
        self.stage = stage
        self.message = message
        self.exit_code = exit_code


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="导出一个 WPG 平台")
    parser.add_argument(
        "platform_arg",
        nargs="?",
        metavar="platform",
        choices=sorted({"windows", "macos", "linux", "android", "web", "ios"}),
        help="要导出的平台：windows / macos / linux / android / web / ios",
    )
    parser.add_argument(
        "--platform",
        dest="platform_opt",
        choices=sorted({"windows", "macos", "linux", "android", "web", "ios"}),
        help="同上，也可以写成 --platform ios",
    )
    parser.add_argument("--release", action="store_true", help="使用正式 Release 文件名")
    parser.add_argument("--check", action="store_true", help="只做环境检查（doctor），不导出（目前仅 ios）")
    parser.add_argument(
        "--configuration",
        default="development",
        help="iOS 构建目标，只支持 development/debug（默认 development）；不支持 release/distribution",
    )
    parser.add_argument(
        "--project-only",
        action="store_true",
        help="iOS：只生成 Xcode project，不编译、不签名",
    )
    args = parser.parse_args()
    if args.platform_arg and args.platform_opt and args.platform_arg != args.platform_opt:
        parser.error("位置参数与 --platform 冲突：%s vs %s" % (args.platform_arg, args.platform_opt))
    args.platform = args.platform_opt or args.platform_arg
    if args.platform is None:
        parser.error("需要指定 platform，例如：python tools/build/export_platform.py ios")
    if args.check and args.platform != "ios":
        parser.error("--check 目前只支持 ios")
    if args.project_only and args.platform != "ios":
        parser.error("--project-only 目前只支持 ios")
    if args.platform == "ios" and args.release:
        parser.error(
            "ios 只支持本地 development 构建，不提供 release/distribution 命名（免费 Personal Team 没有分发签名）"
        )
    if args.platform != "ios" and args.configuration != "development":
        parser.error("--configuration 目前只对 ios 有效")
    return args


def export_binary_name(platform_key: str) -> str:
    if platform_key == "windows":
        return "WPG.exe"
    if platform_key == "linux":
        return "WPG.x86_64"
    if platform_key == "macos":
        return "WPG.app"
    if platform_key == "android":
        return "WPG.apk"
    if platform_key == "ios":
        return "WPG.app"
    if platform_key == "web":
        return "index.html"
    raise ValueError("未知平台：%s" % platform_key)


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


# ===========================================================================
# iOS：本地 Personal Team development 构建
# ===========================================================================
SIGNING_ERROR_MARKERS = (
    "No Account for Team",
    "No profiles for",
    "requires a provisioning profile",
    "Provisioning profile",
    "Signing for",
    "Signing requires",
    "CSSMERR",
    "errSecInternalComponent",
    "no identity found",
    "DEVELOPMENT_TEAM",
    "communication with Apple failed",
    "unable to build chain",
)


def print_ios_checks(checks: Sequence[IosCheck]) -> None:
    for check in checks:
        if check.ok:
            emit("PASS", "%s: %s" % (check.label, check.detail) if check.detail else check.label)
            for note in check.notes:
                emit("INFO", note)
        else:
            emit("FAIL", check.message)
            for note in check.notes:
                emit("INFO", note)


def normalize_ios_configuration(raw: str) -> str:
    value = (raw or "development").strip().lower()
    if value in IOS_UNSUPPORTED_CONFIGURATIONS:
        raise StageFailure(
            "环境检查",
            "IOS_EXPORT_BLOCKED: 本阶段只支持 development（免费 Personal Team 本地构建），"
            "不实现 %s 分发。" % value,
            EXIT_BLOCKED,
        )
    if value not in IOS_CONFIGURATION_ALIASES:
        raise StageFailure(
            "环境检查",
            "IOS_EXPORT_BLOCKED: 未知 --configuration %r，可选 development/debug" % raw,
            EXIT_BLOCKED,
        )
    return IOS_CONFIGURATION_ALIASES[value]


def begin_ios_project_only_export() -> Tuple[bytes, bool]:
    """临时把 iOS preset 的 export_project_only 改成 true，返回 (原始字节, 是否改动)。

    preset 正式值保持 false（Godot GUI 仍然可以整包导出）。命令行要走
    「Godot 只出 Xcode project → xcodebuild 负责编译签名」这条链，所以这里临时改，
    结束后按原始字节写回并校验。不会改 bundle id，也不会留下中间状态。
    """
    original = EXPORT_PRESETS.read_bytes()
    index = preset_index("ios")
    if index is None:
        return original, False
    text = original.decode("utf-8")
    lines = text.splitlines(keepends=True)
    header = "[preset.%s.options]" % index
    start = next((i for i, line in enumerate(lines) if line.strip() == header), None)
    if start is None:
        return original, False
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
    changed = False
    for i in range(start, end):
        if lines[i].startswith("application/export_project_only="):
            lines[i] = "application/export_project_only=true\n"
            changed = True
            break
    if not changed:
        return original, False
    EXPORT_PRESETS.write_text("".join(lines), encoding="utf-8")
    return original, True


def end_ios_project_only_export(original: bytes) -> bool:
    EXPORT_PRESETS.write_bytes(original)
    return EXPORT_PRESETS.read_bytes() == original


def detect_scheme(xcodeproj: Path) -> str:
    proc = run_cmd(["xcodebuild", "-project", str(xcodeproj), "-list"])
    text = proc.stdout or ""
    match = re.search(r"Schemes:\s*\n((?:\s+\S+\n?)+)", text)
    if match:
        schemes = [line.strip() for line in match.group(1).splitlines() if line.strip()]
        if schemes:
            return schemes[0]
    return xcodeproj.stem


def show_build_settings(xcodeproj: Path, log_path: Path) -> Dict[str, List[str]]:
    proc = run_cmd(["xcodebuild", "-project", str(xcodeproj), "-showBuildSettings"], log_path=log_path)
    settings: Dict[str, List[str]] = {}
    if proc.returncode != 0:
        raise StageFailure(
            "Xcode configure",
            "xcodebuild -showBuildSettings 失败，日志：%s\n%s" % (log_path, _tail(proc.stdout)),
        )
    for line in (proc.stdout or "").splitlines():
        found = re.match(r"^\s*([A-Z0-9_]+) = (.*)$", line)
        if found:
            settings.setdefault(found.group(1), []).append(found.group(2).strip())
    return settings


def _tail(text: Optional[str], lines: int = 80) -> str:
    content = text or ""
    return "\n".join(content.splitlines()[-lines:])


def _looks_like_signing_error(text: Optional[str]) -> bool:
    content = text or ""
    return any(marker in content for marker in SIGNING_ERROR_MARKERS)


def write_development_export_options(path: Path, team_id: str) -> None:
    """xcodebuild -exportArchive 用的 development export options。

    只有 method=development / signingStyle=automatic，不写 provisioningProfiles、
    不写证书名、不写任何 Apple 凭据。
    """
    payload = {
        "method": "development",
        "teamID": team_id,
        "signingStyle": "automatic",
        "compileBitcode": False,
        "stripSwiftSymbols": True,
        "destination": "export",
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        plistlib.dump(payload, handle)


def verify_ios_app(app_path: Path, bundle_id: str, expect_team: str) -> Outcome:
    """真实校验 .app：结构 / Bundle ID / ARM64 / codesign，不接受“文件存在”就算过。"""
    if not app_path.is_dir():
        return Outcome("FAIL", ".app 不存在：%s" % app_path)
    info_path = app_path / "Info.plist"
    if not info_path.is_file():
        return Outcome("FAIL", "缺少 Info.plist：%s" % info_path)
    try:
        with info_path.open("rb") as handle:
            info = plistlib.load(handle)
    except Exception as error:  # noqa: BLE001 - 解析失败必须原样报告
        return Outcome("FAIL", "Info.plist 解析失败：%s（%s）" % (info_path, error))
    found_bundle = str(info.get("CFBundleIdentifier", ""))
    if found_bundle != bundle_id:
        return Outcome("FAIL", "CFBundleIdentifier 不一致：%s != %s" % (found_bundle, bundle_id))
    executable_name = str(info.get("CFBundleExecutable", ""))
    executable = app_path / executable_name if executable_name else None
    if executable is None or not executable.is_file():
        return Outcome("FAIL", "主可执行文件缺失（CFBundleExecutable=%r）" % executable_name)

    arch = run_cmd(["lipo", "-archs", str(executable)])
    arch_text = (arch.stdout or "").strip()
    if arch.returncode != 0 or not arch_text:
        file_probe = run_cmd(["file", str(executable)])
        arch_text = (file_probe.stdout or "").strip()
        if "arm64" not in arch_text:
            return Outcome("FAIL", "主程序架构不是 ARM64：%s" % arch_text)
    elif "arm64" not in arch_text.split():
        return Outcome("FAIL", "主程序架构不是 ARM64：%s" % arch_text)

    strict = run_cmd(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app_path)])
    if strict.returncode != 0:
        loose = run_cmd(["codesign", "--verify", "--verbose=4", str(app_path)])
        if loose.returncode != 0:
            return Outcome(
                "FAIL",
                "codesign --verify 失败：%s" % (loose.stdout or strict.stdout or "无输出").strip(),
            )

    detail = run_cmd(["codesign", "-d", "--verbose=2", str(app_path)])
    detail_text = detail.stdout or ""
    team_match = re.search(r"^TeamIdentifier=(\S+)", detail_text, re.MULTILINE)
    if team_match:
        signed_team = team_match.group(1)
        if expect_team and signed_team != expect_team:
            return Outcome(
                "FAIL",
                "签名 TeamIdentifier=%s，与 preset Team ID %s 不一致" % (signed_team, expect_team),
            )
    else:
        detail_text += "\n(codesign -d 没有 TeamIdentifier)"
    authority = re.findall(r"^Authority=(.+)$", detail_text, re.MULTILINE)

    profile_note = "未发现 embedded.mobileprovision"
    embedded = app_path / "embedded.mobileprovision"
    if embedded.is_file():
        decoded = run_cmd(["security", "cms", "-D", "-i", str(embedded)])
        if decoded.returncode == 0 and decoded.stdout:
            try:
                profile = plistlib.loads(decoded.stdout.encode("utf-8"))
                expiry = profile.get("ExpirationDate")
                team_ids = profile.get("TeamIdentifier") or profile.get("TeamIdentifier", [])
                profile_note = "embedded.mobileprovision team=%s 过期时间=%s get-task-allow=%s" % (
                    ",".join(team_ids) if isinstance(team_ids, list) else team_ids,
                    expiry,
                    profile.get("Entitlements", {}).get("get-task-allow"),
                )
                if expect_team and isinstance(team_ids, list) and expect_team not in team_ids:
                    return Outcome(
                        "FAIL",
                        "provisioning profile Team %s 与 preset Team ID %s 不一致"
                        % (",".join(team_ids), expect_team),
                    )
            except Exception as error:  # noqa: BLE001
                profile_note = "embedded.mobileprovision 解析失败：%s" % error
        else:
            profile_note = "embedded.mobileprovision 解码失败：%s" % (decoded.stdout or "").strip()

    return Outcome(
        "PASS",
        "%s | bundle=%s | arch=%s | codesign OK | %s"
        % (app_path.name, found_bundle, arch_text, profile_note),
    )


def verify_ios_ipa(ipa_path: Path, bundle_id: str, expect_team: str, work: Path) -> Outcome:
    """真实校验 development IPA：zip 合法性 + Payload/*.app + Bundle ID + 签名。"""
    if not ipa_path.is_file():
        return Outcome("FAIL", ".ipa 不存在：%s" % ipa_path)
    size = ipa_path.stat().st_size
    if size <= 0:
        return Outcome("FAIL", ".ipa 为空：%s" % ipa_path)
    if not zipfile.is_zipfile(ipa_path):
        return Outcome("FAIL", ".ipa 不是合法 zip：%s" % ipa_path)
    try:
        with zipfile.ZipFile(ipa_path) as archive:
            bad = archive.testzip()
            names = archive.namelist()
    except zipfile.BadZipFile as error:
        return Outcome("FAIL", ".ipa zip 损坏：%s" % error)
    if bad is not None:
        return Outcome("FAIL", ".ipa 里有损坏条目：%s" % bad)
    app_infos = [name for name in names if name.startswith("Payload/") and name.endswith(".app/Info.plist")]
    if not app_infos:
        return Outcome("FAIL", ".ipa 里没有 Payload/*.app/Info.plist（大小 %d 字节）" % size)

    extract_dir = work / "ipa-verify"
    if extract_dir.exists():
        shutil.rmtree(extract_dir)
    extract_dir.mkdir(parents=True, exist_ok=True)
    unzip = run_cmd(["unzip", "-q", "-o", str(ipa_path), "-d", str(extract_dir)])
    if unzip.returncode != 0:
        return Outcome("FAIL", "unzip 解压失败：%s" % _tail(unzip.stdout, 20))
    apps = sorted((extract_dir / "Payload").glob("*.app"))
    if not apps:
        shutil.rmtree(extract_dir, ignore_errors=True)
        return Outcome("FAIL", "解压后 Payload/ 下没有 .app")
    app_check = verify_ios_app(apps[0], bundle_id, expect_team)
    shutil.rmtree(extract_dir, ignore_errors=True)
    if app_check.status != "PASS":
        return Outcome("FAIL", "IPA 内 .app 校验失败：%s" % app_check.message)
    return Outcome(
        "PASS",
        "%s | %d 字节 | zip OK | Payload=%s | %s"
        % (ipa_path.name, size, apps[0].name, app_check.message),
    )


def package_ipa_from_app(app_path: Path, ipa_path: Path, log_path: Path) -> Outcome:
    """-exportArchive 不可用时的 development IPA 打包：把已签名的 .app 放进 Payload/。"""
    stage = ipa_path.parent / "ipa-fallback"
    if stage.exists():
        shutil.rmtree(stage)
    payload = stage / "Payload"
    payload.mkdir(parents=True, exist_ok=True)
    shutil.copytree(app_path, payload / app_path.name, symlinks=True)
    if ipa_path.exists():
        ipa_path.unlink()
    zip_proc = run_cmd(["zip", "-qry", str(ipa_path), "Payload"], cwd=stage, log_path=log_path)
    shutil.rmtree(stage, ignore_errors=True)
    if zip_proc.returncode != 0 or not ipa_path.is_file():
        return Outcome("FAIL", "development IPA 打包失败，日志：%s" % log_path)
    return Outcome("PASS", "development IPA 已从 xcarchive 打包：%s" % ipa_path.name)


def export_ios(args: argparse.Namespace) -> int:
    configuration = normalize_ios_configuration(args.configuration)
    checks = ios_preflight(configuration)
    print_ios_checks(checks)
    failing = [check for check in checks if not check.ok]
    signing_blocked = [check for check in failing if check.code == "IOS_SIGNING_BLOCKED"]
    other_blocked = [check for check in failing if check.code != "IOS_SIGNING_BLOCKED"]

    if args.check:
        if not failing:
            emit("PASS", "iOS doctor（%s）" % configuration)
            return EXIT_PASS
        emit("FAIL", "iOS doctor（%s）：%d 项未通过" % (configuration, len(failing)))
        return EXIT_BLOCKED if all(check.code.endswith("_BLOCKED") for check in failing) else EXIT_FAIL

    if other_blocked:
        emit("FAIL", "iOS 导出前置检查未通过，已停止（见上面的 [FAIL] 行）")
        return EXIT_BLOCKED
    if signing_blocked:
        emit(
            "INFO",
            "签名预检未通过。继续执行以便拿到 xcodebuild 的权威诊断；"
            "若签名确实不可用，最终会以非 0 退出，不会伪造成功。",
        )

    category = game_category_outcome()
    emit_outcome(category)
    if category.status != "PASS":
        return category.exit_code

    configuration_dir = BUILD_DIR / "ios" / configuration
    project_root = configuration_dir / "project"
    source_dir = project_root / "WPG"
    xcodeproj = project_root / "WPG.xcodeproj"
    archive_dir = configuration_dir / "archive"
    archive_path = archive_dir / "WPG.xcarchive"
    app_dir = configuration_dir / "app"
    ipa_dir = configuration_dir / "ipa"
    app_out = app_dir / ("WPG-ios-%s.app" % configuration)
    ipa_out = ipa_dir / ("WPG-ios-%s.ipa" % configuration)

    for folder in (configuration_dir, project_root, archive_dir, app_dir, ipa_dir):
        if folder.exists():
            shutil.rmtree(folder)
    for folder in (project_root, archive_dir, app_dir, ipa_dir):
        folder.mkdir(parents=True, exist_ok=True)

    team_id = ios_team_id()
    bundle_id = ios_bundle_identifier()
    godot = find_godot()
    assert godot is not None

    # ---- 阶段 1：Godot 导出 Xcode project --------------------------------
    emit("INFO", "阶段 1/5：Godot iOS export（只生成 Xcode project）")
    original_bytes, flipped = begin_ios_project_only_export()
    try:
        effective = preset_options("ios").get("application/export_project_only", "")
        if effective != "true":
            raise StageFailure(
                "Godot export",
                "无法把 export_project_only 临时置为 true（当前值 %r），"
                "拒绝继续：否则 Godot 会自己尝试签名构建，阶段边界会变模糊。" % effective,
                EXIT_BLOCKED,
            )
        emit("INFO", "export_project_only 临时置为 true，导出结束按原始字节恢复并校验")
        export_log = LOG_DIR / "export-ios.log"
        proc = run_cmd(
            [
                str(godot),
                "--headless",
                "--path",
                str(ROOT),
                "--export-debug",
                PRESETS["ios"],
                str(source_dir),
            ],
            log_path=export_log,
        )
    finally:
        restored = end_ios_project_only_export(original_bytes)
    if not restored:
        emit("FAIL", "export_presets.cfg 未按原始字节恢复，请立刻检查 git diff export_presets.cfg")
        return EXIT_FAIL
    pbxproj = xcodeproj / "project.pbxproj"
    if proc.returncode != 0 or not pbxproj.is_file():
        emit("FAIL", "阶段 Godot export：Xcode project 生成失败，日志：%s" % export_log)
        print(_tail(proc.stdout))
        return EXIT_FAIL
    emit("PASS", "Xcode project：%s" % xcodeproj.relative_to(ROOT))

    # ---- 阶段 2：Xcode signing 设置 --------------------------------------
    emit("INFO", "阶段 2/5：Xcode configure（Automatic Signing / Team ID / Bundle ID）")
    settings = show_build_settings(xcodeproj, LOG_DIR / "xcodebuild-ios-showsettings.log")
    for key, expected in (
        ("DEVELOPMENT_TEAM", team_id),
        ("CODE_SIGN_STYLE", "Automatic"),
        ("PRODUCT_BUNDLE_IDENTIFIER", bundle_id),
    ):
        values = settings.get(key, [])
        if not values:
            raise StageFailure(
                "Xcode configure",
                "xcodebuild 里读不到 %s（工程没有按预期配置）" % key,
                EXIT_BLOCKED,
            )
        mismatched = sorted({value for value in values if value != expected})
        if mismatched:
            raise StageFailure(
                "Xcode configure",
                "IOS_SIGNING_BLOCKED: %s 不符合预期：%s（期望 %s）"
                % (key, ", ".join(mismatched), expected),
                EXIT_BLOCKED,
            )
        emit("PASS", "%s = %s" % (key, expected))
    pinned_profiles = sorted({v for v in settings.get("PROVISIONING_PROFILE", []) if v})
    if pinned_profiles:
        emit("WARN", "工程里写死了 PROVISIONING_PROFILE=%s，本地构建应交给 Automatic Signing" % ",".join(pinned_profiles))
    else:
        emit("PASS", "PROVISIONING_PROFILE 为空（交给 Xcode Automatic Signing 管理）")

    if args.project_only:
        emit("PASS", "iOS Xcode project 已生成：%s" % xcodeproj.relative_to(ROOT))
        emit("INFO", "未编译、未签名（--project-only）。打开 WPG.xcodeproj 即可看到 Signing & Capabilities。")
        if signing_blocked:
            emit("INFO", "注意：签名预检仍未通过，直接 xcodebuild 会失败（见上面的 [FAIL] 行）。")
        return EXIT_PASS

    # ---- 阶段 3：xcodebuild archive --------------------------------------
    emit("INFO", "阶段 3/5：xcodebuild archive（development / Automatic Signing）")
    scheme = detect_scheme(xcodeproj)
    emit("INFO", "scheme = %s" % scheme)
    archive_log = LOG_DIR / "xcodebuild-ios-archive.log"
    if archive_path.exists():
        shutil.rmtree(archive_path)
    archive_proc = run_cmd(
        [
            "xcodebuild",
            "-project",
            str(xcodeproj),
            "-scheme",
            scheme,
            "-sdk",
            "iphoneos",
            "-configuration",
            "Debug",
            "-destination",
            "generic/platform=iOS",
            "archive",
            "-allowProvisioningUpdates",
            "-archivePath",
            str(archive_path),
        ],
        log_path=archive_log,
        timeout=3600,
    )
    if archive_proc.returncode != 0:
        output = archive_proc.stdout or ""
        print(_tail(output))
        signing = _looks_like_signing_error(output)
        raise StageFailure(
            "xcodebuild archive / signing",
            "%s，日志：%s" % (
                "IOS_SIGNING_BLOCKED: xcodebuild 归档失败（没有可用的 development 签名/Provisioning）"
                if signing
                else "xcodebuild archive 失败",
                archive_log,
            ),
            EXIT_BLOCKED if signing else EXIT_FAIL,
        )
    emit("PASS", "xcarchive：%s" % archive_path.relative_to(ROOT))

    # ---- 阶段 4：.app ----------------------------------------------------
    emit("INFO", "阶段 4/5：提取并校验 .app")
    archive_apps = sorted((archive_path / "Products" / "Applications").glob("*.app"))
    if not archive_apps:
        raise StageFailure("archive", "xcarchive 里没有 Products/Applications/*.app")
    emit("INFO", "xcarchive 内 .app：%s" % archive_apps[0])
    shutil.copytree(archive_apps[0], app_out, symlinks=True)
    app_check = verify_ios_app(app_out, bundle_id, team_id)
    if app_check.status != "PASS":
        raise StageFailure(".app 验证", app_check.message, EXIT_FAIL)
    emit("PASS", ".app：%s -> %s" % (app_out.relative_to(ROOT), app_check.message))

    # ---- 阶段 5：IPA -----------------------------------------------------
    emit("INFO", "阶段 5/5：生成 development .ipa")
    export_options = configuration_dir / ("exportOptions-%s.plist" % configuration)
    write_development_export_options(export_options, team_id)
    export_log = LOG_DIR / "xcodebuild-ios-export-ipa.log"
    export_proc = run_cmd(
        [
            "xcodebuild",
            "-exportArchive",
            "-archivePath",
            str(archive_path),
            "-exportPath",
            str(ipa_dir),
            "-exportOptionsPlist",
            str(export_options),
        ],
        log_path=export_log,
        timeout=1800,
    )
    produced = sorted(ipa_dir.glob("*.ipa"))
    if export_proc.returncode != 0 or not produced:
        print(_tail(export_proc.stdout))
        emit(
            "WARN",
            "xcodebuild -exportArchive 失败（日志：%s）。改用 xcarchive 里已签名的 .app "
            "直接打包 development IPA；这只是打包方式差异，签名仍然来自阶段 3。" % export_log,
        )
        fallback = package_ipa_from_app(app_out, ipa_out, LOG_DIR / "ios-ipa-fallback.log")
        if fallback.status != "PASS":
            emit("FAIL", "阶段 IPA export：%s" % fallback.message)
            return EXIT_BLOCKED if _looks_like_signing_error(export_proc.stdout) else EXIT_FAIL
        emit("WARN", "%s（来源：xcarchive 直接打包，不是 -exportArchive）" % fallback.message)
    else:
        if produced[0] != ipa_out:
            if ipa_out.exists():
                ipa_out.unlink()
            produced[0].rename(ipa_out)
        emit("PASS", ".ipa：%s" % ipa_out.relative_to(ROOT))

    ipa_check = verify_ios_ipa(ipa_out, bundle_id, team_id, configuration_dir)
    if ipa_check.status != "PASS":
        emit("FAIL", "阶段 IPA 验证：%s" % ipa_check.message)
        return EXIT_FAIL
    emit("PASS", ".ipa 验证：%s" % ipa_check.message)

    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
    artifact = ARTIFACTS_DIR / ios_artifact_basename(configuration, include_sha=True)
    shutil.copy2(ipa_out, artifact)
    emit("PASS", "ios development -> %s" % artifact.relative_to(ROOT))
    emit("INFO", "这是 development/testing IPA（Personal Team），不是 App Store / TestFlight 分发包。")
    if signing_blocked:
        emit(
            "INFO",
            "签名预检当时报 FAIL，但 xcodebuild 实测通过——预检需要修正（%s）"
            % signing_blocked[0].detail,
        )
        return EXIT_PASS
    return EXIT_PASS


def main() -> int:
    args = parse_args()
    platform_key = args.platform
    if platform_key == "ios":
        try:
            return export_ios(args)
        except StageFailure as failure:
            emit("FAIL", "阶段 %s：%s" % (failure.stage, failure.message))
            return failure.exit_code
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
