# Phase 2B — 待 Agent A（WildBoat）确认的契约问题

WPG 侧 **不会**另起一套生产 API。下列问题阻塞完整 Online E2E（真实 ticket）。

## 已确认（可联调）

- WPass Auth / Refresh / `/me`（WildBoat Phase 2 Identity 已落地）
- Assignment JSON **草案** shape（`match_id`, `game_instance_id`, `endpoint{host,port,transport}`, `game_ticket`, `ticket_expires_at`, …）
- Validate 请求草案：`{ ticket, game_instance_id, server_build }`
- Settlement 请求草案 + `Idempotency-Key` / `settlement_id` 幂等

## 未确认 / 未实现（阻塞）

1. **Ticket 策略**：opaque + 在线校验（Option A）还是签名自包含（Option B）？WPG 当前按 Option A 适配。
2. **最小 Assignment 端点**：无房间时是否先提供 `POST /v1/matchmaking/quick`，或临时 `POST /v1/matches/assign`？
3. **Validate 响应 JSON**：是否保证含 `player_id`, `match_id`, `game_instance_id`, `display_name`, `valid`？错误码是否含 `TICKET_EXPIRED` / `TICKET_REPLAYED`？
4. **S2S 认证**：`Authorization: Bearer <server_token>` 还是自定义头？环境变量名？轮换策略？
5. **重放策略**：validate 时 consume，还是 admit 成功后 consume？重连是否允许同票一次？
6. **DS 绑定**：`game_instance_id` 是否必须预先 `POST /v1/server/instances/register`？heartbeat 是否强制？
7. **Settlement**：失败重试返回体；重复 `settlement_id` 是 200 还是 `SETTLEMENT_ALREADY_PROCESSED`？

## WPG 当前适配层（非生产替代）

| 模式 | 用途 |
|---|---|
| Auth → 真实 WildBoat | 已测 |
| Assignment `local_stub` | 本地签发 `wpgstub1…` |
| DS `admission_mode=stub` | 验 stub + 防重放 |
| DS `admission_mode=wildboat` | 调用草案 validate URL；后端未实现时安全失败 |
| Settlement 本地 | 仅结构/日志，不宣称云端入账 |
