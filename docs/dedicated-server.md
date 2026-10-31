# WPG Dedicated Server — Local Startup (Phase 2B / 2C)

Online Dedicated Server 是与 LAN / Host-Guest / WAN-P2P **并行**的路径。

| 路径 | ENet 所有者 | 座位 | 默认端口 | 权威方 |
|---|---|---|---|---|
| LAN / P2P（遗留） | `LobbyNet` | 5（`GameLaunch.NET_MAX_SEATS`） | 17777 UDP | 玩家 Host |
| Online Dedicated Server | `DsNet` + `OnlineChannel` | 4（`OnlineProtocol.MAX_PLAYERS`） | 24567 UDP | Headless Dedicated Server |

不要把 LAN room ticket 当作 Online game ticket。  
**生产身份** = WildBoat `game_ticket`；`WPG_DEV_TOKEN` 仅 `admission_mode=dev`。

契约原文：`docs/phase-2b-api-contract.md`。

## 实现状态

| 能力 | 状态 |
|---|---|
| DS listen / 权威快照 / 4 人上限 | **已实现** + 自动化 E2E |
| WPass Auth 客户端 | **已实现** |
| Assignment `POST /v1/games/assign` | **已实现**（真实 WildBoat） |
| DS register + heartbeat | **已实现** |
| Ticket Admission（WildBoat validate） | **已实现**（fail closed） |
| Settlement S2S | **已实现**（最小幂等结算） |
| Phase 2D 游戏世界玩家实体 + 双向移动 | **已实现**（`GameLaunch.NetRole.ONLINE` → `combat_sandbox`） |
| Snapshot v2（match_id / pos / facing） | **已实现** |
| Leave / 断线清理远端实体 | **已实现**（不支持静默重连） |
| 双客户端真实 Online E2E | `tools/e2e/dedicated/run_wildboat_online.py` |
| 双客户端世界同步 E2E | `tools/e2e/dedicated/run_world_sync.py` |
| 双客户端游戏世界实体 E2E | `tools/e2e/dedicated/run_world_entities.py`（加载 `combat_sandbox`） |
| 双客户端 stub Online | `tools/e2e/dedicated/run_stub_online.py` |
| Solo / LAN 回归 | 现有 e2e |
| 玩家小白指南 | `docs/phase-2d-player-multiplayer-test.md` |

## Traffic boundary

- **ENet/UDP**：实时游戏（默认 `24567/udp`）。
- **HTTPS**：WPass / Assignment / ticket validate / settlement → WildBoat。
- Cloudflare Worker **不是** UDP 代理。
- Docker 镜像只暴露游戏 UDP 端口。
- **S2S 凭证绝不进入 Godot Client。**

## Prerequisites

- Godot **4.6.2**（`GODOT_BIN`）
- 本机 WildBoat + PostgreSQL（`make up` in WildBoat）

```bash
export GODOT_BIN="$PWD/build/netlify-godot/wpg-godot/editor/Godot.app/Contents/MacOS/Godot"
export DEDICATED_SERVER_CREDENTIAL='local-ds-credential-32chars-min!!'  # 与 WildBoat .env 一致；勿提交
```

## Start server (headless)

```bash
# Dev admission（Phase 2A 兼容）
WPG_ADMISSION_MODE=dev WPG_DEV_TOKEN=dev WPG_GAME_PORT=24567 WPG_MAX_PLAYERS=4 \
  "$GODOT_BIN" --headless --path . -- --dedicated-server

# Stub ticket admission（本地联调；非生产）
WPG_ADMISSION_MODE=stub WPG_MATCH_ID=dev_match WPG_GAME_INSTANCE_ID=dev_instance \
  WPG_GAME_PORT=24567 \
  "$GODOT_BIN" --headless --path . -- --dedicated-server

# 真实 WildBoat（注册 + 心跳 + 在线验票）
WPG_ADMISSION_MODE=wildboat \
  WPG_WILDBOAT_BASE_URL=http://127.0.0.1:8080 \
  DEDICATED_SERVER_CREDENTIAL="$DEDICATED_SERVER_CREDENTIAL" \
  WPG_ADVERTISE_HOST=127.0.0.1 \
  WPG_GAME_PORT=24567 \
  "$GODOT_BIN" --headless --path . -- --dedicated-server
```

成功 stdout：

```text
WPG_DS_LISTEN port=24567 max_players=4 protocol=1 admission=2
WPG_DS_REGISTERED instance=... server=...
WPG_DS_READY
```

