# WebRTC 房间码原型

这是独立于 WPG 生产联机的最小原型。它不接入 `LobbyNet`，不修改 ENet/LAN，也不表示 WPG 已经支持公网房间码。

## 它证明什么

Host 向信令服务要一个 6 位房间码，Guest 用这个码加入。信令只交换 SDP 和 ICE，不转发游戏快照。双方建立 WebRTC DataChannel 后互发 ping/pong。

## 它还没有证明什么

- 没有两台处于不同网络的桌面设备跑通。本机回环和 Docker 都不能当成公网验收。
- TURN 只在同一台 Mac 上的两个 Linux 容器里证明过：直连被 iptables 丢掉之后，房间码数据才经 coturn 走通。这不是两台桌面设备，也不是公网。
- 官方 `webrtc-native` 1.2.2 不暴露 `iceTransportPolicy`。只配 TURN 服务器仍会收集 host candidate。中继是否被用上，要看直连失败后的对照，不能只看配置。

## 布局

| 路径 | 作用 |
|---|---|
| `signaling/server.py` | 可自托管的房间码信令，Python 标准库 |
| `turn/turnserver.conf.example` | coturn 配置样例 |
| `main.tscn` | 手工建房 / 加入 / 发数据 |
| `harness/accept.py` | 本机检查。跨网或 TURN 没做成时退出码是 2，不是通过 |
| `harness/turn_isolation.py` | Docker 可用时，用 iptables 掐掉直连后再走 TURN |

`addons/webrtc_native/lib/` 是官方 1.2.2 二进制，被 gitignore。缺失时运行：

```bash
python3 prototypes/webrtc_room/fetch_extension.py
```

## 本机检查

```bash
python3 prototypes/webrtc_room/signaling/test_server.py
python3 prototypes/webrtc_room/harness/accept.py
```

手工窗口：

```bash
python3 prototypes/webrtc_room/signaling/server.py --host 127.0.0.1 --port 8787
godot --path prototypes/webrtc_room
```

Headless 需要 `.godot/extension_list.cfg`。`fetch_extension.py` 和 `accept.py` 会写它。Godot 4.6 的游戏进程只加载这份清单，不会自己扫描扩展。

## 两台桌面设备

1. 在一台有公网地址的机器上跑信令：`python3 signaling/server.py --host 0.0.0.0 --port 8787`。
2. 按 `turn/turnserver.conf.example` 部署 coturn，放开 UDP/TCP 3478 和中继端口段。
3. 两台不在同一 NAT 后面的桌面各自打开原型。Host 创建房间，把短码告诉 Guest。
4. 直连模式只在双方能交换到可达 candidate 时成功。对称 NAT 需要 TURN 模式，并填 `turn:公网IP:3478`、用户名和口令。
5. 两边都能发出并收到数据通道消息，才算房间码数据面通过。TURN 是否真的被选中，要靠隔离测试或抓中继流量，不能只看配置里写了 TURN。
