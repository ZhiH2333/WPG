# Client Authentication (WPass / WildBoat)

**状态：** Auth 客户端已实现并对接本机 WildBoat Phase 2 Identity。  
凭证持久化：**未**使用 OS 安全保险库（见下）。

## 已确认契约（对齐 WildBoat `docs/data-models-and-apis.md` Phase 2 notes）

| 项 | 值 |
|---|---|
| Base | `/v1` |
| Register | `POST /v1/auth/register`（不发会话；需邮箱验证） |
| Verify | `POST /v1/auth/email/verify` `{ "token" }` |
| Login | `POST /v1/auth/login` → `tokens` + `me` |
| Refresh | `POST /v1/auth/refresh` `{ "refresh_token" }`（旋转） |
| Logout | `POST /v1/auth/logout`（Bearer） |
| Profile | `GET /v1/me` |
| Access | HS256 JWT，`Authorization: Bearer …`，默认 15m |
| Refresh | 不透明串，仅哈希存库，旋转；复用超窗口吊销全家会话 |
| IDs | UUID 字符串（无 `acc_` / `plr_` 前缀） |
| 未验证登录 | `403 ACCOUNT_NOT_VERIFIED` |

## 客户端模块

| 文件 | 职责 |
|---|---|
| `online/http/wildboat_http_client.gd` | HTTPS JSON、超时、请求 ID、错误信封 |
| `online/http/wildboat_error.gd` | 稳定 `code` 解析 |
| `online/auth/auth_session.gd` | 注册/登录/刷新/登出/恢复；**单飞 refresh** |
| `online/auth/auth_credentials_store.gd` | `user://wpass_session.json` |
| `online/auth/player_identity.gd` | `/me` 快照 |
| `online/ui/online_panel.tscn` | Phase 2C Online 测试 UI（Login / Join Match / Leave） |
| `docs/phase-2c-player-online-test.md` | 面向小白的真实 Online 操作说明 |

## 安全与日志

- 不记录 password / access_token / refresh_token / game_ticket。
- 不向 Dedicated Server 发送 access/refresh token 或 password。
- Access token 仅内存；磁盘只存 refresh（见限制）。

## 凭证存储限制（未完成安全存储）

`AuthCredentialsStore.storage_is_secure() == false`。

当前实现写入 Godot `user://` 普通 JSON 文件，**不是** macOS Keychain / Android Keystore / Windows DPAPI。  
同用户可读该文件。文档与 UI 均标明 **NOT secure**。平台安全保险库接入前不得宣称“安全存储已完成”。

## 本地联调

1. 启动 WildBoat（`EMAIL_MODE=dev`）。
2. 客户端 Base URL：`http://127.0.0.1:8080`。
3. Register → 使用响应中的 `dev_verification_token` 调用 Verify → Login。
4. 自动化：`godot --headless --path . --script res://tests/unit/wildboat_auth_test.gd`  
   无后端时输出 `WILDBOAT_AUTH_SKIP`（exit 0）。
