# Online Protocol (Client ↔ Dedicated Server)

**Transport:** ENet/UDP（默认 `24567`）。与 LAN `17777` / LobbyNet 隔离。  
**Protocol version:** `OnlineProtocol.PROTOCOL_VERSION = 1`  
**座位：** Online 最多 4；peer `1` = DS 进程，不是人类 Host。

## 消息

| 方向 | RPC | 说明 |
|---|---|---|
| C→S | `rpc_hello(protocol, display_name, game_ticket)` | 可靠；ticket 短命 scoped |
| S→C | `rpc_welcome(seat, match_id, protocol)` | 准入成功 |
| S→C | `rpc_reject(reason)` | 见 `RejectReason` |
| C→S | `rpc_input(mx, my)` | 不可靠；意图 |
| S→C | `rpc_snapshot(bytes)` | 不可靠；权威状态 |
| S→C | `rpc_peer_left(seat)` | 可靠 |

客户端之间不直连。客户端不提交权威伤害/得分/结算。

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
| 8 | TICKET_MISMATCH | match/instance 不符 |
| 9 | BACKEND_UNAVAILABLE | WildBoat 校验不可达 |

## Admission 模式（DS）

| `WPG_ADMISSION_MODE` | 行为 |
|---|---|
| `dev`（默认） | Phase 2A：`WPG_DEV_TOKEN`；空 = 开放。**非生产身份** |
| `stub` | 本地 stub ticket（`wpgstub1…`）；测试/联调 |
| `wildboat` | `POST /v1/server/tickets/validate`（**Agent A 尚未实现**） |

身份以校验结果中的 `player_id` 为准，不信任客户端自报账号。

## Assignment（HTTPS）

客户端经 WildBoat 取得 `MatchAssignment`（host/port/ticket）。  
生产路径草案：`POST /v1/matchmaking/quick`（**未实现**）。  
本地：`AssignmentClient.mode=local_stub` 签发 stub ticket，配合 DS `admission_mode=stub`。

## Settlement（HTTPS S2S）

DS 生成 `SettlementPayload`（含唯一 `settlement_id`），调用  
`POST /v1/server/matches/{match_id}/settlement`（**未实现**）。  
`stub`/`dev` 下仅本地记录，**不伪装云端成功**。客户端不提交权威结算。

## 待 Agent A 确认

见 `docs/phase-2b-contract-questions.md`。
