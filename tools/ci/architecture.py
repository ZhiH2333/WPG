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
    # Phase 8：URI / token / 候选选择全部归 domain，UI 只发命令。
    if "wpg://" in overlay:
        failures.append("LanOverlay 不许自己拼 wpg:// URI（必须走 LobbyManager.create_invite）")
    if "_lobby.create_invite(" not in overlay:
        failures.append("LanOverlay 的 Copy Invite 必须走 LobbyManager.create_invite()")
    if "JoinInvite.generate_token" in overlay:
        failures.append("LanOverlay 不许自己生成 token（归 JoinInvite / LobbyManager）")
    # ConnectionPath 只描述候选，绝不持有 peer / 建连。
    if (ROOT / "lobby/connection_path.gd").is_file():
        path_code = _strip_comments(read(ROOT / "lobby/connection_path.gd"))
        for marker in ("ENetMultiplayerPeer", "@rpc", "create_client", "create_server"):
            if marker in path_code:
                failures.append("lobby/connection_path.gd 只是候选描述，不允许出现 %s" % marker)
    # Phase 9.1：P2P state / rendezvous contract / 编排器必须保持"纯"。
    # - 状态对象只描述状态；contract 只描述数据；两者都不许碰 ENet / @rpc。
    # - ConnectionPath 与编排器都不持有 peer（建连只经注入的 transport -> LobbyNet）。
    pure_objects = {
        "lobby/p2p_connection_state.gd": "P2P 状态对象",
        "lobby/rendezvous_contract.gd": "Rendezvous contract",
        "lobby/connect_attempt.gd": "ConnectAttempt",
    }
    for rel, name in pure_objects.items():
        if not (ROOT / rel).is_file():
            failures.append("缺少 %s（%s）" % (rel, name))
            continue
        code = _strip_comments(read(ROOT / rel))
        for marker in ("ENetMultiplayerPeer", "@rpc", "multiplayer.", "SceneTree"):
            if marker in code:
                failures.append("%s（%s）只是纯对象，不允许出现 %s" % (rel, name, marker))
    # 编排器不创建 ENet、不发 @rpc；建连必须走注入的 transport（归 LobbyNet）。
    orchestrator = _strip_comments(read(ROOT / "lobby/p2p_connection.gd"))
    if not orchestrator:
        failures.append("缺少 lobby/p2p_connection.gd（Phase 9.1 编排器）")
    else:
        if "ENetMultiplayerPeer" in orchestrator:
            failures.append("lobby/p2p_connection.gd 不允许创建 ENet peer（归 lobby/lobby_net.gd）")
        if "@rpc" in orchestrator:
            failures.append("lobby/p2p_connection.gd 不允许出现 @rpc（大厅 RPC 归 lobby/lobby_net.gd）")
        if "bind_transport" not in orchestrator:
            failures.append("lobby/p2p_connection.gd 必须通过 bind_transport() 注入传输层")
    # 编排器 / contract 不许被 UI 直接使用（UI 只经 LobbyManager）。
    for path in sorted(ROOT.rglob("*.gd")):
        rel = path.relative_to(ROOT).as_posix()
        if not rel.startswith("ui/"):
            continue
        code = _strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        for marker in ("RendezvousContract", "P2PConnectionState", "P2PConnection"):
            if marker in code:
                failures.append("%s：UI 不得直接接触 %s（必须经 LobbyManager）" % (rel, marker))
        # Phase 9.2.1：UI 也不得接触 rendezvous 的 packet format / 客户端。
        # 注意：不要用泛化的 "decode(" —— 那会和 UI 自己的解码逻辑撞名。
        for marker in ("RendezvousClient", "PacketPeerUDP", "encode_register"):
            if marker in code:
                failures.append("%s：UI 不得接触 rendezvous packet format（%s）" % (rel, marker))
    # Phase 9.2.1：rendezvous_client 是 UDP 层，绝不允许抢 LobbyNet 的 ENet / 大厅 RPC。
    rv_client_rel = "lobby/rendezvous_client.gd"
    if not (ROOT / rv_client_rel).is_file():
        failures.append("缺少 %s（Phase 9.2.1 rendezvous 客户端）" % rv_client_rel)
    else:
        rv_client = _strip_comments(read(ROOT / rv_client_rel))
        for marker in ("ENetMultiplayerPeer", "@rpc"):
            if marker in rv_client:
                failures.append(
                    "%s 不允许出现 %s（ENet 与大厅 RPC 只归 lobby/lobby_net.gd）" % (rv_client_rel, marker)
                )
        if "PacketPeerUDP" not in rv_client:
            failures.append("%s 必须用 PacketPeerUDP（rendezvous 走 UDP，不占 SceneTree peer）" % rv_client_rel)
        # 不允许它经 multiplayer 改 SceneTree 的 active peer。
        if "multiplayer.multiplayer_peer" in rv_client:
            failures.append("%s 不允许改 SceneTree.multiplayer.multiplayer_peer" % rv_client_rel)
    # rendezvous server 只做发现：不许访问 Combat，也不许承载游戏包。
    rv_server_rel = "tools/p2p/rendezvous/server.py"
    if not (ROOT / rv_server_rel).is_file():
        failures.append("缺少 %s（Phase 9.2.1 rendezvous 服务端）" % rv_server_rel)
    else:
        rv_server = read(ROOT / rv_server_rel)
        for marker in ("net_session", "NetSession", "combat_sandbox", "LobbyNet", "snapshot"):
            if marker in rv_server:
                failures.append("%s 只是发现服务，不允许访问 Combat / Lobby（%s）" % (rv_server_rel, marker))
    # rendezvous 协议模块同样不许碰游戏 / 战斗。
    rv_proto_rel = "tools/p2p/rendezvous/protocol.py"
    if (ROOT / rv_proto_rel).is_file():
        rv_proto = read(ROOT / rv_proto_rel)
        for marker in ("net_session", "combat", "LobbyNet"):
            if marker in rv_proto:
                failures.append("%s 只是编解码，不允许访问 %s" % (rv_proto_rel, marker))
    # LanBeacon 只做发现，不是认证 / 不是游戏流量。
    beacon = _strip_comments(read(ROOT / "arena/lan_beacon.gd"))
    for marker in ("ENetMultiplayerPeer", "@rpc", "check_ticket"):
        if marker in beacon:
            failures.append("arena/lan_beacon.gd 只是 LAN discovery，不允许出现 %s" % marker)
    # 全仓库：new ENetMultiplayerPeer 只允许 LobbyNet。
    # 例外只限于**明确列出的测试文件**：
    # - connection_path_test：必须亲手持有/替换 peer，才能证明「候选回退过程中
    #   SceneTree 始终只有一个 peer」这条 Phase 8 硬约束。
    # 新增测试例外必须逐个列出，绝不扩大生产代码白名单。
    ENet_ALLOWED = {
        "lobby/lobby_net.gd",
        "tests/connection_path_test.gd",
    }
    for path in ROOT.rglob("*.gd"):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(".godot/") or rel.startswith("tools/"):
            continue
        code = _strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        if "ENetMultiplayerPeer.new()" in code and rel not in ENet_ALLOWED:
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


