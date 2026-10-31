# WPG Dedicated Server — Local Startup (Phase 2B)

Online Dedicated Server 是与 LAN / Host-Guest / WAN-P2P **并行**的路径。

| 路径 | ENet 所有者 | 座位 | 默认端口 | 权威方 |
|---|---|---|---|---|
| LAN / P2P（遗留） | `LobbyNet` | 5（`GameLaunch.NET_MAX_SEATS`） | 17777 UDP | 玩家 Host |
| Online Dedicated Server | `DsNet` + `OnlineChannel` | 4（`OnlineProtocol.MAX_PLAYERS`） | 24567 UDP | Headless Dedicated Server |

不要把 LAN room ticket 当作 Online game ticket。  
**生产身份** = WildBoat `game_ticket`；`WPG_DEV_TOKEN` 仅 `admission_mode=dev`。

## 实现状态（务必区分）

| 能力 | 状态 |
|---|---|
| DS listen / 权威快照 / 4 人上限 | **已实现** + 自动化 E2E |
| WPass Auth 客户端 | **已实现** + 对本机 WildBoat 自动化测 |
| Assignment 客户端（契约 DTO） | **已实现**；WildBoat MM **未实现** → 用 `local_stub` |
| Ticket Admission（stub/dev） | **已实现** + 单元测试 |
| Ticket Admission（WildBoat validate） | **适配层已写**；后端端点 **未实现** → E2E **BLOCKED** |
| Settlement S2S | **最小结构 + 本地记录**；云端提交 **BLOCKED** |
| 双客户端真实 Online（WPass+真实 ticket） | **BLOCKED**（等 Agent A） |
| 双客户端 stub Online | **可测**（见下方联调） |
| Solo / LAN 回归 | 须跑现有 e2e（见 Tests） |

## Traffic boundary

- **ENet/UDP**：实时游戏（默认 `24567/udp`）。
- **HTTPS**：WPass / Assignment / ticket validate / settlement → WildBoat。
- Cloudflare Worker **不是** UDP 代理。
- Docker 镜像只暴露游戏 UDP 端口。

## Prerequisites

- Godot **4.6.2**（`GODOT_BIN`）
- 可选：Docker；本机 WildBoat（Auth / 未来 ticket）

```bash
export GODOT_BIN="/absolute/path/to/Godot"
# 常见本地落点：
# export GODOT_BIN="$PWD/build/netlify-godot/wpg-godot/editor/Godot.app/Contents/MacOS/Godot"
```

## Start server (headless)

```bash
# Dev admission（Phase 2A 兼容）
WPG_ADMISSION_MODE=dev WPG_DEV_TOKEN=dev WPG_GAME_PORT=24567 WPG_MAX_PLAYERS=4 \
  "$GODOT_BIN" --headless --path . -- --dedicated-server

# Stub ticket admission（本地 Online 联调）
WPG_ADMISSION_MODE=stub WPG_MATCH_ID=dev_match WPG_GAME_INSTANCE_ID=dev_instance \
  WPG_GAME_PORT=24567 \
  "$GODOT_BIN" --headless --path . -- --dedicated-server

# WildBoat online validate（后端未就绪时会拒票 BACKEND_UNAVAILABLE）
WPG_ADMISSION_MODE=wildboat \
  WPG_WILDBOAT_BASE_URL=http://127.0.0.1:8080 \
  WPG_WILDBOAT_SERVER_TOKEN="<server-secret>" \
  WPG_MATCH_ID=... WPG_GAME_INSTANCE_ID=... \
  "$GODOT_BIN" --headless --path . -- --dedicated-server
```

成功 stdout：

```text
WPG_DS_LISTEN port=24567 max_players=4 protocol=1 admission=1
WPG_DS_READY
```

## Configuration

| Variable / CLI | Meaning | Default |
|---|---|---|
| `WPG_GAME_PORT` / `--port=` | ENet UDP | `24567` |
| `WPG_MAX_PLAYERS` / `--max-players=` | Online cap ≤4 | `4` |
| `WPG_ADMISSION_MODE` / `--admission-mode=` | `dev` \| `stub` \| `wildboat` | `dev` |
| `WPG_DEV_TOKEN` / `--dev-token=` | Dev shared secret | empty=open |
| `WPG_MATCH_ID` | Expected match id | `dev_match` |
| `WPG_GAME_INSTANCE_ID` | Expected instance id | `dev_instance` |
| `WPG_WILDBOAT_BASE_URL` | S2S / validate base | `http://127.0.0.1:8080` |
| `WPG_WILDBOAT_SERVER_TOKEN` | S2S credential（勿提交） | empty |
| `WPG_SERVER_BUILD` | Validate payload build | `wpg-server-dev` |
| `WPG_READY_FILE` / `--ready-file=` | Readiness marker | `user://wpg_ds_ready` |
| `WPG_TICK_HZ` | Snapshot Hz | `20` |
| `WPG_DEDICATED_SERVER=1` | Force dedicated boot | off |

## 本地 Online 联调（Auth + stub ticket + DS）

1. 启动 WildBoat（Auth）。
2. 启动 DS：`WPG_ADMISSION_MODE=stub`。
3. 客户端：Multiplayer → **Online (beta)**，或脚本：
   - Login（真实 WPass）
   - Assignment mode = `local_stub`
   - Connect DS
4. 第二客户端重复（不同账号）→ 两人均 admitted + 收到 snapshot。
5. 无 ticket / 过期 stub / 第 5 人 → 对应 reject。

**真实 WildBoat ticket E2E：未验证（后端未提供 validate/assignment）。**

## Export / Docker

```bash
./tools/server/export_dedicated.sh
docker build --platform linux/amd64 --target runtime-local -t wpg-dedicated-server:local .
docker run --rm --platform linux/amd64 --name wpg-ds \
  -p 24567:24567/udp \
  -e WPG_GAME_PORT=24567 \
  -e WPG_MAX_PLAYERS=4 \
  -e WPG_ADMISSION_MODE=dev \
  -e WPG_DEV_TOKEN=dev \
  wpg-dedicated-server:local
```

Healthcheck：容器内 `/var/lib/wpg/ready`。只映射 UDP。

## Tests

```bash
export GODOT_BIN=...

python3 tools/test/run_all.py architecture
python3 tools/test/run_unit.py

"$GODOT_BIN" --headless --path . --script res://tests/unit/ticket_admission_test.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/wildboat_auth_test.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/assignment_client_test.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/ds_admission_test.gd

python3 tools/test/run_e2e.py dedicated
python3 tools/test/run_e2e.py solo
```

相关文档：`docs/client-authentication.md`、`docs/online-protocol.md`、`docs/phase-2b-contract-questions.md`。
