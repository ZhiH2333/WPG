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
    print("%s %s" % (paint(kind, "[%s]" % kind), message))


def emit_outcome(outcome: Outcome) -> None:
    emit(outcome.status, outcome.message)


def run_cmd(
    args: Sequence[str],
    cwd: Optional[Path] = None,
    env: Optional[Dict[str, str]] = None,
    log_path: Optional[Path] = None,
) -> subprocess.CompletedProcess:
    merged = os.environ.copy()
    if env:
        merged.update(env)
    proc = subprocess.run(
        list(args),
        cwd=str(cwd or ROOT),
        env=merged,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
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


def find_java_home() -> Optional[Path]:
    env_home = os.environ.get("JAVA_HOME", "").strip()
    if env_home and (Path(env_home) / "bin/java").is_file():
        return Path(env_home)
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


def android_env() -> Dict[str, str]:
    env: Dict[str, str] = {}
    sdk = find_android_sdk()
    if sdk is not None:
        env["ANDROID_HOME"] = str(sdk)
        env["ANDROID_SDK_ROOT"] = str(sdk)
    java_home = find_java_home()
    if java_home is not None:
        env["JAVA_HOME"] = str(java_home)
        env["PATH"] = str(java_home / "bin") + os.pathsep + os.environ.get("PATH", "")
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
    return Outcome("PASS", "%s 构建条件满足（Godot %s）" % (platform_key, version_line))


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
