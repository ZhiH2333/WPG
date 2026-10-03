# Rendezvous Service（Phase 9.2.1）

最小公网 **发现 / 交换服务**。纯 Python 标准库，**无第三方依赖**，**不依赖 Godot**。

## 它是什么

Host 与 Guest 各自向它 `REGISTER`，它记录双方**真实观测到的** UDP 端点，
然后在对端出现时把「对方候选 + 对方 observed endpoint」交换给双方。
拿到信息后，双方由各自客户端里的 `P2PConnection` 继续走 Direct 连接。

## 它绝对不是

- **不是 Relay**：不转发任何游戏数据包。
- 不承载 Combat / Lobby roster / Ready / seat 分配 / `Room.players` / `GameLaunch`。
- **不是最终游戏权威**：能否进 Lobby 仍由 Host 的 protocol 6 ticket handshake 决定。
  这里只做最基础的协议、形状与配对校验。

## 运行

```bash
# 默认 0.0.0.0:17779
python3 tools/p2p/rendezvous/server.py

# 指定端口 + 打开诊断日志（日志里绝不含完整 ticket）
python3 tools/p2p/rendezvous/server.py --port 17779 --verbose
```

## 协议（v2）

`protocol.py` 是 `lobby/rendezvous_contract.gd` 的**逐字节镜像**。
任何 wire 改动必须同时改这两处，并跑 `test_server.py` 与
`tests/rendezvous_contract_test.gd`。

```
u32 magic | u8 version | u8 type | u32 sid_len | session_id | <payload>
```

| 消息 | 方向 | 说明 |
|---|---|---|
| `REGISTER` | client → server | role / protocol / nonce / room_id / **ticket** / local candidates |
| `REGISTERED` | server → client | 自己的 `observed_address` / `observed_port` |
| `PEER_READY` | server → client | 对端已就绪（带对端 nonce / role / observed） |
| `CANDIDATES` | server → client | 对端候选 + 对端 observed endpoint |
| `ERROR` | server → client | 可诊断错误码 |
| `BYE` | client → server | 主动离场 |

错误码：`SESSION_NOT_FOUND` / `SESSION_FULL` / `BAD_PROTOCOL` / `BAD_TICKET` /
`BAD_ROLE` / `DUPLICATE_PEER` / `MALFORMED_PACKET` / `TIMEOUT` / `ROOM_MISMATCH`。

## observed endpoint 的唯一来源

```
observed_address, observed_port = addr[0], addr[1]
```

即 `recvfrom()` 交给我们的**内核源地址**。服务器看到什么就记什么。

严禁从 invite / 本地地址 / hostname / **客户端自报的 observed 字段** 伪造。
客户端在 `Candidate.observed_address` 里塞什么都一律无视 ——
`test_server.py::case_observed_endpoint_recorded` 专门断言这一点。

## Session 模型

| 字段 | 说明 |
|---|---|
| `session_id` | 服务端分配，16 hex |
| `room_id` / `ticket` | 房间身份与门票（ticket 只比对，**不进日志**） |
| `host` / `guest` | 各最多一个 `Peer` |
| `host_*` / `guest_*` candidates | 双方各自申报的候选 |
| `host_*` / `guest_*` observed | **服务端观测值** |
| `created_at` / `last_activity` | 驱动 `SESSION_IDLE_TIMEOUT_SEC = 30` 回收 |

配对规则：

- 一个 session **最多一个 Host + 一个 Guest**；
- **重复 Host 注册**：不覆盖旧 session，回 `DUPLICATE_PEER`（同一来源同 nonce 视为幂等刷新）；
- **重复 Guest 注册**：不创建第二个 Guest，回 `DUPLICATE_PEER`（同上幂等刷新语义）；
- Guest 必须携带与 session 一致的 ticket，否则 `BAD_TICKET`。

## 日志

只输出：`session_id` / `peer role` / nonce 短摘要（前 8 位）/ observed endpoint /
`message_type` / 错误码。

**绝不输出完整 ticket 或完整 nonce**。见 `safe_summary()` 与
`test_server.py::case_logs_hide_ticket`。

## 测试

```bash
python3 tools/p2p/rendezvous/test_server.py     # -> RENDEZVOUS_SERVER_OK
```

覆盖：Host/Guest 注册、配对、双方收到 candidates、observed 写入、
**客户端不能伪造 observed**、bad protocol / bad ticket / 重复 Host / 重复 Guest 被拒、
session 超时清理（且不影响其它 session）、malformed 包被拒、nonce 唯一非空、
日志不含明文 ticket、最小 STUN 解析、Python↔GDScript wire 一致性。

## STUN（`stun.py`）

最小 RFC 5389 Binding Request 客户端，只为拿到 NAT 映射后的 observed 端点。

只实现：Binding Request 构造、magic cookie 校验、12 字节 transaction id、
`XOR-MAPPED-ADDRESS`（回退 `MAPPED-ADDRESS`）解析。

**不实现**完整 STUN server / ICE / TURN / WebRTC / 任何第三方 NAT 库。
无应答时返回 `None` —— **绝不**用本地地址伪造 observed endpoint。

## 本阶段范围

已完成：**Rendezvous 注册 + 候选交换 + observed endpoint 获取**。

**未做**（属 Phase 9.2.2）：UDP simultaneous open、多端口快速探测、
hole punch retry storm、ICE、TURN、Relay、UPnP、Host migration、reconnect。
