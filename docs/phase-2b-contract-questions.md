# Phase 2B — 契约状态（Agent B Integration）

WildBoat Agent A 已冻结契约：`docs/phase-2b-api-contract.md`（自 WildBoat 同步副本）。

## 已确认并已对接

| 项 | 决议 |
|---|---|
| Ticket 策略 | Option A：opaque + 在线 `POST /v1/server/tickets/validate` |
| Assignment | `POST /v1/games/assign`（**不是** `/v1/matchmaking/quick`） |
| Validate 请求 | `{ game_ticket, player_id, match_id, game_instance_id }` |
| Validate 错误 | `TICKET_INVALID` / `TICKET_EXPIRED` / `TICKET_REPLAYED` / `TICKET_REVOKED` |
| S2S 认证 | `Authorization: Bearer <DEDICATED_SERVER_CREDENTIAL>` |
| 重放 | validate 时原子 consume；重放 → `TICKET_REPLAYED` |
| DS 绑定 | 必须 `instances/register` + heartbeat；stale heartbeat 不可分配 |
| Settlement | `POST /v1/server/matches/{match_id}/settlement`；同 `settlement_id` → `already_processed: true` |

## 超时 / 半消费语义（契约安全处理）

若 DS 已发出 validate 请求但在收到响应前超时：

1. **fail closed**（拒绝入场，`BACKEND_UNAVAILABLE`）。
2. **不得自动重试同一 ticket**（票可能已在 WildBoat 侧消费；重试会得到 `TICKET_REPLAYED`）。
3. 玩家必须重新 `POST /v1/games/assign` 获取新票。

## WPG 模式边界

| 模式 | 用途 |
|---|---|
| Auth → 真实 WildBoat | 生产路径 |
| Assignment `wildboat` | 真实 `/v1/games/assign`；失败时**不**静默降级 stub |
| Assignment `local_stub` | 仅显式本地联调 |
| DS `admission_mode=wildboat` | S2S validate；不可达时 fail closed |
| DS `admission_mode=stub` / `dev` | 本地 / Phase 2A 兼容 |
