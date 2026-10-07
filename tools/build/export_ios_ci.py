#!/usr/bin/env python3
"""CI 用的**无签名** iOS 构建：只证明「这个 commit 能在 iOS 上编译」，不签名、不产 .ipa。

    python3 tools/build/export_ios_ci.py

流程（GitHub Actions 的 macOS runner 上，没有任何 Apple 凭据）：
    阶段 1  Godot 4.6.2 --export-debug + 临时 export_project_only=true → WPG.xcodeproj
    阶段 2  确认 WPG.xcodeproj / project.pbxproj / scheme 真的存在
    阶段 3  xcodebuild 在 generic/platform=iOS 上用 CODE_SIGNING_ALLOWED=NO 编译
    阶段 4  找到生成的 WPG.app
    阶段 5  WPG.app + WPG.xcodeproj → artifacts/WPG_YYYYMMDD_7sha_ios.zip

为什么这个包是 .zip 而不是 .ipa：
    没有签名的 .app 装不进任何设备、也过不了任何审核。把它叫 .ipa 就是撒谎。
    这个 zip 只用来证明 CI 能编译，并让 reviewer 拿到 Xcode 工程继续排查。
    要真机安装，走本地 Personal Team 路径：python3 tools/build/export_platform.py ios

这个脚本绝不做的事（本地 iOS 工具链的硬边界）：
    - 不读、不校验、不要求 Team ID / Apple ID / .p12 / .mobileprovision / private key
    - 不调用 ios_signing_check() / ios_preflight()，不把签名状态伪装成构建状态
    - export_presets.cfg 只在阶段 1 临时把 export_project_only 置 true，
      结束后按**原始字节**恢复并校验完全一致；正式值永远是 false
    - 不改 Team ID、Bundle ID、iOS icon、export_method 等任何 preset 选项
"""

from __future__ import annotations

import platform
import shutil
import sys
from pathlib import Path
from typing import List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from export_platform import (  # noqa: E402
    begin_ios_project_only_export,
    detect_scheme,
    end_ios_project_only_export,
)
from verify_package import verify  # noqa: E402
from wpg_common import (  # noqa: E402
    ARTIFACTS_DIR,
    BUILD_DIR,
    EXIT_BLOCKED,
    EXIT_FAIL,
    EXIT_PASS,
    EXPORT_PRESETS,
    LOG_DIR,
    PRESETS,
    ROOT,
    Outcome,
    dev_package_basename,
    emit,
    emit_outcome,
    find_godot,
    game_category_outcome,
    godot_version_line,
    godot_version_ok,
    preset_exists,
    preset_options,
    run_cmd,
    templates_ready,
)


def tail(text: Optional[str], lines: int = 60) -> str:
    content = text or ""
    return "\n".join(content.splitlines()[-lines:])


def ci_preflight() -> List[Outcome]:
    """CI 环境检查。只检查与「能否编译」有关的东西，不检查任何 Apple 账号状态。"""
    checks: List[Outcome] = []

    if platform.system() != "Darwin":
        checks.append(Outcome("FAIL", "iOS 构建需要 macOS + Xcode"))
        return checks
    checks.append(Outcome("PASS", "macOS %s" % (platform.mac_ver()[0] or "")))

    xcode = run_cmd(["xcodebuild", "-version"])
    if xcode.returncode != 0:
        checks.append(Outcome("FAIL", "xcodebuild 不可用：%s" % tail(xcode.stdout, 5)))
        return checks
    lines = [line for line in (xcode.stdout or "").strip().splitlines() if line.strip()]
    checks.append(Outcome("PASS", " / ".join(lines[:2])))

    godot = find_godot()
    if godot is None:
        checks.append(Outcome("FAIL", "Missing: Godot"))
        return checks
    version_line = godot_version_line(godot)
    if not godot_version_ok(version_line):
        checks.append(Outcome("FAIL", "Godot 版本是 %r，本仓库要求固定版本" % version_line))
        return checks
    checks.append(Outcome("PASS", "Godot %s（%s）" % (version_line, godot)))

    checks.append(templates_ready("ios"))

    if not preset_exists("ios"):
        checks.append(Outcome("FAIL", "export preset 缺失：iOS"))
    else:
        checks.append(Outcome("PASS", 'export preset: name="iOS" platform="iOS"'))

    options = preset_options("ios")
    if "application/export_project_only" not in options:
        checks.append(
            Outcome(
                "FAIL",
                "iOS preset 缺少 application/export_project_only，无法临时切成 project-only 导出",
            )
        )
    else:
        checks.append(
            Outcome(
                "PASS",
                "export_project_only 当前=%s（导出期间临时置 true，结束后按原始字节恢复）"
                % options.get("application/export_project_only"),
            )
        )

    checks.append(game_category_outcome())
    return checks