def _node_block(text: str, name: str) -> str:
    """取 .tscn 里某个 [node name="X" ...] 段落（到下一个 [node ...] 为止）。"""
    marker = '[node name="%s"' % name
    start = text.find(marker)
    if start < 0:
        return ""
    end = text.find("[node ", start + len(marker))
    return text[start:end if end >= 0 else len(text)]


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
    # 默认合同仍是「右摇杆 = Aim + Fire」：FIRE 按钮可以存在（Manual Fire ON 用），
    # 但必须默认隐藏，且可见性只由 GameSettings.is_touch_manual_fire() 决定。
    scene = read(ROOT / "ui/mobile/touch_controls.tscn")
    if "FireButton" not in scene:
        failures.append("touch_controls.tscn 缺少 FireButton（Manual Fire ON 需要）")
    elif "visible = false" not in _node_block(scene, "FireButton"):
        failures.append("touch_controls.tscn 的 FireButton 必须默认隐藏（默认右摇杆 = Aim + Fire）")
    if "fire_button_path" not in scene:
        failures.append("touch_controls.tscn 必须把 TouchInput.fire_button_path 绑到 FireButton")
    if "PauseButton" not in scene:
        failures.append("touch_controls.tscn 缺少 PauseButton")
    if "Weapon1Button" not in scene or "Weapon4Button" not in scene:
        failures.append("touch_controls.tscn 缺少 Weapon 1~4 按钮")
    controls = _strip_comments(read(ROOT / "ui/mobile/touch_controls.gd"))
    if "is_touch_manual_fire" not in controls:
        failures.append("TouchControls 必须按 GameSettings.is_touch_manual_fire() 同步 FIRE 按钮可见性")
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


