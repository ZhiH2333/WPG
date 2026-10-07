#!/usr/bin/env python3
"""WPG CI / Build / Release 共用底层。本地 Build Tools 与 GitHub Actions 都调用这里。"""

from __future__ import annotations

import hashlib
import os
import platform
import re
import shutil
import subprocess
import sys
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple


# Windows CI stdout/stderr 可能是 cp1252，导致中文日志触发 UnicodeEncodeError。
# 统一在进程启动时把标准流重配为 UTF-8（若已是 UTF-8 则幂等），
# 保证 emit() 里的中文在所有平台都能安全打印。
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    try:
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


ROOT = Path(__file__).resolve().parent.parent
PROJECT_GODOT = ROOT / "project.godot"
EXPORT_PRESETS = ROOT / "export_presets.cfg"
BUILD_DIR = ROOT / "build"
ARTIFACTS_DIR = ROOT / "artifacts"
LOG_DIR = BUILD_DIR / "logs"

GODOT_VERSION = "4.6.2"
GODOT_RELEASE_TAG = "4.6.2-stable"
GODOT_TEMPLATE_DIR_NAME = "4.6.2.stable"

# Godot 4.6 里 `package/app_category` 的枚举顺序：
# Accessibility,Audio,Game,Image,Maps,News,Productivity,Social,Video,Undefined
# 所以 Game 的索引是 2。注意导出后 AndroidManifest 里的 `android:appCategory`
# 会变成 0：Godot 的 _get_app_category_value() 把 APP_CATEGORY_GAME 映射到
# Android 自己的 GAME=0。用 apkanalyzer 看到 `appCategory="0"` 是正常的，
# 不是掉回了 Accessibility。
ANDROID_APP_CATEGORY_GAME = 2

# 三星 Game Launcher / Game Booster 等 OEM 游戏助手只靠 isGame/appCategory 不一定
# 会收录应用；官方 Game Mode API 要求的 android.game_mode_config 才是可靠信号。
GAME_MODE_CONFIG_XML = """<?xml version="1.0" encoding="UTF-8"?>
<!-- WPG: 让三星 Game Launcher / Game Booster 等 OEM 游戏助手识别为游戏。
     参考 https://developer.android.com/games/optimize/adpf/gamemode/gamemode-api -->
<game-mode-config xmlns:android="http://schemas.android.com/apk/res/android"
    android:supportsBatteryGameMode="true"
    android:supportsPerformanceGameMode="true" />
"""

GAME_MODE_META_DATA = """        <meta-data
            android:name="android.game_mode_config"
            android:resource="@xml/game_mode_config" />"""