def run_godot_project_export(source_dir: Path) -> Outcome:
    """阶段 1：Godot 只生成 Xcode project，导出后按原始字节恢复 export_presets.cfg。"""
    godot = find_godot()
    assert godot is not None

    original_bytes, flipped = begin_ios_project_only_export()
    if not flipped:
        return Outcome(
            "FAIL",
            "无法把 export_project_only 临时置为 true（key 缺失或没有改动），拒绝继续",
        )

    failure = ""
    export_log = LOG_DIR / "export-ios-ci.log"
    try:
        effective = preset_options("ios").get("application/export_project_only", "")
        if effective != "true":
            failure = "export_project_only 临时值是 %r，不是 true，拒绝继续" % effective
        else:
            emit("INFO", "阶段 1/5：Godot iOS export（export_project_only 临时置为 true）")
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
            if proc.returncode != 0:
                failure = "Godot iOS 导出失败，日志：%s\n%s" % (export_log, tail(proc.stdout))
    finally:
        restored = end_ios_project_only_export(original_bytes)

    if not restored or EXPORT_PRESETS.read_bytes() != original_bytes:
        return Outcome(
            "FAIL",
            "export_presets.cfg 未按原始字节恢复，请立刻检查 git diff export_presets.cfg",
        )
    emit("PASS", "export_presets.cfg 已按原始字节恢复并校验")
    if failure:
        return Outcome("FAIL", failure)
    return Outcome("PASS", "Xcode project 生成完成")


def check_project(xcodeproj: Path) -> Tuple[Outcome, str]:
    """阶段 2：确认工程文件与 scheme 都在。返回 (结果, scheme 名)。"""
    pbxproj = xcodeproj / "project.pbxproj"
    if not pbxproj.is_file() or pbxproj.stat().st_size == 0:
        return Outcome("FAIL", "缺少 %s" % pbxproj), ""
    scheme = detect_scheme(xcodeproj)
    if not scheme:
        return Outcome("FAIL", "xcodebuild 读不到 scheme"), ""
    scheme_file = xcodeproj / "xcshareddata" / "xcschemes" / ("%s.xcscheme" % scheme)
    if not scheme_file.is_file():
        shared_dir = xcodeproj / "xcshareddata" / "xcschemes"
        shared = sorted(path.stem for path in shared_dir.glob("*.xcscheme")) if shared_dir.is_dir() else []
        if not shared:
            return Outcome("FAIL", "没有共享 scheme：%s" % scheme_file), ""
        scheme = shared[0]
    emit("PASS", "Xcode project：%s" % xcodeproj.relative_to(ROOT))
    emit("PASS", "scheme = %s" % scheme)
    return Outcome("PASS", "Xcode project 与 scheme 就绪"), scheme


def build_unsigned(xcodeproj: Path, scheme: str, derived: Path) -> Outcome:
    """阶段 3：unsigned xcodebuild。不带 -allowProvisioning*，不联系 Apple。"""
    if derived.exists():
        shutil.rmtree(derived)
    derived.mkdir(parents=True, exist_ok=True)
    log_path = LOG_DIR / "xcodebuild-ios-ci.log"
    emit("INFO", "阶段 3/5：xcodebuild（generic/platform=iOS，CODE_SIGNING_ALLOWED=NO）")
    proc = run_cmd(
        [
            "xcodebuild",
            "-project",
            str(xcodeproj),
            "-scheme",
            scheme,
            "-configuration",
            "Debug",
            "-destination",
            "generic/platform=iOS",
            "-derivedDataPath",
            str(derived),
            "build",
            "CODE_SIGNING_ALLOWED=NO",
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGN_IDENTITY=",
            "PROVISIONING_PROFILE_SPECIFIER=",
        ],
        log_path=log_path,
        timeout=5400,
    )
    if proc.returncode != 0:
        return Outcome(
            "FAIL",
            "unsigned xcodebuild 失败，日志：%s\n%s" % (log_path, tail(proc.stdout)),
        )
    return Outcome("PASS", "unsigned xcodebuild 完成")


