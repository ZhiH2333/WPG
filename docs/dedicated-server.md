# WPG Dedicated Server — Local Startup (Phase 2A)

Online Dedicated Server 是与 LAN / Host-Guest / WAN-P2P **并行**的路径。

| 路径 | ENet 所有者 | 座位 | 默认端口 | 权威方 |
|---|---|---|---|---|
| LAN / P2P（遗留） | `LobbyNet` | 5（`GameLaunch.NET_MAX_SEATS`） | 17777 UDP | 玩家 Host |
| Online Dedicated Server | `DsNet` + `OnlineChannel` | 4（`OnlineProtocol.MAX_PLAYERS`） | 24567 UDP | Headless Dedicated Server |

不要把 LAN room ticket 当作 Online game ticket。Phase 2A 只用开发身份（`WPG_DEV_TOKEN`）。

## Traffic boundary

- **ENet/UDP**：本进程只承载实时游戏流量（默认 `24567/udp`）。
- **HTTPS**：账号 / 房间 / 票证属于未来的 WildBoat；不要把 Cloudflare Worker 当成 UDP 代理。
- Docker 镜像只暴露游戏 UDP 端口，不暴露 HTTP。

## Prerequisites

- Godot **4.6.2**（设置 `GODOT_BIN`，或不在 PATH 时使用仓库本地编辑器落点）
- 可选：Docker（镜像构建与容器运行）

```bash
export GODOT_BIN="/absolute/path/to/Godot"
# 本仓库常见本地落点：
# export GODOT_BIN="$PWD/build/netlify-godot/wpg-godot/editor/Godot.app/Contents/MacOS/Godot"
```

## Start server from source (headless)

```bash
# 方式 A：经 boot_screen 切入（与导出物行为一致）
"$GODOT_BIN" --headless --path . -- --dedicated-server --port=24567 --max-players=4

# 方式 B：环境变量
WPG_DEDICATED_SERVER=1 WPG_GAME_PORT=24567 WPG_MAX_PLAYERS=4 WPG_DEV_TOKEN=dev \
  "$GODOT_BIN" --headless --path .

# 方式 C：直接进 server 场景
"$GODOT_BIN" --headless --path . res://server/main.tscn
```

成功时 stdout 会出现：

```text
WPG_DS_LISTEN port=24567 max_players=4 protocol=1
WPG_DS_READY
```

就绪文件默认：`user://wpg_ds_ready`（可用 `WPG_READY_FILE` / `--ready-file=` 覆盖）。

## Connect a development client

Phase 2A 没有正式 Online UI。用 E2E 客户端脚本或在代码里挂 `DedicatedClient`：

```gdscript
var client := DedicatedClient.create("alice", "dev")
add_child(client) ## 最终名必须是 OnlineChannel（固定 RPC 路径）
client.connect_to_server("127.0.0.1", 24567)
```

客户端发送输入意图；服务器仿真并广播权威快照。客户端之间不直连。

## Configuration

| Variable / CLI | Meaning | Default |
|---|---|---|
| `WPG_GAME_PORT` / `--port=` | ENet UDP listen port | `24567` |
| `WPG_MAX_PLAYERS` / `--max-players=` | Online cap (≤ 4) | `4` |
| `WPG_DEV_TOKEN` / `--dev-token=` | Dev admission secret (empty = open) | empty |
| `WPG_READY_FILE` / `--ready-file=` | Readiness marker path | `user://wpg_ds_ready` |
| `WPG_TICK_HZ` | Snapshot tick rate | `20` |
| `WPG_MATCH_ID` | Dev match id label | `dev_match` |
| `WPG_DEDICATED_SERVER=1` | Force dedicated boot | off |

## Export Linux headless binary

Preset name: **Linux Dedicated Server**（`dedicated_server=true`）。

```bash
chmod +x tools/server/export_dedicated.sh
./tools/server/export_dedicated.sh
# -> build/dedicated_server/wpg_server.x86_64
```

或：

```bash
"$GODOT_BIN" --headless --path . --export-release "Linux Dedicated Server" \
  build/dedicated_server/wpg_server.x86_64
```

## Docker

```bash
# A) 本地已导出二进制（较快，先跑 ./tools/server/export_dedicated.sh）
# 导出物是 linux/amd64；在 Apple Silicon 上务必指定平台。
docker build --platform linux/amd64 --target runtime-local -t wpg-dedicated-server:local .
docker run --rm --platform linux/amd64 --name wpg-ds \
  -p 24567:24567/udp \
  -e WPG_GAME_PORT=24567 \
  -e WPG_MAX_PLAYERS=4 \
  -e WPG_DEV_TOKEN=dev \
  wpg-dedicated-server:local

# B) 多阶段：镜像内用 Godot 重新导出（可复现，较慢）
docker build --platform linux/amd64 -t wpg-dedicated-server .
```

Healthcheck：容器内 `/var/lib/wpg/ready` 存在即 ready。优雅停止用 `docker stop`。只映射 UDP 游戏端口。

## Tests

```bash
export GODOT_BIN=...   # 若 Godot 不在 PATH

python3 tools/test/run_all.py architecture
python3 tools/test/run_unit.py
# 或只跑 Online 相关：
"$GODOT_BIN" --headless --path . --script res://tests/unit/online_protocol_test.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/ds_admission_test.gd
"$GODOT_BIN" --headless --path . --script res://tests/integration/dedicated_server_test.gd

python3 tools/test/run_e2e.py dedicated
python3 tools/test/run_e2e.py solo
# LAN / WAN-P2P 回归按环境支持情况运行
```

## Phase 2A non-goals

未实现：WPass、WildBoat Game Ticket、Friends/Party、房间码、Matchmaking、云存档、多实例编排。