## Configuration

| Variable / CLI | Meaning | Default |
|---|---|---|
| `WPG_GAME_PORT` / `--port=` | ENet UDP | `24567` |
| `WPG_MAX_PLAYERS` / `--max-players=` | Online cap ≤4 | `4` |
| `WPG_ADMISSION_MODE` / `--admission-mode=` | `dev` \| `stub` \| `wildboat` | `dev` |
| `WPG_DEV_TOKEN` / `--dev-token=` | Dev shared secret | empty=open |
| `WPG_MATCH_ID` | 初始 match（wildboat 下由验票覆盖） | `dev_match` |
| `WPG_GAME_INSTANCE_ID` | skip-register 时使用 | `dev_instance` |
| `WPG_WILDBOAT_BASE_URL` | WildBoat base | `http://127.0.0.1:8080` |
| `DEDICATED_SERVER_CREDENTIAL` | S2S 凭证（**勿进客户端**） | empty |
| `WPG_WILDBOAT_SERVER_TOKEN` | 同上（兼容旧名） | empty |
| `WPG_ADVERTISE_HOST` | 注册到 WildBoat 的 host | `127.0.0.1` |
| `WPG_HEARTBEAT_INTERVAL_SEC` | 心跳间隔 | `10` |
| `WPG_SERVER_BUILD` | register/build 标识 | `wpg-ds-local` |
| `WPG_READY_FILE` / `--ready-file=` | Readiness marker | `user://wpg_ds_ready` |
| `WPG_TICK_HZ` | Snapshot Hz | `20` |
| `WPG_DEDICATED_SERVER=1` | Force dedicated boot | off |

## 真实 Online 联调

### 玩家 UI（Phase 2C，推荐）

小白步骤见 **`docs/phase-2c-player-online-test.md`**。

```text
双击 tools/online/一键启动本地Online测试.command
双击 tools/online/打开两个游戏窗口.command
游戏内：MULTIPLAYER → Online (test) → Login → Join Match
```

脚本等价命令：`tools/online/start_local_online_test.sh` / `open_two_clients.sh` / `stop_local_online_test.sh`。

### 开发者联调

1. 启动 WildBoat（`make up && make smoke`）。
2. 启动 DS：`WPG_ADMISSION_MODE=wildboat` + `DEDICATED_SERVER_CREDENTIAL`。
3. 客户端：Multiplayer → **Online (test)** → Login → mode=`wildboat (real Online)` → **Join Match**。
4. 第二客户端不同账号重复 → 同 match admitted + snapshot；UI 显示 `players 2/4`。
5. 自动化：`python3 tools/e2e/dedicated/run_wildboat_online.py`

**禁止**：把 `local_stub` 当作真实 Online 的静默降级。

## Export / Docker

```bash
./tools/server/export_dedicated.sh
docker build --platform linux/amd64 --target runtime-local -t wpg-dedicated-server:phase2b .
docker run --rm --platform linux/amd64 --name wpg-ds \
  -p 24567:24567/udp \
  -e WPG_GAME_PORT=24567 \
  -e WPG_MAX_PLAYERS=4 \
  -e WPG_ADMISSION_MODE=wildboat \
  -e WPG_WILDBOAT_BASE_URL=http://host.docker.internal:8080 \
  -e DEDICATED_SERVER_CREDENTIAL="$DEDICATED_SERVER_CREDENTIAL" \
  -e WPG_ADVERTISE_HOST=127.0.0.1 \
  wpg-dedicated-server:phase2b
```

Healthcheck：容器内 `/var/lib/wpg/ready`。只映射 UDP。凭证仅经环境变量注入。

## Tests

```bash
export GODOT_BIN=...
export DEDICATED_SERVER_CREDENTIAL=...

python3 tools/test/run_all.py architecture
python3 tools/test/run_unit.py

"$GODOT_BIN" --headless --path . --script res://tests/unit/ticket_admission_test.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/wildboat_auth_test.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/assignment_client_test.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/ds_admission_test.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/online_protocol_test.gd

python3 tools/e2e/dedicated/run.py
python3 tools/e2e/dedicated/run_stub_online.py
python3 tools/e2e/dedicated/run_wildboat_online.py
python3 tools/e2e/solo/run.py
```

相关文档：`docs/client-authentication.md`、`docs/online-protocol.md`、`docs/phase-2b-api-contract.md`。
