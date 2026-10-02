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
    """Phase 3 + Phase 7 硬约束：Lobby 域对象存在、不碰 ENet、UI 只发命令；
    建连与大厅 @rpc 只允许出现在 lobby/lobby_net.gd。"""
    failures = []
    expected = {
        "lobby/lobby_player.gd": "class_name LobbyPlayer",
        "lobby/room.gd": "class_name Room",
        "lobby/lobby_manager.gd": "class_name LobbyManager",
        "lobby/lobby_net.gd": "class_name LobbyNet",
    }
    for rel, marker in expected.items():
        text = read(ROOT / rel)
        if not text:
            failures.append("缺少 %s" % rel)
            continue
        if marker not in text:
            failures.append("%s 缺少 %s" % (rel, marker))
    # 域对象与 Manager 不碰 ENet / 大厅 RPC：建连、关连、@rpc 全归 LobbyNet。
    for rel in ("lobby/lobby_player.gd", "lobby/room.gd", "lobby/lobby_manager.gd"):
        code = _strip_comments(read(ROOT / rel))
        if "ENetMultiplayerPeer" in code or "multiplayer." in code:
            failures.append("%s 不允许出现 ENet / multiplayer（建连归 LobbyNet）" % rel)
        if "@rpc" in code:
            failures.append("%s 不允许出现大厅 @rpc（只允许 lobby/lobby_net.gd）" % rel)
    room = read(ROOT / "lobby/room.gd")
    if "const MAX_PLAYERS: int = GameLaunch.NET_MAX_SEATS" not in room:
        failures.append("Room 上限必须取自 GameLaunch.NET_MAX_SEATS（= 5）")
    manager = read(ROOT / "lobby/lobby_manager.gd")
    if "func start_match() -> bool" not in manager:
        failures.append("LobbyManager 缺少 start_match()：信封必须由 domain 写")
    # UI 不碰 ENet / @rpc，建连只发 LobbyManager 命令。
    overlay = _strip_comments(read(ROOT / "ui/lan_overlay.gd"))
    if "_lobby.start_match()" not in overlay:
        failures.append("LanOverlay 的 Start 必须走 LobbyManager.start_match()")
    if "_lobby.host_room(" not in overlay and "_lobby.join_room_address(" not in overlay:
        failures.append("LanOverlay 建房 / 连房必须走 LobbyManager 命令（host_room / join_room_address）")
    if "ENetMultiplayerPeer" in overlay or "@rpc" in overlay:
        failures.append("ui/lan_overlay.gd 不允许出现 ENet / @rpc（建连归 lobby/lobby_net.gd）")
    # 全仓库：new ENetMultiplayerPeer 只允许 LobbyNet。
    for path in ROOT.rglob("*.gd"):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(".godot/") or rel.startswith("tools/"):
            continue
        code = _strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        if "ENetMultiplayerPeer.new()" in code and rel != "lobby/lobby_net.gd":
            failures.append("%s 不允许 new ENetMultiplayerPeer（只允许 lobby/lobby_net.gd）" % rel)
    # 战斗 NetSession 不得混进大厅 RPC。
    net = read(ROOT / "arena/net_session.gd")
    for marker in (
        "rpc_hello",
        "rpc_hello_ok",
        "rpc_assign_seat",
        "rpc_roster",
        "rpc_begin",
        "rpc_ready",
        "rpc_apply_ready",
    ):
        if marker in net:
            failures.append("arena/net_session.gd 不允许出现大厅 RPC：%s" % marker)
    # GameLaunch 是换场信封，不是长期 Lobby 单例。
    launch = read(ROOT / "ui/game_launch.gd")
    if "LobbyManager" in launch or "LobbyNet" in launch or "LobbyPlayer" in launch:
        failures.append("ui/game_launch.gd 不得依赖 Lobby 对象（信封不是长期 Lobby 单例）")
    return failures


def _strip_comments(text: str) -> str:
    """去掉 GDScript 行注释，避免注释里的词触发约束。"""
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        lines.append(line)
    return "\n".join(lines)


def _mobile_input_guards() -> list:
    """Touch 必须走 PlayerInput 正式 API；禁止 Touch 直连战斗/网络/暂停。
    UI 依赖 Touch -> emulated Mouse compatibility，Gameplay 隔离由 Touch source +
    DEVICE_ID_EMULATION filter 负责，而不是全局关闭 Mouse emulation。"""
    failures = []
    project = read(ROOT / "project.godot")
    if "pointing/emulate_mouse_from_touch=false" in project:
        failures.append(
            "project.godot 不得关闭 pointing/emulate_mouse_from_touch（标准 UI 依赖 Touch->Mouse）"
        )
    forbidden_imports = [
        ("WeaponHost", "Touch 层不得直连 WeaponHost"),
        ("PauseOverlay", "Touch 层不得直连 PauseOverlay"),
        ("NetSession", "Touch 层不得直连 NetSession"),
        ("ENetMultiplayerPeer", "Touch 层不得直连 ENet"),
    ]
    forbidden_classnames = [
        "TouchPlayer",
        "TouchPlayerInput",
        "TouchCombat",
    ]
    for path in ROOT.rglob("*.gd"):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(".godot/") or rel.startswith("tools/"):
            continue
        is_touch_layer = rel.startswith("ui/mobile/")
        text = path.read_text(encoding="utf-8", errors="replace")
        for name in forbidden_classnames:
            if ("class_name %s" % name) in text:
                failures.append("%s 引入了禁止的 Touch 类名 %s" % (rel, name))
        if not is_touch_layer:
            continue
        if rel.endswith("touch_action_button.gd") or rel.endswith("virtual_stick.gd"):
            continue
        code = _strip_comments(text)
        for marker, why in forbidden_imports:
            if marker in code:
                failures.append("%s：%s" % (rel, why))
    # 正式触屏场景不得保留默认 FIRE 大按钮。
    scene = read(ROOT / "ui/mobile/touch_controls.tscn")
    if "FireButton" in scene:
        failures.append("touch_controls.tscn 不得保留默认 FIRE 按钮（右摇杆 = Aim + Fire）")
    if "PauseButton" not in scene:
        failures.append("touch_controls.tscn 缺少 PauseButton")
    if "Weapon1Button" not in scene or "Weapon4Button" not in scene:
        failures.append("touch_controls.tscn 缺少 Weapon 1~4 按钮")
    pi_text = read(ROOT / "player/player_input.gd")
    for api in ("set_touch_move_vector", "set_touch_aim_vector", "set_touch_fire_held", "queue_touch_dash", "queue_touch_weapon_slot"):
        if api not in pi_text:
            failures.append("PlayerInput 缺少正式 Touch API：%s" % api)
    # gameplay fire 不得在 Touch source active 时读键鼠/模拟鼠标。
    if "_touch_enabled" not in pi_text or "if _touch_enabled:" not in pi_text:
        failures.append("PlayerInput 必须按 _touch_enabled 独占 Touch source")
    # TouchActionButton / VirtualStick 必须过滤模拟鼠标，避免 ScreenTouch + emulated Mouse 双触发。
    for rel, name in (("ui/mobile/touch_action_button.gd", "TouchActionButton"), ("ui/mobile/virtual_stick.gd", "VirtualStick")):
        code = _strip_comments(read(ROOT / rel))
        if "DEVICE_ID_EMULATION" not in code:
            failures.append("%s 必须过滤 InputEvent.DEVICE_ID_EMULATION 模拟鼠标" % name)
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
    failures.extend(_mobile_input_guards())
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
