# Online Protocol (Client ↔ Dedicated Server)

**Transport:** ENet/UDP（默认 `24567`）。与 LAN `17777` / LobbyNet 隔离。  
**Protocol version:** `OnlineProtocol.PROTOCOL_VERSION = 1`  
**座位：** Online 最多 4；peer `1` = DS 进程，不是人类 Host。  
**契约：** `docs/phase-2b-api-contract.md`

## 消息

| 方向 | RPC | 说明 |
|---|---|---|
| C→S | `rpc_hello(protocol, display_name, game_ticket, claimed_player_id, claimed_match_id)` | 可靠；ticket 短命 scoped；claimed_* 仅绑定 validate |
| S→C | `rpc_welcome(seat, match_id, protocol)` | 准入成功 |
| S→C | `rpc_reject(reason)` | 见 `RejectReason` |
| C→S | `rpc_input(mx, my)` | 不可靠；意图 |
| S→C | `rpc_snapshot(bytes)` | 不可靠；权威状态 |
| S→C | `rpc_peer_left(seat)` | 可靠 |

客户端之间不直连。客户端不提交权威伤害/得分/结算。  
客户端不向 DS 发送 Access Token / Refresh Token。

## RejectReason

| 值 | 名 | 含义 |
|---|---|---|
| 0 | NONE | — |
| 1 | BAD_PROTOCOL | 协议不匹配 |
| 2 | BAD_TOKEN | ticket/dev token 无效 |
| 3 | FULL | Online 满员（≥4） |
| 4 | DUPLICATE | 同 peer / 同 player 重复 |
| 5 | MALFORMED | 畸形 |
| 6 | TICKET_EXPIRED | 票过期 |
| 7 | TICKET_REPLAYED | 重放 |
| 8 | TICKET_MISMATCH | match/instance 不符 / revoked |
| 9 | BACKEND_UNAVAILABLE | WildBoat 校验不可达（fail closed） |

## Admission 模式（DS）

| `WPG_ADMISSION_MODE` | 行为 |
|---|---|
| `dev`（默认） | Phase 2A：`WPG_DEV_TOKEN`；空 = 开放。**非生产身份** |
| `stub` | 本地 stub ticket（`wpgstub1…`）；测试/联调 |
| `wildboat` | 注册/心跳 + `POST /v1/server/tickets/validate`；不可达 fail closed |

身份以校验结果中的 `player_id` 为准，不信任客户端自报账号。

Validate 超时：单次请求 ≤3s，**不重试**（半消费风险）。玩家需重新 Assignment。

## Assignment（HTTPS）

客户端经 WildBoat 取得 `MatchAssignment`（扁平 host/port/ticket）。  
生产：`POST /v1/games/assign` + Player Access JWT。  
本地显式：`AssignmentClient.mode=local_stub`（**不得**在 wildboat 失败时静默切换）。

## Settlement（HTTPS S2S）

DS 生成 UUID `settlement_id`，调用  
`POST /v1/server/matches/{match_id}/settlement`（`DEDICATED_SERVER_CREDENTIAL`）。  
重试保持同一 `settlement_id`；`already_processed: true` 视为幂等成功。  
网络成功 ≠ 结算成功（需 body.`ok`）。  
`stub`/`dev` 下仅本地记录，**不伪装云端成功**。客户端不提交权威结算。