def _ui_display_guards() -> list:
    """硬规定：任何界面都不显示「本局获得的技能 / 物品 / 状态」清单。

    结算页（winner_page）与 profile 曾经把本局获得的升级 id 原样列出来（以及 shop 的
    owned 列表），已全部移除。这条约束用 API 级别把关，避免换个写法又加回来：
    UI 层不得读取本局获得的升级清单。
    """
    failures = []
    forbidden = (
        "get_owned_upgrade_ids",
        "get_owned_count",
    )
    for path in sorted(ROOT.rglob("*.gd")):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(".godot/") or rel.startswith("tools/"):
            continue
        if not rel.startswith("ui/"):
            continue
        code = _strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        for marker in forbidden:
            if marker in code:
                failures.append(
                    "%s：UI 不得读取本局获得的升级清单（%s）——任何界面都不显示它" % (rel, marker)
                )
    # 结算页与 profile 里「owned」字样本身也必须消失，防止换个 API 再展示一次。
    for rel in (
        "ui/winner_page.gd",
        "ui/winner_page.tscn",
        "ui/profile_overlay.gd",
        "ui/profile_overlay.tscn",
        "ui/shop_offer.gd",
        "ui/shop_offer.tscn",
    ):
        text = read(ROOT / rel)
        if "owned" in text.lower():
            failures.append("%s 不得再出现 owned 展示（硬规定：不显示本局获得的物品）" % rel)
    return failures


def _icon_guards() -> list:
    """图标接线守卫：预设引用的 res:// 图标必须真实存在，且导出期素材不进 PCK。"""
    failures = []
    project = read(PROJECT_GODOT)
    if 'config/icon="res://icon.png"' not in project:
        failures.append("application/config/icon 未指向 res://icon.png")
    if not (ROOT / "icon.png").is_file():
        failures.append("缺少项目图标 icon.png（跑 tools/icons/generate_icons.py 生成）")
    if 'boot_splash/image="res://icons/splash.png"' not in project:
        failures.append("application/boot_splash/image 未指向 res://icons/splash.png")
    # 默认 stretch_mode=1(Keep) 会按窗口长边撑满：横屏时字标被裁成中间一小段。
    # 2(Keep Width) 才保证整条字标等比完整可见，也是 boot_screen.gd 复刻的规则。
    if "boot_splash/stretch_mode=2" not in project:
        failures.append("boot_splash/stretch_mode 必须是 2(Keep Width)，否则横屏会裁掉字标")
    for name in ("logo.png", "splash.png"):
        if not (ROOT / "icons" / name).is_file():
            failures.append("缺少开屏素材 icons/%s（跑 tools/icons/generate_icons.py 生成）" % name)
    if (ROOT / "icons" / ".gdignore").is_file():
        failures.append("icons/.gdignore 会让 splash.png 无法被导入，开屏会失效")
    boot_screen = read(ROOT / "ui" / "boot_screen.gd")
    if 'const MENU_SCENE := "res://ui/main_menu.tscn"' not in boot_screen:
        failures.append("ui/boot_screen.gd 必须把 ui/main_menu.tscn 作为 MENU_SCENE")
    # 导出期素材目录必须整体忽略，否则 1024 PNG 会被打进每个平台的 PCK。
    for name in ("ios", "macos", "android", "windows", "web", "wpg_iOS_Exports"):
        if not (ROOT / "icons" / name / ".gdignore").is_file():
            failures.append("icons/%s/.gdignore 缺失：导出期图标会被当资源打进 PCK" % name)
    stray = sorted(
        path.relative_to(ROOT).as_posix()
        for name in ("ios", "macos", "android", "windows", "web", "wpg_iOS_Exports")
        for path in (ROOT / "icons" / name).rglob("*.import")
    )
    if stray:
        failures.append("导出期图标目录里出现 Godot 导入残留：%s" % ", ".join(stray[:3]))
    if not (ROOT / "wpg.icon" / "icon.json").is_file():
        failures.append("缺少 wpg.icon/icon.json：图标唯一真源")

    required_exact = {
        "application/icon",
        "application/console_wrapper_icon",
        "application/liquid_glass_icon",
    }
    required_prefixes = ("icons/", "launcher_icons/", "progressive_web_app/icon_")
    checked = set()
    for line in read(EXPORT_PRESETS).splitlines():
        key, sep, value = line.partition("=")
        key = key.strip()
        if not sep:
            continue
        if key not in required_exact and not key.startswith(required_prefixes):
            continue
        value = value.strip().strip('"')
        if not value.startswith("res://"):
            failures.append("%s 未指向图标资源：%s" % (key, value or "(空)"))
            continue
        rel = value[len("res://") :]
        if rel in checked:
            continue
        checked.add(rel)
        if not (ROOT / rel).exists():
            failures.append("%s 指向不存在的文件：%s" % (key, value))
    if not failures:
        emit("PASS", "图标接线（%d 个资源）" % len(checked))
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
        if 'run/main_scene="res://ui/boot_screen.tscn"' not in project:
            failures.append("主场景必须是 res://ui/boot_screen.tscn（开屏：字标 + 进度条）")
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
    # 协议 6（Phase 8）：JoinInvite / ConnectionPath / ticket handshake 唯一一次 bump。
    if "const NET_PROTOCOL: int = 6" not in launch:
        failures.append("GameLaunch.NET_PROTOCOL 不是 6")
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
    failures.extend(_ui_display_guards())
    failures.extend(_icon_guards())
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
