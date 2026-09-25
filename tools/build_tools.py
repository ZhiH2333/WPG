#!/usr/bin/env python3
"""WPG 本地构建菜单。真正的检查和导出都在 tools/ci、tools/build、tools/release。"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from wpg_common import (  # noqa: E402
    PLATFORMS,
    PRESETS,
    ROOT,
    emit,
    find_godot,
    git_output,
    platform_prereq,
    preset_exists,
    read_project_version,
    set_project_version,
    tag_for_version,
    tool_versions,
    version_is_valid,
    working_tree_dirty,
)


def run_script(relative: str, args: list) -> int:
    command = [sys.executable, str(ROOT / relative), *args]
    return subprocess.run(command).returncode


def print_header() -> None:
    info = tool_versions()
    print("")
    print("====================================")
    print("WPG BUILD TOOLS")
    print("====================================")
    print("Project Version: %s" % info["version"])
    print("Git Branch: %s" % info["branch"])
    print("Git Commit: %s" % info["commit"])
    if info["tag"]:
        print("Tag: %s" % info["tag"])
    print("Godot: %s" % info["godot"])
    print("Python: %s" % info["python"])
    print("Git: %s" % info["git"])
    print("")


def print_menu() -> None:
    print("1. Run CI Checks")
    print("2. Build Windows")
    print("3. Build macOS")
    print("4. Build Linux")
    print("5. Build Android APK")
    print("6. Build Web")
    print("7. Build All Platforms")
    print("8. Show Version")
    print("9. Set Version")
    print("10. Check Release Readiness")
    print("11. Create Release Tag")
    print("12. Exit")
    print("")


def show_version() -> int:
    info = tool_versions()
    print("Project Version:")
    print(info["version"])
    print("Git Branch:")
    print(info["branch"])
    print("Git Commit:")
    print(info["commit"])
    if info["tag"]:
        print("Tag:")
        print(info["tag"])
    return 0


def set_version_interactive(preset: str = "") -> int:
    current = read_project_version() or "MISSING"
    print("Current version:")
    print(current)
    if preset:
        entered = preset.strip()
    else:
        entered = input("New version (MAJOR.MINOR.PATCH): ").strip()
    if not entered:
        emit("INFO", "已取消，未修改版本")
        return 0
    outcome = set_project_version(entered)
    emit(outcome.status, outcome.message)
    if outcome.status != "PASS":
        return outcome.exit_code
    print("Project Version: %s" % read_project_version())
    return 0


def origin_main_matches_head() -> tuple:
    fetch = subprocess.run(
        ["git", "fetch", "origin", "main"],
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if fetch.returncode != 0:
        return False, "无法 fetch origin/main，不能确认 main HEAD"
    code, head = git_output(["rev-parse", "HEAD"])
    main_code, main_head = git_output(["rev-parse", "origin/main"])
    if code != 0 or main_code != 0:
        return False, "无法解析 HEAD 或 origin/main"
    if head != main_head:
        return False, "当前 commit 不是 origin/main（%s != %s）" % (head[:7], main_head[:7])
    return True, head[:7]


def tag_exists(tag: str) -> bool:
    code, _text = git_output(["rev-parse", "--verify", "refs/tags/%s" % tag])
    if code == 0:
        return True
    remote_code, remote_text = git_output(["ls-remote", "--tags", "origin", "refs/tags/%s" % tag])
    return remote_code == 0 and bool(remote_text)


def check_readiness() -> int:
    print("Release Readiness")
    print("")
    blocked = False
    failed = False
    branch_code, branch = git_output(["rev-parse", "--abbrev-ref", "HEAD"])
    if branch_code != 0 or branch != "main":
        emit("FAIL", "Branch is not main（当前 %s）" % branch)
        failed = True
    else:
        emit("PASS", "Branch = main")
    if working_tree_dirty():
        emit("FAIL", "Working tree is not clean")
        failed = True
    else:
        emit("PASS", "Working tree clean")
    ok_head, head_message = origin_main_matches_head()
    if ok_head:
        emit("PASS", "Commit = main HEAD %s" % head_message)
    else:
        emit("FAIL", head_message)
        failed = True
    version = read_project_version()
    if version is None:
        emit("FAIL", "project.godot version 不存在")
        failed = True
    elif not version_is_valid(version):
        emit("FAIL", "版本格式不对：%s" % version)
        failed = True
    else:
        emit("PASS", "Version = %s" % version)
        tag = tag_for_version(version)
        if tag_exists(tag):
            emit("FAIL", "Git tag 已存在：%s" % tag)
            failed = True
        else:
            emit("PASS", "Tag %s 尚未占用" % tag)
    missing_presets = [name for key, name in PRESETS.items() if not preset_exists(key)]
    if missing_presets:
        emit("FAIL", "Export presets 缺失：%s" % ", ".join(missing_presets))
        failed = True
    else:
        emit("PASS", "Export presets")
    print("")
    emit("INFO", "开始跑 WPG CI checks")
    ci_code = run_script("tools/ci/run_ci.py", [])
    if ci_code == 0:
        emit("PASS", "CI checks")
    else:
        emit("FAIL", "CI checks")
        failed = True
    print("")
    for platform_key in PLATFORMS:
        prereq = platform_prereq(platform_key)
        label = "%s 构建条件" % platform_key
        if prereq.status == "PASS":
            emit("PASS", label)
        elif prereq.status == "BLOCKED":
            emit("BLOCKED", "%s — %s" % (label, prereq.message))
            blocked = True
        else:
            emit("FAIL", "%s — %s" % (label, prereq.message))
            failed = True
    print("")
    if failed:
        emit("FAIL", "Not ready to create release tag.")
        return 1
    if blocked:
        emit("BLOCKED", "CI 可以通过，但有平台目前不能构建。不要创建正式 tag。")
        return 2
    emit("PASS", "Ready to create release tag.")
    return 0


def create_release_tag() -> int:
    branch_code, branch = git_output(["rev-parse", "--abbrev-ref", "HEAD"])
    if branch_code != 0 or branch != "main":
        emit("FAIL", "禁止创建 Tag：当前不是 main")
        return 1
    if working_tree_dirty():
        emit("FAIL", "禁止创建 Tag：working tree 不干净")
        return 1
    version = read_project_version()
    if version is None or not version_is_valid(version):
        emit("FAIL", "禁止创建 Tag：project.godot 版本无效")
        return 1
    ok_head, head_message = origin_main_matches_head()
    if not ok_head:
        emit("FAIL", "禁止创建 Tag：%s" % head_message)
        return 1
    tag = tag_for_version(version)
    if tag_exists(tag):
        emit("FAIL", "禁止创建 Tag：%s 已存在" % tag)
        return 1
    answer = input("Create tag %s? [y/N] " % tag).strip().lower()
    if answer not in ("y", "yes"):
        emit("INFO", "已取消，未创建 tag，未 push")
        return 0
    created = subprocess.run(["git", "tag", "-a", tag, "-m", tag], cwd=str(ROOT))
    if created.returncode != 0:
        emit("FAIL", "创建本地 tag 失败")
        return 1
    pushed = subprocess.run(["git", "push", "origin", tag], cwd=str(ROOT))
    if pushed.returncode != 0:
        subprocess.run(["git", "tag", "-d", tag], cwd=str(ROOT))
        emit("FAIL", "push tag 失败，已删除本地 tag。没有创建 GitHub Release。")
        return 1
    emit("PASS", "已 push %s。WPG Release 会在 GitHub 上自动运行。" % tag)
    emit("INFO", "Create Tag 不等于 GitHub Release。Release 由 WPG Release workflow 创建。")
    return 0


def dispatch(choice: str) -> int:
    if choice == "1":
        return run_script("tools/ci/run_ci.py", [])
    if choice == "2":
        return run_script("tools/build/export_platform.py", ["windows"])
    if choice == "3":
        return run_script("tools/build/export_platform.py", ["macos"])
    if choice == "4":
        return run_script("tools/build/export_platform.py", ["linux"])
    if choice == "5":
        return run_script("tools/build/export_platform.py", ["android"])
    if choice == "6":
        return run_script("tools/build/export_platform.py", ["web"])
    if choice == "7":
        return run_script("tools/build/build_all.py", [])
    if choice == "8":
        return show_version()
    if choice == "9":
        return set_version_interactive()
    if choice == "10":
        return check_readiness()
    if choice == "11":
        return create_release_tag()
    if choice == "12":
        return 0
    emit("FAIL", "没有这个选项：%s" % choice)
    return 1


def startup_checks() -> None:
    info = tool_versions()
    if info["git"] != "ok":
        emit("FAIL", "Missing: Git")
    if find_godot() is None:
        emit("WARN", "Missing: Godot。CI 和 Build 会失败，菜单仍可打开。")
    elif not str(info["godot"]).startswith("4.6.2"):
        emit("WARN", "Godot 不是 4.6.2：%s" % info["godot"])


def main() -> int:
    startup_checks()
    if len(sys.argv) > 1:
        print_header()
        choice = sys.argv[1].strip()
        if choice == "9" and len(sys.argv) > 2:
            print_header()
            return set_version_interactive(sys.argv[2])
        return dispatch(choice)
    while True:
        print_header()
        print_menu()
        try:
            choice = input("Select: ").strip()
        except EOFError:
            print("")
            return 0
        if choice == "12":
            return 0
        code = dispatch(choice)
        if code != 0:
            emit("FAIL" if code != 2 else "BLOCKED", "选项 %s 结束，exit %s" % (choice, code))
        else:
            emit("PASS", "选项 %s 结束" % choice)


if __name__ == "__main__":
    sys.exit(main())
