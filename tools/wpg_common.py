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
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple


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
}

PLATFORMS: Tuple[str, ...] = ("windows", "macos", "linux", "android", "web")

TEMPLATE_FILES: Dict[str, Tuple[str, ...]] = {
    "windows": ("windows_release_x86_64.exe",),
    "macos": ("macos.zip",),
    "linux": ("linux_release.x86_64",),
    "android": ("android_release.apk", "android_debug.apk"),
    "web": ("web_nothreads_release.zip", "web_release.zip"),
}


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


def preset_exists(platform_key: str) -> bool:
    if not EXPORT_PRESETS.is_file():
        return False
    text = EXPORT_PRESETS.read_text(encoding="utf-8")
    preset_name = PRESETS[platform_key]
    return ('name="%s"' % preset_name) in text and (
        'platform="%s"' % preset_name
    ) in text


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


def platform_prereq(platform_key: str) -> Outcome:
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


def package_basename(platform_key: str, release: bool) -> str:
    if release:
        version = read_project_version() or "UNKNOWN"
        if platform_key == "android":
            return "WPG-v%s-android.apk" % version
        return "WPG-v%s-%s.zip" % (version, platform_key)
    commit = git_commit(short=True)
    if platform_key == "android":
        return "WPG-android-%s.apk" % commit
    return "WPG-%s-%s.zip" % (platform_key, commit)


def github_artifact_name(platform_key: str) -> str:
    commit = os.environ.get("GITHUB_SHA", git_commit(short=False))[:7]
    ref_name = os.environ.get("GITHUB_REF_NAME", git_branch())
    if ref_name.startswith("dev/"):
        leaf = ref_name.split("/", 1)[1].replace("/", "-")
        return "WPG-dev-%s-%s-%s" % (leaf, platform_key, commit)
    if ref_name == "main":
        return "WPG-main-%s-%s" % (platform_key, commit)
    safe = ref_name.replace("/", "-")
    return "WPG-%s-%s-%s" % (safe, platform_key, commit)


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