def find_built_app(derived: Path) -> Tuple[Outcome, Path]:
    """阶段 4：拿到编译出来的 WPG.app。"""
    products = derived / "Build" / "Products"
    apps = sorted(path for path in products.rglob("*.app") if path.is_dir())
    if not apps:
        return Outcome("FAIL", "xcodebuild 后没有找到任何 .app：%s" % products), Path()
    app = apps[0]
    if not (app / "Info.plist").is_file():
        return Outcome("FAIL", ".app 里没有 Info.plist：%s" % app), Path()
    emit("PASS", ".app：%s" % app)
    return Outcome("PASS", ".app 就绪"), app


def package(app: Path, project_root: Path, artifact: Path) -> Outcome:
    """阶段 5：WPG.app + WPG.xcodeproj + Godot 生成的工程文件 → 一个 zip。

    不把 DerivedData / 任何 cache 放进去。用系统 `zip -r` 打包，这样 .app 里
    如果有符号链接也会被如实保留。
    """
    stage = BUILD_DIR / "ios" / "ci" / "package"
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True, exist_ok=True)

    try:
        shutil.copytree(app, stage / app.name, symlinks=True)
        for item in sorted(project_root.iterdir()):
            target = stage / item.name
            if item.is_dir():
                shutil.copytree(item, target, symlinks=True)
            else:
                shutil.copy2(item, target)
    except OSError as error:
        shutil.rmtree(stage, ignore_errors=True)
        return Outcome("FAIL", "准备打包目录失败：%s" % error)

    names = sorted(path.name for path in stage.iterdir())
    if app.name not in names or "WPG.xcodeproj" not in names:
        shutil.rmtree(stage, ignore_errors=True)
        return Outcome(
            "FAIL",
            "打包目录缺少 .app 或 WPG.xcodeproj：%s" % (", ".join(names) or "(空)"),
        )

    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
    if artifact.exists():
        artifact.unlink()
    log_path = LOG_DIR / "ios-ci-zip.log"
    proc = run_cmd(["zip", "-qry", str(artifact), *names], cwd=stage, log_path=log_path)
    shutil.rmtree(stage, ignore_errors=True)
    if proc.returncode != 0 or not artifact.is_file() or artifact.stat().st_size == 0:
        return Outcome("FAIL", "iOS CI zip 失败，日志：%s\n%s" % (log_path, tail(proc.stdout)))
    return Outcome("PASS", artifact.name)


def main() -> int:
    checks = ci_preflight()
    for check in checks:
        emit_outcome(check)
    failing = [check for check in checks if check.status != "PASS"]
    if failing:
        emit("FAIL", "iOS CI 构建前置检查未通过（见上面的 [FAIL] 行）")
        return EXIT_BLOCKED if all(check.status == "BLOCKED" for check in failing) else EXIT_FAIL

    configuration_dir = BUILD_DIR / "ios" / "ci"
    project_root = configuration_dir / "project"
    xcodeproj = project_root / "WPG.xcodeproj"
    derived = configuration_dir / "dd"
    if configuration_dir.exists():
        shutil.rmtree(configuration_dir)
    project_root.mkdir(parents=True, exist_ok=True)

    result = run_godot_project_export(project_root / "WPG")
    emit_outcome(result)
    if result.status != "PASS":
        return EXIT_BLOCKED if result.status == "BLOCKED" else EXIT_FAIL

    if not xcodeproj.is_dir():
        emit("FAIL", "阶段 2：没有生成 %s" % xcodeproj)
        return EXIT_FAIL
    project_check, scheme = check_project(xcodeproj)
    emit_outcome(project_check)
    if project_check.status != "PASS":
        return EXIT_FAIL

    build_result = build_unsigned(xcodeproj, scheme, derived)
    emit_outcome(build_result)
    if build_result.status != "PASS":
        return EXIT_FAIL

    app_result, app = find_built_app(derived)
    emit_outcome(app_result)
    if app_result.status != "PASS":
        return EXIT_FAIL

    artifact = ARTIFACTS_DIR / dev_package_basename("ios")
    package_result = package(app, project_root, artifact)
    emit_outcome(package_result)
    if package_result.status != "PASS":
        return EXIT_FAIL

    verify_code = verify("ios", False)
    if verify_code != EXIT_PASS:
        return verify_code

    emit("PASS", "unsigned iOS CI package -> %s" % artifact.relative_to(ROOT))
    emit(
        "INFO",
        "这是**未签名**的 CI 构建包（.app + Xcode 工程），不是可安装的 .ipa；"
        "真机安装走本地 Personal Team：python3 tools/build/export_platform.py ios",
    )
    return EXIT_PASS


if __name__ == "__main__":
    sys.exit(main())
