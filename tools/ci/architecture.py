#!/usr/bin/env python3
"""架构约束检查。只读仓库，不改游戏代码。任一失败返回非 0。"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import (  # noqa: E402
    EXPORT_PRESETS,
    PRESETS,
    PROJECT_GODOT,
    ROOT,
    emit,
    read_project_version,
    version_is_valid,
)


def read(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8")


def _lobby_guards() -> list:
    """Phase 3 硬约束：Lobby 域对象存在、不碰 ENet、UI 只发命令。"""
    failures = []
    expected = {
        "lobby/lobby_player.gd": "class_name LobbyPlayer",
        "lobby/room.gd": "class_name Room",
        "lobby/lobby_manager.gd": "class_name LobbyManager",
    }
    for rel, marker in expected.items():
        text = read(ROOT / rel)
        if not text:
            failures.append("缺少 %s" % rel)
            continue
        if marker not in text:
            failures.append("%s 缺少 %s" % (rel, marker))
        if "ENetMultiplayerPeer" in text or "multiplayer." in text:
            failures.append("%s 不允许出现 ENet / multiplayer（建连归 LobbyNet）" % rel)
    room = read(ROOT / "lobby/room.gd")
    if "const MAX_PLAYERS: int = GameLaunch.NET_MAX_SEATS" not in room:
        failures.append("Room 上限必须取自 GameLaunch.NET_MAX_SEATS（= 5）")
    manager = read(ROOT / "lobby/lobby_manager.gd")
    if "func start_match() -> bool" not in manager:
        failures.append("LobbyManager 缺少 start_match()：信封必须由 domain 写")
    overlay = read(ROOT / "ui/lan_overlay.gd")
    if "_lobby.start_match()" not in overlay:
        failures.append("LanOverlay 的 Start 必须走 LobbyManager.start_match()")
    if "note_peer_connecting" not in overlay:
        failures.append("LanOverlay 未把 peer 事件转给 LobbyManager")
    return failures


def main() -> int:
    failures = []
    project = read(PROJECT_GODOT)
    if not project:
        failures.append("缺少 project.godot")
    else:
        if "\n[autoload]" in "\n" + project:
            failures.append("project.godot 出现 [autoload]，Autoload 必须为 0")
        if '"4.6"' not in project:
            failures.append("config/features 未包含 4.6")
        if "Forward Plus" not in project:
            failures.append("config/features 未包含 Forward Plus")
        if 'run/main_scene="res://ui/main_menu.tscn"' not in project:
            failures.append("主场景不是 res://ui/main_menu.tscn")
    version = read_project_version()
    if version is None:
        failures.append("application/config/version 不存在")
    elif not version_is_valid(version):
        failures.append("application/config/version 不是 MAJOR.MINOR.PATCH：%s" % version)
    else:
        emit("PASS", "Project Version: %s" % version)
    if (ROOT / "version.txt").exists():
        failures.append("存在第二套版本文件 version.txt")
    launch = read(ROOT / "ui/game_launch.gd")
    if "const NET_PORT: int = 17777" not in launch:
        failures.append("GameLaunch.NET_PORT 不是 17777")
    if "const NET_DISCOVER_PORT: int = 17778" not in launch:
        failures.append("GameLaunch.NET_DISCOVER_PORT 不是 17778")
    if "const NET_PROTOCOL: int = 5" not in launch:
        failures.append("GameLaunch.NET_PROTOCOL 不是 5")
    net = read(ROOT / "arena/net_session.gd")
    if "class_name NetSession" not in net:
        failures.append("arena/net_session.gd 缺少 class_name NetSession")
    for path in ROOT.rglob("*.gd"):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(".godot/") or rel.startswith("tools/"):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if "class_name NetworkSession" in text or "class_name CombatSession" in text:
            failures.append("%s 引入了禁止的网络类名" % rel)
    failures.extend(_lobby_guards())
    presets = read(EXPORT_PRESETS)
    for key, name in PRESETS.items():
        if ('name="%s"' % name) not in presets:
            failures.append("export preset 缺失：%s" % name)
        else:
            emit("PASS", "Export preset %s" % key)
    if failures:
        for item in failures:
            emit("FAIL", item)
        return 1
    emit("PASS", "Architecture Guard")
    return 0


if __name__ == "__main__":
    sys.exit(main())