GAME_CATEGORY_EXPECTATIONS: Dict[str, Tuple[str, str]] = {
    "android": ("package/app_category", "2"),
    "macos": ("application/app_category", "Games"),
    "ios": ("LSApplicationCategoryType", "public.app-category.games"),
}
VERSION_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
TAG_RE = re.compile(r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
VERSION_LINE_RE = re.compile(
    r'^(config/version=")([^"]*)(")\s*$',
    re.MULTILINE,
)

EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_BLOCKED = 2

PRESETS: Dict[str, str] = {
    "windows": "Windows Desktop",
    "macos": "macOS",
    "linux": "Linux",
    "android": "Android",
    "web": "Web",
    # iOS 只做**本地 Personal Team development 构建**，不进正式 Release 流程。
    "ios": "iOS",
}

# 正式 Release（GitHub Release / checksums / build_all）仍然只有这五个平台。
# iOS 刻意不放进 PLATFORMS：本地 development toolchain 与 distribution 语义无关，
# 混进去会让 stable release 误以为存在 iOS 分发产物。
PLATFORMS: Tuple[str, ...] = ("windows", "macos", "linux", "android", "web")

TEMPLATE_FILES: Dict[str, Tuple[str, ...]] = {
    "windows": ("windows_release_x86_64.exe",),
    "macos": ("macos.zip",),
    "linux": ("linux_release.x86_64",),
    "android": ("android_release.apk", "android_debug.apk"),
    "web": ("web_nothreads_release.zip", "web_release.zip"),
    "ios": ("ios.zip",),
}

WEB_PACKAGE_SUFFIXES: Tuple[str, ...] = (".wasm", ".js", ".pck")

# ---------------------------------------------------------------------------
# iOS 本地 development 构建的常量
# ---------------------------------------------------------------------------
# Apple Team ID：Xcode Personal Team。不是 Apple ID，也不是密码。
IOS_TEAM_ID_RE = re.compile(r"^[A-Z0-9]{10}$")
# reverse-DNS Bundle ID：只允许 A-Z a-z 0-9 . -
IOS_BUNDLE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$")
# Godot iOS 导出方式枚举：App Store,Development,Ad-Hoc,Enterprise
IOS_EXPORT_METHOD_DEVELOPMENT = "1"
IOS_PLACEHOLDER_BUNDLE_TOKENS: Tuple[str, ...] = (
    "example",
    "placeholder",
    "yourcompany",
    "yourdomain",
    "changeme",
    "sample",
    "acme",
    "bundleidentifier",
    "com.company",
    "org.godotengine",
)
IOS_CONFIGURATION_ALIASES: Dict[str, str] = {
    "development": "development",
    "ios-development": "development",
    "ios-dev": "development",
    "debug": "development",
    "ios-debug": "development",
}
# 明确拒绝把本地构建说成 distribution / release。
IOS_UNSUPPORTED_CONFIGURATIONS: Tuple[str, ...] = (
    "release",
    "distribution",
    "app-store",
    "appstore",
    "ad-hoc",
    "adhoc",
    "enterprise",
    "testflight",
    "ios-release",
    "ios-distribution",
)


@dataclass
class Outcome:
    status: str
    message: str

    @property
    def exit_code(self) -> int:
        if self.status == "PASS":
            return EXIT_PASS
        if self.status == "BLOCKED":
            return EXIT_BLOCKED
        return EXIT_FAIL


def use_color() -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    return sys.stdout.isatty()


def paint(kind: str, text: str) -> str:
    if not use_color():
        return text
    colors = {
        "PASS": "32",
        "FAIL": "31",
        "BLOCKED": "33",
        "INFO": "36",
        "WARN": "35",
    }
    code = colors.get(kind, "0")
    return "\033[%sm%s\033[0m" % (code, text)


def emit(kind: str, message: str) -> None:
    print("%s %s" % (paint(kind, "[%s]" % kind), message), flush=True)


def emit_outcome(outcome: Outcome) -> None:
    emit(outcome.status, outcome.message)


def run_cmd(
    args: Sequence[str],
    cwd: Optional[Path] = None,
    env: Optional[Dict[str, str]] = None,
    log_path: Optional[Path] = None,
    timeout: Optional[float] = None,
) -> subprocess.CompletedProcess:
    merged = os.environ.copy()
    if env:
        merged.update(env)
    try:
        proc = subprocess.run(
            list(args),
            cwd=str(cwd or ROOT),
            env=merged,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as expired:
        output = expired.stdout or ""
        if isinstance(output, bytes):
            output = output.decode("utf-8", "replace")
        proc = subprocess.CompletedProcess(list(args), 124, output)
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(proc.stdout or "", encoding="utf-8")
    return proc


def git_output(args: Sequence[str]) -> Tuple[int, str]:
    proc = run_cmd(["git", *args])
    return proc.returncode, (proc.stdout or "").strip()


def git_branch() -> str:
    code, text = git_output(["rev-parse", "--abbrev-ref", "HEAD"])
    if code != 0 or not text:
        return "UNKNOWN"
    return text


def git_commit(short: bool = True) -> str:
    args = ["rev-parse", "--short=7", "HEAD"] if short else ["rev-parse", "HEAD"]
    code, text = git_output(args)
    if code != 0 or not text:
        return "UNKNOWN"
    return text


def git_exact_tag() -> str:
    code, text = git_output(["describe", "--tags", "--exact-match"])
    if code != 0:
        return ""
    return text


def working_tree_dirty() -> bool:
    code, text = git_output(["status", "--porcelain"])
    if code != 0:
        return True
    return bool(text)


def read_project_version() -> Optional[str]:
    if not PROJECT_GODOT.is_file():
        return None
    text = PROJECT_GODOT.read_text(encoding="utf-8")
    match = VERSION_LINE_RE.search(text)
    if match is None:
        return None
    value = match.group(2).strip()
    if not value:
        return None
    return value


def version_is_valid(version: str) -> bool:
    return VERSION_RE.match(version) is not None


def tag_for_version(version: str) -> str:
    return "v%s" % version


def set_project_version(version: str) -> Outcome:
    if not version_is_valid(version):
        return Outcome("FAIL", "版本格式必须是 MAJOR.MINOR.PATCH，例如 0.4.0")
    if not PROJECT_GODOT.is_file():
        return Outcome("FAIL", "找不到 project.godot")
    text = PROJECT_GODOT.read_text(encoding="utf-8")
    match = VERSION_LINE_RE.search(text)
    if match is None:
        return Outcome("FAIL", "project.godot 里没有 application/config/version")
    updated = VERSION_LINE_RE.sub(
        lambda found: '%s%s%s' % (found.group(1), version, found.group(3)),
        text,
        count=1,
    )
    PROJECT_GODOT.write_text(updated, encoding="utf-8")
    read_back = read_project_version()
    if read_back != version:
        return Outcome("FAIL", "写回后读到的版本是 %s" % read_back)
    return Outcome("PASS", "Project Version: %s" % read_back)


def godot_candidates() -> List[Path]:
    found: List[Path] = []
    env_bin = os.environ.get("GODOT_BIN", "").strip()
    if env_bin:
        found.append(Path(env_bin))
    for name in ("godot", "godot4", "Godot"):
        which = shutil.which(name)
        if which:
            found.append(Path(which))
    mac_app = Path("/Applications/Godot.app/Contents/MacOS/Godot")
    if mac_app.is_file():
        found.append(mac_app)
    home = Path.home()
    found.extend(
        [
            home / "Applications/Godot.app/Contents/MacOS/Godot",
            Path("/usr/local/bin/godot"),
            Path("/usr/bin/godot"),
        ]
    )
    unique: List[Path] = []
    seen = set()
    for path in found:
        key = str(path)
        if key in seen:
            continue
        seen.add(key)
        unique.append(path)
    return unique


def godot_log_args(log_path: Path) -> List[str]:
    """把 Godot 自己的日志显式指到仓库内。

    Godot 默认把日志写到 user://logs（macOS 是 ~/Library/Application Support/Godot/
    app_userdata/<project>/logs）。在只允许写工作区的受限沙箱 / CI 容器里，日志轮转
    会因为无法建文件而崩溃（RotatedFileLogger::rotate_file 后 signal 11），表现为
    所有脚本 check 都失败但没有任何 parse error。显式指定日志路径避免这个假失败。
    必须用绝对路径：Godot 会把相对路径当作 user:// 下的路径。
    """
    resolved = log_path.resolve()
    resolved.parent.mkdir(parents=True, exist_ok=True)
    return ["--log-file", str(resolved)]


def find_godot() -> Optional[Path]:
    for path in godot_candidates():
        if path.is_file() and os.access(path, os.X_OK):
            return path
    return None


def godot_version_line(godot: Path) -> str:
    proc = run_cmd([str(godot), "--version"])
    if proc.returncode != 0:
        return ""
    return (proc.stdout or "").strip().splitlines()[0].strip()


def godot_version_ok(version_line: str) -> bool:
    return version_line.startswith(GODOT_VERSION)


def export_template_dir() -> Path:
    system = platform.system()
    if system == "Darwin":
        base = Path.home() / "Library/Application Support/Godot/export_templates"
    elif system == "Windows":
        appdata = os.environ.get("APPDATA", "")
        base = Path(appdata) / "Godot/export_templates" if appdata else Path()
    else:
        base = Path.home() / ".local/share/godot/export_templates"
    return base / GODOT_TEMPLATE_DIR_NAME


def templates_ready(platform_key: str) -> Outcome:
    folder = export_template_dir()
    if not folder.is_dir():
        return Outcome(
            "BLOCKED",
            "Export Templates 缺失：%s（需要 Godot %s）" % (folder, GODOT_VERSION),
        )
    required = TEMPLATE_FILES.get(platform_key, ())
    if required and not any((folder / name).is_file() for name in required):
        return Outcome(
            "BLOCKED",
            "缺少 %s 导出模板：%s" % (platform_key, ", ".join(required)),
        )
    return Outcome("PASS", "Export Templates: %s" % folder)


def web_package_problem(folder: Path, prefix: str = "Web 导出目录") -> Optional[str]:
    """检查一个 Web 导出目录能不能发布。返回 None 表示没问题。

    导出、Netlify 构建、手动发布共用这一个判断：宁可不上传，也不要把坏包或者
    空目录发成正式站。
    """
    if not folder.is_dir():
        return "%s不存在：%s" % (prefix, folder)
    files = [path for path in folder.rglob("*") if path.is_file()]
    names = [path.name for path in files]
    if "index.html" not in names:
        return "%s里没有 index.html：%s" % (prefix, folder)
    if not [name for name in names if name != "index.html"]:
        return "%s里只有 HTML，不是完整包：%s" % (prefix, folder)
    if not any(
        name.endswith(WEB_PACKAGE_SUFFIXES) or ".wasm" in name or ".pck" in name
        for name in names
    ):
        return "%s里缺少 wasm/js/pck：%s（%s）" % (prefix, ", ".join(sorted(names)), folder)
    return None


def preset_exists(platform_key: str) -> bool:
    if not EXPORT_PRESETS.is_file():
        return False
    text = EXPORT_PRESETS.read_text(encoding="utf-8")
    preset_name = PRESETS[platform_key]
    return ('name="%s"' % preset_name) in text and (
        'platform="%s"' % preset_name
    ) in text


# ---------------------------------------------------------------------------
# export_presets.cfg 解析（iOS toolchain 只读，不写回正式配置）
# ---------------------------------------------------------------------------
def _preset_section_bounds(text: str, header_pattern: str) -> Optional[Tuple[int, int]]:
    """返回某个 [preset.N...] 段落在文本里的 (start, end)，找不到返回 None。"""
    match = re.search(header_pattern, text, re.MULTILINE)
    if match is None:
        return None
    start = match.start()
    nxt = re.search(r"^\[", text[match.end() :], re.MULTILINE)
    end = match.end() + nxt.start() if nxt else len(text)
    return start, end


def preset_index(platform_key: str) -> Optional[str]:
    """返回 preset 序号（例如 iOS 是 "5"）。找不到 preset 返回 None。"""
    if not EXPORT_PRESETS.is_file():
        return None
    text = EXPORT_PRESETS.read_text(encoding="utf-8")
    preset_name = PRESETS[platform_key]
    for match in re.finditer(r"^\[preset\.(\d+)\]\s*$", text, re.MULTILINE):
        bounds = _preset_section_bounds(text, r"^\[preset\.%s\]\s*$" % match.group(1))
        if bounds is None:
            continue
        body = text[bounds[0] : bounds[1]]
        if 'name="%s"' % preset_name in body:
            return match.group(1)
    return None


def _parse_cfg_options(body: str) -> Dict[str, str]:
    """解析 Godot 的 preset options 段。多行字符串值（引号未闭合）会继续收集。"""
    options: Dict[str, str] = {}
    key: Optional[str] = None
    chunks: List[str] = []
    for line in body.splitlines():
        if key is None:
            found = re.match(r"^([A-Za-z0-9_./-]+)=(.*)$", line)
            if found is None:
                continue
            key, value = found.group(1), found.group(2)
            if value.startswith('"') and not (len(value) >= 2 and value.endswith('"')):
                chunks = [value]
                continue
            options[key] = value[1:-1] if value.startswith('"') and value.endswith('"') else value
            key = None
            continue
        chunks.append(line)
        if line.endswith('"'):
            joined = "\n".join(chunks)
            options[key] = joined[1:] if joined.startswith('"') else joined
            options[key] = options[key][:-1] if options[key].endswith('"') else options[key]
            key = None
            chunks = []
    return options


def preset_options(platform_key: str) -> Dict[str, str]:
    """读取某个 preset 的 options 键值。preset 不存在返回 {}。"""
    index = preset_index(platform_key)
    if index is None:
        return {}
    text = EXPORT_PRESETS.read_text(encoding="utf-8")
    bounds = _preset_section_bounds(text, r"^\[preset\.%s\.options\]\s*$" % index)
    if bounds is None:
        return {}
    return _parse_cfg_options(text[bounds[0] : bounds[1]])


def ios_team_id() -> str:
    return preset_options("ios").get("application/app_store_team_id", "").strip()


def ios_bundle_identifier() -> str:
    return preset_options("ios").get("application/bundle_identifier", "").strip()


def bundle_identifier_problem(value: str) -> Optional[str]:
    """Bundle ID 不可用时返回原因，可用返回 None。

    占位值（com.example.* 之类）必须显式失败，绝不能被当成配置成功蒙混过去。
    """
    if not value:
        return "bundle identifier 为空（preset 需要 application/bundle_identifier）"
    if IOS_BUNDLE_ID_RE.match(value) is None:
        return "invalid bundle identifier: %s（只允许 A-Z a-z 0-9 . -，至少两级）" % value
    lowered = value.lower()
    for token in IOS_PLACEHOLDER_BUNDLE_TOKENS:
        if token in lowered:
            return "invalid/example bundle identifier: %s（仍是占位值，含 %r）" % (value, token)
    return None


def codesigning_identity_names() -> List[str]:
    """keychain 里可用的 codesigning identity 的 CN 列表。"""
    proc = run_cmd(["security", "find-identity", "-v", "-p", "codesigning"])
    names: List[str] = []
    for line in (proc.stdout or "").splitlines():
        found = re.search(r'^\s*\d+\)\s+[0-9A-F]{40}\s+"(.+)"\s*$', line)
        if found:
            names.append(found.group(1))
    return names


def _certificate_organizational_unit(common_name: str) -> str:
    """证书 subject 里的 OU，Apple 用它承载真正的 Team ID。"""
    proc = run_cmd(["security", "find-certificate", "-c", common_name, "-p"])
    pem = proc.stdout or ""
    if proc.returncode != 0 or "BEGIN CERTIFICATE" not in pem:
        return ""
    try:
        parsed = subprocess.run(
            ["openssl", "x509", "-noout", "-subject", "-nameopt", "multiline"],
            input=pem,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    for line in (parsed.stdout or "").splitlines():
        if "organizationalUnitName" in line and "=" in line:
            return line.split("=", 1)[1].strip()
    return ""


def xcode_account_teams() -> Tuple[Optional[List[str]], str]:
    """Xcode 账号里注册过的 Team ID 列表。

    返回 (None, 原因) 表示读不出来（不能据此判成功也不能据此判失败）；
    返回 ([...], "") 表示确实读到了账号团队列表。
    """
    proc = run_cmd(["defaults", "read", "com.apple.dt.Xcode", "IDEProvisioningTeamByIdentifier"])
    if proc.returncode != 0:
        return None, "defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 失败"
    teams = sorted(set(re.findall(r"teamID\s*=\s*([A-Z0-9]{10})", proc.stdout or "")))
    if not teams:
        return None, "Xcode 账号 Team 列表为空/格式无法解析"
    return teams, ""


def installed_provisioning_profiles() -> List[Path]:
    folders = [
        Path.home() / "Library/MobileDevice/Provisioning Profiles",
        Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
    ]
    profiles: List[Path] = []
    for folder in folders:
        if folder.is_dir():
            profiles.extend(sorted(folder.glob("*.mobileprovision")))
    return profiles


_UDID_RE = re.compile(r"\(([0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3,5})\)")


def usb_connected_ios_devices() -> List[str]:
    """USB 连接着的 iOS 设备名（`xcrun xctrace list devices` 的 Devices 段）。"""
    proc = run_cmd(["xcrun", "xctrace", "list", "devices"], timeout=120)
    names: List[str] = []
    in_devices = False
    for line in (proc.stdout or "").splitlines():
        if line.startswith("== "):
            in_devices = line.startswith("== Devices ==")
            continue
        if not in_devices:
            continue
        found = re.match(r"\s*(.+?)\s+\([0-9A-Fa-f-]{20,}\)\s*$", line)
        if found:
            names.append(found.group(1).strip())
    return names


def development_ready_ios_devices() -> List[str]:
    """已在 Xcode 里「Use for Development」的设备（`xcrun devicectl list devices`）。"""
    proc = run_cmd(["xcrun", "devicectl", "list", "devices"], timeout=120)
    out = proc.stdout or ""
    if proc.returncode != 0 or "No devices found" in out:
        return []
    return _UDID_RE.findall(out)



def find_android_sdk() -> Optional[Path]:
    for key in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        value = os.environ.get(key, "").strip()
        if value and Path(value).is_dir():
            return Path(value)
    home = Path.home()
    candidates = [
        home / "Library/Android/sdk",
        home / "Android/Sdk",
        Path(os.environ.get("LOCALAPPDATA", "")) / "Android/Sdk",
    ]
    for path in candidates:
        if path.is_dir() and (path / "platform-tools").is_dir():
            return path
    return None


def find_java_home(prefer_android: bool = False) -> Optional[Path]:
    """定位 JDK。

    `prefer_android=True` 时优先返回 JDK 17：Godot 4.6 的 Android Gradle 模板
    (AGP 8.6.1) 是按 Java 17 配置的，系统默认 JDK 往往是 21/24/25，直接用它会
    触发 Gradle 的 Java 版本不兼容错误。
    """
    env_home = os.environ.get("JAVA_HOME", "").strip()
    if env_home and (Path(env_home) / "bin/java").is_file():
        return Path(env_home)
    if prefer_android:
        preferred = _preferred_android_java_home()
        if preferred is not None:
            return preferred
    if shutil.which("java"):
        return None
    mac_homes = [
        "/usr/libexec/java_home",
    ]
    if Path(mac_homes[0]).is_file():
        proc = run_cmd([mac_homes[0]])
        text = (proc.stdout or "").strip()
        if proc.returncode == 0 and text and (Path(text) / "bin/java").is_file():
            return Path(text)
    jvm_root = Path("/Library/Java/JavaVirtualMachines")
    if jvm_root.is_dir():
        preferred = []
        others = []
        for folder in sorted(jvm_root.iterdir()):
            home = folder / "Contents/Home"
            if not (home / "bin/java").is_file():
                continue
            if "17" in folder.name or "zulu-17" in folder.name or "temurin-17" in folder.name:
                preferred.append(home)
            else:
                others.append(home)
        if preferred:
            return preferred[0]
        if others:
            return others[0]
    return None


def _preferred_android_java_home() -> Optional[Path]:
    """找一个 JDK 17 给 Android Gradle 构建用。"""
    candidates: List[Path] = []
    jvm_root = Path("/Library/Java/JavaVirtualMachines")
    if jvm_root.is_dir():
        for folder in sorted(jvm_root.iterdir()):
            home = folder / "Contents/Home"
            if (home / "bin/java").is_file() and "17" in folder.name:
                candidates.append(home)
    for root in (Path("/usr/lib/jvm"), Path("/opt/java"), Path("/opt/homebrew/opt")):
        if not root.is_dir():
            continue
        for folder in sorted(root.iterdir()):
            for home in (folder, folder / "Contents/Home"):
                if "17" in folder.name and (home / "bin/java").is_file():
                    candidates.append(home)
    return candidates[0] if candidates else None


def android_env() -> Dict[str, str]:
    env: Dict[str, str] = {}
    sdk = find_android_sdk()
    if sdk is not None:
        env["ANDROID_HOME"] = str(sdk)
        env["ANDROID_SDK_ROOT"] = str(sdk)
    java_home = find_java_home(prefer_android=True)
    if java_home is not None:
        env["JAVA_HOME"] = str(java_home)
        env["PATH"] = str(java_home / "bin") + os.pathsep + os.environ.get("PATH", "")
    # Gradle 的缓存默认在 ~/.gradle，在受限沙箱 / CI 里通常不可写。指向仓库内目录，
    # 既避免 "Could not create parent directory for lock file"，也让构建可缓存。
    gradle_home = ROOT / ".gradle-home"
    gradle_home.mkdir(parents=True, exist_ok=True)
    env.setdefault("GRADLE_USER_HOME", str(gradle_home))
    return env


def android_prereq() -> Outcome:
    missing: List[str] = []
    if find_android_sdk() is None:
        missing.append("Android SDK")
    java_home = find_java_home()
    java_on_path = shutil.which("java") is not None
    if java_home is None and not java_on_path:
        missing.append("Java")
    if missing:
        return Outcome("BLOCKED", "Missing: %s" % ", ".join(missing))
    sdk = find_android_sdk()
    java_note = str(java_home) if java_home else "PATH"
    return Outcome("PASS", "Android SDK: %s ; Java: %s" % (sdk, java_note))


def ensure_android_gradle_template() -> Outcome:
    """准备 Gradle 自定义构建用的 `android/` 目录。

    三星 Game Launcher / Game Booster 只认 `android.game_mode_config` 这个
    meta-data，而 Godot 只能通过 Gradle 自定义构建把它写进 manifest。`android/`
    被 .gitignore 排除，所以每次构建都要能从官方模板重新生成，并补上：
      - `res/xml/game_mode_config.xml`
      - manifest 里的 `android.game_mode_config` meta-data
    这两步是幂等的，重复执行不会重复插入。
    """
    source_zip = export_template_dir() / "android_source.zip"
    if not source_zip.is_file():
        return Outcome(
            "BLOCKED",
            "缺少 android_source.zip：%s（需要 Godot %s 的 Export Templates）"
            % (source_zip, GODOT_VERSION),
        )
    target = ROOT / "android"
    # Godot 把 Gradle 工程解到 `gradle_build_directory` + `/build`，
    # 并在其父目录写 `.build_version`、在 build 目录写 `.gdignore`。
    build_dir = target / "build"
    manifest = build_dir / "src/main/AndroidManifest.xml"
    if not manifest.is_file():
        if target.exists():
            shutil.rmtree(target)
        build_dir.mkdir(parents=True, exist_ok=True)
        try:
            with zipfile.ZipFile(source_zip) as archive:
                archive.extractall(build_dir)
        except zipfile.BadZipFile:
            return Outcome("FAIL", "android_source.zip 损坏：%s" % source_zip)
        # 版本标识：与 Godot 的命令行导出保持一致，避免 "build version mismatch"。
        (target / ".build_version").write_text(
            "%s\n" % GODOT_TEMPLATE_DIR_NAME, encoding="utf-8"
        )
        (build_dir / ".gdignore").write_text("\n", encoding="utf-8")
    # zip 不带可执行位，gradlew 必须手动补上，否则 Gradle 构建报 Permission denied。
    gradlew = build_dir / "gradlew"
    if gradlew.is_file():
        gradlew.chmod(gradlew.stat().st_mode | 0o755)
    if not manifest.is_file():
        return Outcome("FAIL", "Android 模板里没有 src/main/AndroidManifest.xml")

    config_dir = build_dir / "res/xml"
    config_dir.mkdir(parents=True, exist_ok=True)
    config_path = config_dir / "game_mode_config.xml"
    config_path.write_text(GAME_MODE_CONFIG_XML, encoding="utf-8")

    text = manifest.read_text(encoding="utf-8")
    if "android.game_mode_config" not in text:
        anchor = 'tools:ignore="GoogleAppIndexingWarning" >'
        if anchor not in text:
            return Outcome("FAIL", "AndroidManifest.xml 结构不符合预期，找不到 application 结尾")
        text = text.replace(anchor, anchor + "\n" + GAME_MODE_META_DATA, 1)
        manifest.write_text(text, encoding="utf-8")
    return Outcome("PASS", "Android Gradle 模板就绪（含 game_mode_config）")


def game_mode_outcome() -> Outcome:
    """确认 Gradle 构建里确实带了游戏模式声明。"""
    manifest = ROOT / "android/build/src/main/AndroidManifest.xml"
    config = ROOT / "android/build/res/xml/game_mode_config.xml"
    if not manifest.is_file() or not config.is_file():
        return Outcome("FAIL", "Android Gradle 模板缺少 game_mode_config")
    text = manifest.read_text(encoding="utf-8")
    if "android.game_mode_config" not in text:
        return Outcome("FAIL", "AndroidManifest.xml 缺少 android.game_mode_config")
    if 'android:appCategory="game"' not in text:
        return Outcome("FAIL", 'AndroidManifest.xml 缺少 android:appCategory="game"')
    return Outcome("PASS", "Android 游戏模式声明就绪")


# ---------------------------------------------------------------------------
# iOS 本地 development 环境检查（doctor / preflight 共用）
# ---------------------------------------------------------------------------
@dataclass
class IosCheck:
    label: str
    ok: bool
    code: str = ""
    detail: str = ""
    notes: Tuple[str, ...] = ()

    @property
    def message(self) -> str:
        if self.ok:
            return self.detail or self.label
        if self.code:
            return "%s: %s" % (self.code, self.detail)
        return self.detail


def _ios_pass(label: str, detail: str, *notes: str) -> IosCheck:
    return IosCheck(label, True, "", detail, tuple(notes))


def _ios_fail(label: str, code: str, detail: str, *notes: str) -> IosCheck:
    return IosCheck(label, False, code, detail, tuple(notes))


def xcode_developer_dir() -> Tuple[int, str]:
    proc = run_cmd(["xcode-select", "-p"])
    return proc.returncode, (proc.stdout or "").strip()


def xcodebuild_version() -> Tuple[int, str]:
    if shutil.which("xcodebuild") is None:
        return 1, "xcodebuild 不在 PATH"
    proc = run_cmd(["xcodebuild", "-version"])
    lines = [line for line in (proc.stdout or "").strip().splitlines() if line.strip()]
    return proc.returncode, " / ".join(lines[:2])


def ios_signing_check(team_id: str) -> IosCheck:
    """Apple development signing 是否可用。

    判定标准：keychain 里有 codesigning identity，**并且** Xcode 账号里确实有这个
    Team（Automatic Signing 靠 Xcode 账号去要 provisioning profile）。读不到就明确
    FAIL，绝不因为「大概可以」就输出 PASS。
    """
    label = "Apple signing availability"
    blocked = "No usable Apple development signing identity / Personal Team provisioning is available."
    if not team_id:
        return _ios_fail(label, "IOS_SIGNING_BLOCKED", "Team ID 为空，无法确定签名目标")
    identities = codesigning_identity_names()
    if not identities:
        return _ios_fail(
            label,
            "IOS_SIGNING_BLOCKED",
            blocked,
            "security find-identity -p codesigning：0 个 identity",
            "修复：Xcode → Settings → Accounts → 登录 Apple ID → Manage Certificates → Apple Development",
        )
    notes: List[str] = ["keychain identity: %s" % identities[0]]
    cert_team = _certificate_organizational_unit(identities[0])
    if cert_team:
        notes.append("证书 OU Team = %s（Apple 用 OU 承载真正的 Team ID）" % cert_team)
    profiles = installed_provisioning_profiles()
    notes.append("本机 provisioning profile 数量：%d" % len(profiles))
    teams, reason = xcode_account_teams()
    if teams is None:
        return _ios_fail(
            label,
            "IOS_SIGNING_BLOCKED",
            "无法检查 Xcode 账号是否拥有 Team %s（%s）" % (team_id, reason),
            "Automatic Signing 需要 Xcode 账号；读不到就不能算通过",
            "修复：Xcode → Settings → Accounts → 登录拥有 Team %s 的 Apple ID" % team_id,
        )
    notes.append("Xcode 账号里的 Team：%s" % ", ".join(teams))
    if team_id not in teams:
        return _ios_fail(
            label,
            "IOS_SIGNING_BLOCKED",
            blocked,
            *tuple(notes),
            "配置的 Team ID = %s，但 Xcode 账号里没有这个 Team" % team_id,
            "修复：Xcode → Settings → Accounts → 用拥有 Team %s 的 Apple ID 登录" % team_id,
        )
    if not profiles:
        # 没有 profile 就一定归档不了；Apple 只有在团队里至少有一台已注册设备时
        # 才会签发 development profile，所以这里必须把设备状态说清楚。
        connected = usb_connected_ios_devices()
        ready = development_ready_ios_devices()
        notes.append("USB 连接的 iOS 设备：%s" % (", ".join(connected) if connected else "无"))
        notes.append("已可用于开发的设备：%d 台" % len(ready))
        if not ready:
            if connected:
                fix = (
                    "Xcode → Window → Devices and Simulators → 选中 %s → "
                    "Use for Development（手机需解锁、开启开发者模式并信任此电脑）" % connected[0]
                )
            else:
                fix = (
                    "用数据线连接 iPhone/iPad，在 Xcode → Window → Devices and Simulators 里 "
                    "点 Use for Development"
                )
            return _ios_fail(
                label,
                "IOS_SIGNING_BLOCKED",
                blocked,
                *tuple(notes),
                "Apple：Your team has no devices from which to generate a provisioning profile.",
                "修复：" + fix,
            )
    return _ios_pass(
        label,
        "codesigning identity 可用，Xcode 账号拥有 Team %s" % team_id,
        *tuple(notes),
    )


def ios_preflight(configuration: str = "development") -> List[IosCheck]:
    """iOS 构建前的全部检查。顺序即执行顺序：macOS 不通过就立刻停。"""
    checks: List[IosCheck] = []
    if platform.system() != "Darwin":
        checks.append(_ios_fail("macOS", "IOS_EXPORT_BLOCKED", "iOS export requires macOS and Xcode"))
        return checks
    checks.append(_ios_pass("macOS", "macOS %s" % (platform.mac_ver()[0] or platform.system())))

    code, dev_dir = xcode_developer_dir()
    if code != 0 or not dev_dir:
        checks.append(_ios_fail("Xcode", "IOS_EXPORT_BLOCKED", "xcode-select -p 执行失败：%s" % (dev_dir or "无输出")))
    elif not Path(dev_dir).is_dir():
        checks.append(_ios_fail("Xcode", "IOS_EXPORT_BLOCKED", "Xcode developer directory 不存在：%s" % dev_dir))
    elif "Xcode.app" not in dev_dir:
        checks.append(
            _ios_fail(
                "Xcode",
                "IOS_EXPORT_BLOCKED",
                "xcode-select is not pointing to Xcode: %s" % dev_dir,
                "修复：sudo xcode-select -s /Applications/Xcode.app/Contents/Developer",
            )
        )
    else:
        checks.append(_ios_pass("Xcode", dev_dir))

    xcode_build_code, xcode_build = xcodebuild_version()
    if xcode_build_code != 0 or not xcode_build.startswith("Xcode"):
        checks.append(_ios_fail("xcodebuild", "IOS_EXPORT_BLOCKED", "xcodebuild 不可用：%s" % xcode_build))
    else:
        checks.append(_ios_pass("xcodebuild", xcode_build))

    if code != 0 or not dev_dir:
        checks.append(_ios_fail("xcode-select", "IOS_EXPORT_BLOCKED", "xcode-select -p 执行失败"))
    elif dev_dir == "/Library/Developer/CommandLineTools" or "CommandLineTools" in dev_dir:
        checks.append(
            _ios_fail(
                "xcode-select",
                "IOS_EXPORT_BLOCKED",
                "xcode-select is not pointing to Xcode: %s" % dev_dir,
                "当前指向 Command Line Tools，iOS 构建需要完整 Xcode",
                "修复：sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -license accept",
            )
        )
    else:
        checks.append(_ios_pass("xcode-select", dev_dir))

    godot = find_godot()
    if godot is None:
        checks.append(_ios_fail("Godot 4.6.2", "IOS_EXPORT_BLOCKED", "找不到 Godot"))
    else:
        version_line = godot_version_line(godot)
        if not godot_version_ok(version_line):
            checks.append(
                _ios_fail(
                    "Godot 4.6.2",
                    "IOS_EXPORT_BLOCKED",
                    "Godot 版本是 %s，本仓库要求 %s" % (version_line or "未知", GODOT_VERSION),
                )
            )
        else:
            checks.append(_ios_pass("Godot 4.6.2", "%s（%s）" % (GODOT_VERSION, godot)))

    templates = templates_ready("ios")
    if templates.status != "PASS":
        checks.append(_ios_fail("iOS export template", "IOS_EXPORT_BLOCKED", templates.message))
    else:
        checks.append(_ios_pass("iOS export template", templates.message))

    team_id = ios_team_id()
    if not team_id:
        checks.append(
            _ios_fail(
                "Team ID",
                "IOS_EXPORT_BLOCKED",
                "preset 缺少 application/app_store_team_id（需要 Xcode Personal Team 的 Team ID）",
            )
        )
    elif IOS_TEAM_ID_RE.match(team_id) is None:
        checks.append(_ios_fail("Team ID", "IOS_EXPORT_BLOCKED", "Team ID 格式不对：%r（应为 10 位大写字母数字）" % team_id))
    else:
        checks.append(_ios_pass("Team ID", team_id))

    bundle_id = ios_bundle_identifier()
    problem = bundle_identifier_problem(bundle_id)
    if problem is None:
        checks.append(_ios_pass("Bundle ID", bundle_id))
    else:
        checks.append(_ios_fail("Bundle ID", "IOS_EXPORT_BLOCKED", problem))

    if not preset_exists("ios"):
        checks.append(_ios_fail("iOS preset", "IOS_EXPORT_BLOCKED", "export preset 缺失：iOS"))
    else:
        checks.append(_ios_pass("iOS preset", 'name="iOS" platform="iOS"'))

    options = preset_options("ios")
    if options.get("architectures/arm64") == "true":
        checks.append(_ios_pass("ARM64", "architectures/arm64=true"))
    else:
        checks.append(_ios_fail("ARM64", "IOS_EXPORT_BLOCKED", "iOS preset 未启用 architectures/arm64=true"))

    export_method = options.get("application/export_method_debug", "")
    if export_method == IOS_EXPORT_METHOD_DEVELOPMENT:
        checks.append(_ios_pass("development export method", "application/export_method_debug=1 (Development)"))
    else:
        checks.append(
            _ios_fail(
                "development export method",
                "IOS_EXPORT_BLOCKED",
                "application/export_method_debug=%r，本地 Personal Team 构建必须是 1 (Development)；"
                "不要把 export_method_release=0 (App Store) 当成本阶段构建路径" % export_method,
            )
        )

    checks.append(ios_signing_check(team_id))
    return checks


def ios_prereq(_platform_key: str) -> Outcome:
    """platform_prereq 的 iOS 分支：返回第一条不通过的检查。"""
    for check in ios_preflight():
        if not check.ok:
            return Outcome("BLOCKED", check.message)
    return Outcome("PASS", "ios development 构建条件满足（Godot %s）" % GODOT_VERSION)


def platform_prereq(platform_key: str) -> Outcome:
    if platform_key == "ios":
        return ios_prereq(platform_key)
    godot = find_godot()
    if godot is None:
        return Outcome("BLOCKED", "Missing: Godot")
    version_line = godot_version_line(godot)
    if not version_line:
        return Outcome("BLOCKED", "Godot 无法运行：%s" % godot)
    if not godot_version_ok(version_line):
        return Outcome(
            "BLOCKED",
            "Godot 版本是 %s，本仓库要求 %s.x" % (version_line, GODOT_VERSION),
        )
    if not preset_exists(platform_key):
        return Outcome("BLOCKED", "export preset 缺失：%s" % PRESETS[platform_key])
    templates = templates_ready(platform_key)
    if templates.status != "PASS":
        return templates
    if platform_key == "android":
        android = android_prereq()
        if android.status != "PASS":
            return android
        gradle = ensure_android_gradle_template()
        if gradle.status != "PASS":
            return gradle
        mode = game_mode_outcome()
        if mode.status != "PASS":
            return mode
    return Outcome("PASS", "%s 构建条件满足（Godot %s）" % (platform_key, version_line))


def game_category_outcome() -> Outcome:
    """确认所有平台都被标记成游戏。

    手机 / 启动器是否把包当成游戏，取决于各平台的分类字段。这里做静态检查，
    防止以后改 preset 时把游戏标记改掉（尤其是 iOS 的 LSApplicationCategoryType，
    它写在 additional_plist_content 里，很容易被整段覆盖掉）。
    """
    if not EXPORT_PRESETS.is_file():
        return Outcome("FAIL", "找不到 export_presets.cfg")
    text = EXPORT_PRESETS.read_text(encoding="utf-8")
    problems: List[str] = []
    for platform_key, (field, expected) in sorted(GAME_CATEGORY_EXPECTATIONS.items()):
        if platform_key == "ios":
            found = expected in text
        else:
            # 值可能带引号（例如 macOS 的 application/app_category="Games"）。
            pattern = re.compile(
                r'^%s="?%s"?\s*$' % (re.escape(field), re.escape(expected)),
                re.MULTILINE,
            )
            found = pattern.search(text) is not None
        if not found:
            problems.append("%s 缺少游戏分类（%s=%s）" % (platform_key, field, expected))
    android_pattern = re.compile(
        r"^package/app_category=%d\s*$" % ANDROID_APP_CATEGORY_GAME,
        re.MULTILINE,
    )
    if android_pattern.search(text) is None:
        problems.append("android 的 package/app_category 必须是 %d (Game)" % ANDROID_APP_CATEGORY_GAME)
    # 三星 Game Launcher / Game Booster 依赖 Gradle 自定义构建写入的 game_mode_config。
    # 一旦被改回 false，三星等 OEM 又会识别不出游戏，所以这里一并锁住。
    if re.search(r"^gradle_build/use_gradle_build=true\s*$", text, re.MULTILINE) is None:
        problems.append("android 必须启用 gradle_build/use_gradle_build（三星需要 game_mode_config）")
    if problems:
        return Outcome("FAIL", "；".join(problems))
    return Outcome("PASS", "所有平台的游戏分类标记就绪")


def ios_artifact_basename(configuration: str = "development", include_sha: bool = True) -> str:
    """本地 development 产物名。

    永远带 development 字样：这台机器（免费 Personal Team）只能签 development，
    任何输出都不允许暗示 App Store / TestFlight / Ad Hoc 分发。
    """
    configuration = IOS_CONFIGURATION_ALIASES.get(configuration, configuration)
    name = "WPG-ios-%s" % configuration
    if include_sha:
        return "%s-%s.ipa" % (name, git_commit(short=True))
    return "%s.ipa" % name


def package_basename(platform_key: str, release: bool) -> str:
    if release:
        # 正式 Release 命名：WPG-vX.Y.Z-<platform>.zip / WPG-vX.Y.Z-android.apk。
        # Dev 命名重构绝对不许改这一支。
        if platform_key == "ios":
            # iOS 只有本地 development 构建，没有 release/distribution 语义。
            return ios_artifact_basename("development", include_sha=True)
        version = read_project_version() or "UNKNOWN"
        if platform_key == "android":
            return "WPG-v%s-android.apk" % version
        return "WPG-v%s-%s.zip" % (version, platform_key)
    return dev_package_basename(platform_key)


# ---------------------------------------------------------------------------
# Dev build 命名（唯一的命名真源）
# ---------------------------------------------------------------------------
# 规则：WPG_YYYYMMDD_<7位commit>_<platform>.<ext>
#
# 日期来自**触发那次构建的 commit 的 commit timestamp**，不是 workflow 运行日期：
# 同一个 commit 无论在哪天重跑，前缀都一样；同一次 push 的六个平台也必然同前缀。
# 短 SHA 严格 7 位。
#
# 正式 Release 命名（WPG-vX.Y.Z-...）与这里完全分开，互不影响。
DEV_PLATFORM_EXTENSIONS: Dict[str, str] = {
    "windows": "zip",
    "macos": "zip",
    "linux": "zip",
    "android": "apk",
    "web": "zip",
    "ios": "zip",
}

# Dev CD 的六个平台（顺序即 SHA256SUMS / manifest 里的顺序）。
DEV_PLATFORMS: Tuple[str, ...] = tuple(DEV_PLATFORM_EXTENSIONS.keys())

DEV_BUILD_PREFIX_ENV = "WPG_DEV_BUILD_PREFIX"
DEV_DATE_ENV = "WPG_DEV_DATE"
DEV_SHA_ENV = "WPG_DEV_SHA"
DEV_BRANCH_ENV = "WPG_DEV_BRANCH"

DEV_DATE_RE = re.compile(r"^\d{8}$")


def git_commit_date(sha: str = "") -> str:
    """某个 commit 的 YYYYMMDD（committer date）。取不到返回 ""。"""
    args = ["log", "-1", "--format=%cs"]
    if sha:
        args.append(sha)
    code, text = git_output(args)
    if code != 0 or not text.strip():
        return ""
    first = text.strip().split()[0]
    digits = re.sub(r"\D", "", first)
    if len(digits) != 8:
        return ""
    return digits


def dev_commit_date(sha: str = "") -> str:
    """Dev 构建前缀里的日期。优先级：显式值 > 环境变量 > commit timestamp。

    最后兜底用当天日期，只是为了让「拿不到 git」时构建脚本不要因为命名而崩，
    正常的 CI / 本地 / Netlify 环境里 git 一定在，走不到这一支。
    """
    env = os.environ.get(DEV_DATE_ENV, "").strip()
    if DEV_DATE_RE.match(env):
        return env
    found = git_commit_date(sha or os.environ.get(DEV_SHA_ENV, "").strip())
    if found:
        return found
    return time.strftime("%Y%m%d", time.gmtime())


def dev_short_sha(sha: str = "") -> str:
    """严格 7 位短 SHA。"""
    if sha:
        return sha[:7]
    env = os.environ.get(DEV_SHA_ENV, "").strip()
    if env:
        return env[:7]
    return git_commit(short=True)


def dev_build_prefix(commit_date: str = "", short_sha: str = "") -> str:
    """WPG_YYYYMMDD_7sha —— 所有 Dev 产物名的共同前缀。

    prepare job 算一次，写进 WPG_DEV_BUILD_PREFIX 环境变量；六个平台 job、
    verify、aggregate 全都读同一个值，杜绝「Windows 一个日期、Android 另一个」。
    """
    if commit_date and short_sha:
        return "WPG_%s_%s" % (commit_date, short_sha)
    env = os.environ.get(DEV_BUILD_PREFIX_ENV, "").strip()
    if env:
        return env
    return "WPG_%s_%s" % (commit_date or dev_commit_date(), short_sha or dev_short_sha())


def dev_package_basename(platform_key: str) -> str:
    if platform_key not in DEV_PLATFORM_EXTENSIONS:
        raise ValueError("未知平台：%s" % platform_key)
    ext = DEV_PLATFORM_EXTENSIONS[platform_key]
    return "%s_%s.%s" % (dev_build_prefix(), platform_key, ext)


def dev_artifact_name(platform_key: str) -> str:
    """GitHub Actions artifact 名（不含扩展名）。

    upload-artifact 是 immutable 语义：一个 artifact 只能由一个 job 写一次，
    所以六个平台必须各自一个唯一名字。
    """
    if platform_key not in DEV_PLATFORM_EXTENSIONS:
        raise ValueError("未知平台：%s" % platform_key)
    return "%s_%s" % (dev_build_prefix(), platform_key)


def dev_checksums_name() -> str:
    return "%s_SHA256SUMS.txt" % dev_build_prefix()


def dev_manifest_name() -> str:
    return "%s_manifest.json" % dev_build_prefix()


def read_branch_or_env() -> str:
    """分支名：优先 WPG_DEV_BRANCH（prepare 写的），再看 git，最后 GITHUB_REF_NAME。

    checkout 一个精确 SHA 时 HEAD 是 detached，`abbrev-ref` 只会给出 HEAD，
    所以 CI 里必须由 prepare 把分支名塞进环境变量。
    """
    env = os.environ.get(DEV_BRANCH_ENV, "").strip()
    if env:
        return env
    branch = git_branch()
    if branch and branch != "HEAD":
        return branch
    return os.environ.get("GITHUB_REF_NAME", "").strip() or "UNKNOWN"


def zip_directory(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        destination.unlink()
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(source.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(source).as_posix())


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_sha256sums(paths: Sequence[Path], destination: Path) -> None:
    lines = []
    for path in paths:
        lines.append("%s  %s" % (sha256_file(path), path.name))
    destination.write_text("\n".join(lines) + "\n", encoding="utf-8")


def tool_versions() -> Dict[str, str]:
    godot = find_godot()
    godot_text = "MISSING"
    if godot is not None:
        line = godot_version_line(godot)
        godot_text = line or "UNKNOWN"
    return {
        "version": read_project_version() or "MISSING",
        "branch": git_branch(),
        "commit": git_commit(short=True),
        "tag": git_exact_tag(),
        "godot": godot_text,
        "python": platform.python_version(),
        "git": "ok" if shutil.which("git") else "MISSING",
    }
