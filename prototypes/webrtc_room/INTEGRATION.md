# 接入 LobbyNet 的最小方案

状态：**未实施**。容器里的 TURN 对照已经通过，但还没有两台不同网络的桌面设备用房间码对上。在那之前不改 `lobby/lobby_net.gd`，也不把 WebRTC 放进生产导出。

## 要守住的边界

- `LobbyNet` 仍是大厅里唯一会给 `SceneTree.multiplayer.multiplayer_peer` 赋值的对象。
- 同一时间只有一个 active peer。建 WebRTC 之前必须先 `close()` 掉现有的 ENet peer，反过来也一样。
- LAN 继续走现在的 `host_listen()` / `client_connect()`，不删。
- 数据通道一旦成为那个唯一 peer，后面的 protocol 6 ticket、Ready、换场交接、`NetSession` 和 snapshot v3 保持原样。
- 信令是 HTTP，不是第二个 peer，也不转发快照。角色和座位仍由 Host 的握手决定。
- 不改 Ability Framework，不改 Combat snapshot v3。

## 以后可以动的最小切口

1. 只在 `LobbyNet` 里新增一条房间码入口，例如 `host_room_code()` / `join_room_code()`。UI 仍然只叫 `LobbyManager`。
2. 传输实现放在 `LobbyNet` 拥有的对象里。Host 用 `WebRTCMultiplayerPeer.create_server()`（peer id 固定为 1），Guest 用 `create_client(id)`，并且只在 `WebRTCPeerConnection.STATE_NEW` 时 `add_peer()`。Godot 4.6 的这个类自己不生成 offer，SDP/ICE 仍由房间码信令交换。
3. `add_peer()` 成功并且通道打开之后，才把这一个 `WebRTCMultiplayerPeer` 赋给 `multiplayer.multiplayer_peer`。赋值点留在 `LobbyNet`，和现在的 ENet 赋值并列，不能同时成立。
4. 赋上去之后，现有的 `rpc_hello(protocol 6, ticket)`、Ready 和 `release_peer_for_handoff()` 继续用这一个 peer。战斗层不感知底下是 ENet 还是 WebRTC。
5. 扩展二进制进主工程会改变所有平台的导出。这一步等到两台不同网络的桌面设备跑通，并且有一次可复核的 TURN 中继测试之后再做。Android 只需要已经打开的 `INTERNET`，不要顺手改别的 preset。

## 还缺的证据

- 两台不在同一网络的桌面设备，用房间码完成双向数据。容器 TURN 对照不能代替这一条。
- 1.2.2 没有 `iceTransportPolicy`。接入时不能把「配置了 TURN」写成「流量走了 TURN」。中继要靠直连失败的对照，或者以后扩展把选中的 candidate pair 暴露出来。
