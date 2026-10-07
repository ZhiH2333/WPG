#!/usr/bin/env python3
"""Dev build 命名单元测试。

    python3 tools/test/test_dev_naming.py

锁住这几条规则，防止以后有人改回散落的 `WPG-windows-xxxx`：
  1. Dev 前缀 = WPG_YYYYMMDD_<7位commit>
  2. 日期来自 commit timestamp，不是运行当天
  3. 六个平台各自的扩展名
  4. artifact 名唯一且不含扩展名
  5. 正式 Release 命名（WPG-vX.Y.Z-...）完全不受影响
  6. iOS 只在 Dev 里出现，release 平台集合仍是五个
  7. 本地 Personal Team 的 .ipa 命名不变
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import wpg_common as wpg  # noqa: E402

DEV_ENV_KEYS = (
    "WPG_DEV_BUILD_PREFIX",
    "WPG_DEV_DATE",
    "WPG_DEV_SHA",
    "WPG_DEV_BRANCH",
)

EXAMPLE_DATE = "20261005"
EXAMPLE_FULL_SHA = "e34723ff606b660119b68f4526804cf3d24b7190"
EXAMPLE_SHORT_SHA = "e34723f"
EXAMPLE_PREFIX = "WPG_20261005_e34723f"

EXPECTED_DEV_FILES: Dict[str, str] = {
    "windows": "WPG_20261005_e34723f_windows.zip",
    "macos": "WPG_20261005_e34723f_macos.zip",
    "linux": "WPG_20261005_e34723f_linux.zip",
    "android": "WPG_20261005_e34723f_android.apk",
    "web": "WPG_20261005_e34723f_web.zip",
    "ios": "WPG_20261005_e34723f_ios.zip",
}


class Runner:
    def __init__(self) -> None:
        self.failures: List[str] = []
        self.passed = 0

    def check(self, label: str, actual: object, expected: object) -> None:
        if actual == expected:
            self.passed += 1
            print("[PASS] %s" % label)
        else:
            self.failures.append("%s: %r != %r" % (label, actual, expected))
            print("[FAIL] %s: %r != %r" % (label, actual, expected))

    def ok(self, label: str, condition: bool, detail: str = "") -> None:
        if condition:
            self.passed += 1
            print("[PASS] %s" % label)
        else:
            self.failures.append("%s%s" % (label, ("：%s" % detail) if detail else ""))
            print("[FAIL] %s%s" % (label, ("：%s" % detail) if detail else ""))

    def note(self, message: str) -> None:
        print("[INFO] %s" % message)


def with_env(overrides: Dict[str, Optional[str]]) -> None:
    for key in DEV_ENV_KEYS:
        os.environ.pop(key, None)
    for key, value in overrides.items():
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value


def run_print_meta(args: List[str], env: Dict[str, str]) -> Dict[str, str]:
    proc = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "build" / "print_meta.py"), *args],
        cwd=str(ROOT),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        raise AssertionError("print_meta %s 失败：%s%s" % (" ".join(args), proc.stdout, proc.stderr))
    out: Dict[str, str] = {}
    for line in proc.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            out[key.strip()] = value.strip()
    return out


def main() -> int:
    saved = {key: os.environ.get(key) for key in DEV_ENV_KEYS}
    runner = Runner()
    try:
        with_env({})

        # ---- 1. 前缀格式 -------------------------------------------------
        runner.check(
            "dev_build_prefix(显式日期+短SHA)",
            wpg.dev_build_prefix(EXAMPLE_DATE, EXAMPLE_SHORT_SHA),
            EXAMPLE_PREFIX,
        )

        # ---- 2. 短 SHA 严格 7 位 ----------------------------------------
        runner.check("短 SHA 7 位", wpg.dev_short_sha(EXAMPLE_FULL_SHA), EXAMPLE_SHORT_SHA)

        # ---- 3. 环境变量前缀优先 ----------------------------------------
        with_env({"WPG_DEV_BUILD_PREFIX": EXAMPLE_PREFIX})
        runner.check("WPG_DEV_BUILD_PREFIX 优先", wpg.dev_build_prefix(), EXAMPLE_PREFIX)

        # ---- 4. 日期 / SHA 环境变量拼出同一个前缀 ------------------------
        with_env({"WPG_DEV_DATE": EXAMPLE_DATE, "WPG_DEV_SHA": EXAMPLE_FULL_SHA})
        runner.check(
            "WPG_DEV_DATE + WPG_DEV_SHA 拼前缀",
            wpg.dev_build_prefix(),
            EXAMPLE_PREFIX,
        )
        runner.check("dev_commit_date 读环境变量", wpg.dev_commit_date(), EXAMPLE_DATE)

        # ---- 5. 六个平台的文件名 ----------------------------------------
        with_env({"WPG_DEV_BUILD_PREFIX": EXAMPLE_PREFIX})
        for platform_key, expected in EXPECTED_DEV_FILES.items():
            runner.check(
                "dev_package_basename(%s)" % platform_key,
                wpg.dev_package_basename(platform_key),
                expected,
            )
            runner.check(
                "package_basename(%s, release=False)" % platform_key,
                wpg.package_basename(platform_key, False),
                expected,
            )
            runner.check(
                "dev_artifact_name(%s) 唯一且无扩展名" % platform_key,
                wpg.dev_artifact_name(platform_key),
                EXAMPLE_PREFIX + "_" + platform_key,
            )

        runner.check(
            "SHA256SUMS 文件名",
            wpg.dev_checksums_name(),
            EXAMPLE_PREFIX + "_SHA256SUMS.txt",
        )
        runner.check(
            "manifest 文件名",
            wpg.dev_manifest_name(),
            EXAMPLE_PREFIX + "_manifest.json",
        )

        # ---- 6. 平台集合边界 --------------------------------------------
        runner.check("release 平台仍是五个", list(wpg.PLATFORMS), ["windows", "macos", "linux", "android", "web"])
        runner.ok("release 平台不含 ios", "ios" not in wpg.PLATFORMS)
        runner.check(
            "Dev 平台是六个（含 ios）",
            list(wpg.DEV_PLATFORMS),
            ["windows", "macos", "linux", "android", "web", "ios"],
        )
        runner.ok("PRESETS 含 ios", "ios" in wpg.PRESETS)

        # ---- 7. Release 命名完全不受影响 --------------------------------
        version = wpg.read_project_version()
        runner.ok("project.godot 版本可读", bool(version), str(version))
        version = version or "UNKNOWN"
        for platform_key in wpg.PLATFORMS:
            expected = (
                "WPG-v%s-android.apk" % version
                if platform_key == "android"
                else "WPG-v%s-%s.zip" % (version, platform_key)
            )
            runner.check(
                "release 命名 %s" % platform_key,
                wpg.package_basename(platform_key, True),
                expected,
            )
        runner.ok(
            "release 命名仍是 WPG-vX.Y.Z-*",
            re.match(r"^WPG-v\d+\.\d+\.\d+-(windows|macos|linux|web)\.zip$", wpg.package_basename("windows", True))
            is not None,
        )

        # ---- 8. 本地 iOS Personal Team 命名不变 --------------------------
        ipa = wpg.ios_artifact_basename("development", include_sha=True)
        runner.ok("本地 iOS 包仍是 .ipa", ipa.endswith(".ipa"), ipa)
        runner.ok(
            "本地 iOS 包名前缀不变",
            ipa.startswith("WPG-ios-development-"),
            ipa,
        )
        runner.check(
            "iOS Dev 包是 .zip 不是 .ipa",
            wpg.dev_package_basename("ios"),
            EXAMPLE_PREFIX + "_ios.zip",
        )

        # ---- 9. 未知平台必须报错 ----------------------------------------
        runner.ok("未知平台抛异常", _raises(lambda: wpg.dev_package_basename("switch")))

        # ---- 10. commit timestamp 是日期，不是运行日期 -------------------
        with_env({})
        commit_date = wpg.dev_commit_date()
        runner.ok("commit 日期是 8 位数字", re.match(r"^\d{8}$", commit_date) is not None, str(commit_date))
        git_date = _git_date()
        if git_date:
            runner.check("日期来自 git commit timestamp", commit_date, git_date)
        else:
            runner.note("拿不到 git 日期，跳过比对")

        # ---- 11. print_meta 输出 ----------------------------------------
        clean_env = dict(os.environ)
        for key in DEV_ENV_KEYS:
            clean_env.pop(key, None)
        clean_env["WPG_DEV_BUILD_PREFIX"] = EXAMPLE_PREFIX
        meta = run_print_meta(["windows"], clean_env)
        runner.check("print_meta windows file_name", meta.get("file_name"), EXPECTED_DEV_FILES["windows"])
        runner.check(
            "print_meta windows artifact_name",
            meta.get("artifact_name"),
            EXAMPLE_PREFIX + "_windows",
        )
        meta_release = run_print_meta(["android", "--release"], clean_env)
        runner.check("print_meta android --release file_name", meta_release.get("file_name"), "WPG-v%s-android.apk" % version)
        runner.check(
            "print_meta --release artifact_name",
            meta_release.get("artifact_name"),
            "release-android",
        )
        prefix_env = dict(clean_env)
        prefix_env["WPG_DEV_BRANCH"] = "dev"
        prefix_env.pop("WPG_DEV_BUILD_PREFIX", None)
        prefix_out = run_print_meta(["--prefix"], prefix_env)
        runner.check(
            "print_meta --prefix build_prefix",
            prefix_out.get("build_prefix"),
            "WPG_%s_%s" % (prefix_out.get("commit_date"), prefix_out.get("short_sha")),
        )
        runner.check("print_meta --prefix branch", prefix_out.get("branch"), "dev")
        runner.ok(
            "print_meta --prefix sha 是 40 位",
            re.match(r"^[0-9a-f]{40}$", prefix_out.get("sha", "")) is not None,
            prefix_out.get("sha", ""),
        )
        runner.check(
            "print_meta --prefix short_sha 7 位",
            len(prefix_out.get("short_sha", "")),
            7,
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    print("")
    if runner.failures:
        for item in runner.failures:
            print("[FAIL] %s" % item)
        print("[FAIL] Dev naming unit tests：%d 失败 / %d 通过" % (len(runner.failures), runner.passed))
        return 1
    print("[PASS] Dev naming unit tests：%d 项通过" % runner.passed)
    return 0


def _raises(func) -> bool:
    try:
        func()
    except ValueError:
        return True
    return False


def _git_date() -> str:
    try:
        proc = subprocess.run(
            ["git", "log", "-1", "--format=%cs"],
            cwd=str(ROOT),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return ""
    if proc.returncode != 0:
        return ""
    return re.sub(r"\D", "", proc.stdout.strip())


if __name__ == "__main__":
    sys.exit(main())
