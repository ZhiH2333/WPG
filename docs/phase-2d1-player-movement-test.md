# Phase 2D.1 — 真实按键移动验收（小白版）

这份说明只教你**怎么点、按什么键、看什么**。你不需要懂代码或改任何文件。

本阶段目标：两个真实玩家进入同一场 Online 对局后，**用正常游戏移动键**控制角色，并且**对方屏幕上也能看见你在动**。

> 重要：自动化测试通过 ≠ 本页验收通过。必须以真实键盘操作为准。
>
> **Phase 2D.1 关键修复：** 点 Join Match 进入游戏世界时，旧逻辑会在销毁主菜单时**误关 Dedicated Server 连接**（服务器日志会出现 ADMIT 后立刻 LEAVE）。连接一断，按键怎么按都不会动。请**完全退出旧游戏窗口**，用当前代码重新一键启动后再测。

---

## 和 Phase 2D 的差别

| Phase 2D | Phase 2D.1（本页） |
|---|---|
| 双人进同一世界、能看见对方 | 同上 |
| 自动化可以「注入」移动指令 | **必须用 WASD / 方向键** |
| 可能只证明网络协议能动 | **必须证明真人操作能动** |

---

## 开始前准备（只需一次）

1. 电脑已安装 **Docker Desktop**，并保持打开。
2. 本仓库旁边有同级文件夹 `WildBoat`（例如 `…/WPG/wpg` 与 `…/WPG/WildBoat`）。
3. 能运行本项目的游戏窗口（一键脚本会帮你开）。

---

## 第一步：一键启动测试环境

1. 用 Finder 打开：`wpg/tools/online/`
2. **双击** `一键启动本地Online测试.command`
3. 若 macOS 拦截：右键 → 打开 → 仍要打开。
4. 等到窗口出现「环境已准备好」。
5. **不要关闭** Dedicated Server 窗口/后台。测完再双击 `停止本地Online测试.command`。

会启动：

- 真实 WildBoat（登录 / 分配对局 / 验票）
- 真实 Dedicated Server（游戏 UDP，默认 `24567`）

---

## 第二步：打开两个游戏窗口

1. 仍在 `wpg/tools/online/`
2. **双击** `打开两个游戏窗口.command`
3. 桌面出现两个 WPG 窗口（窗口 A / 窗口 B）

---

## 第三步：两个账号分别登录

每个窗口都做一遍（**必须两个不同邮箱**）：

1. 主菜单 → 顶栏 **MULTIPLAYER**（或主页 **Multi**）
2. 点 **Online (test)**
3. 打开 **Online Test** 面板
4. 默认地址保持 `http://127.0.0.1:8080`
5. 填 Email / Password / Display name → **Register** → **Verify** → **Login**
6. 上方应显示 `Player …`

若两个窗口登成同一个号：在其中一个点 **Logout**，换另一个邮箱。

---

## 第四步：加入同一场比赛并进入游戏世界

每个窗口：

1. 模式下拉框选：**wildboat (real Online)**（不要选 local_stub）
2. 点 **Join Match**
3. 状态变化预期：
   - `Requesting assignment…`
   - `Connecting to Dedicated Server…`
   - `Connected — entering game world · seat …`
4. 随后加载**战斗沙盒游戏世界**

第二个窗口同样 Join 后，两边都应在游戏世界里，并能看见两个角色。

---

## 第五步：移动键是什么

进世界后：

1. **先用鼠标点一下游戏窗口**（确保窗口有焦点；未聚焦的窗口收不到键盘）。
2. 使用这些键移动：
   - **W / A / S / D**
   - 或 **方向键 ↑ ← ↓ →**
3. **不要**在暂停菜单打开时测移动（Esc 会打开暂停；再按 Continue 回到游戏）。
4. 不要把键盘打进登录框：进世界后若还能看到 Online 面板文字输入框，先点一下游戏画面中央。

---

## 第六步：验收 A 移动（自己 + 对方）

1. 点中 **窗口 A**，按住 **D**（或 →）走几秒。
2. **窗口 A**：你自己的角色应明显向右移动（镜头大致跟着走）。
3. **窗口 B**：对应 A 的那个角色也应向右移动（允许一点点延迟）。

两边都看到 A 在动，才算 A 侧通过。

---

## 第七步：验收 B 移动（反向）

1. 点中 **窗口 B**，按住 **A**（或 ←）走几秒。
2. **窗口 B**：自己的角色应向左移动。
3. **窗口 A**：应看到 B 的角色向左移动。

---

## 第八步：停止输入

1. 松开所有移动键。
2. 角色应很快停下（不再持续滑行离开）。
3. 若松开后仍一直飘走：失败，把现象告诉开发者。

---

## 第九步：Leave 后远端消失

1. 在窗口 A 打开暂停菜单 → 退出回主菜单。
2. 看窗口 B：A 的远端角色应**消失**。
3. 窗口 B 可继续留在世界或同样退出。

---

## 成功 / 失败对照

| 步骤 | 成功 | 失败（不要当成成功） |
|---|---|---|
| 登录 | 显示 Player 名 | `Failed… NOT matched` |
| Join | 进入游戏世界 + 看到 2 个角色 | 一直 Connecting / 只有面板人数 |
| 自己移动 | 按住 WASD 后自己角色移动 | 完全不动 / 只有动画抖一下 |
| 对方看见 | 另一窗口里你的角色也在动 | 对方完全静止 |
| 停止 | 松键后停下 | 松键后继续狂奔 |
| Leave | 对方角色消失 | 幽灵残留 |

---

## 遇到问题怎么反馈（不用改代码）

请提供：

1. **截图**：窗口 A、窗口 B 各一张（能看出角色位置）。
2. 日志文件：`wpg/build/logs/online-test/dedicated_server.log`
3. 你按的是哪些键、哪个窗口有焦点。
4. （可选，给开发者）用诊断开关启动客户端后的终端输出里带 `WPG_ONLINE_INPUT_DIAG` 的行。

开发者诊断环境变量（普通玩家可忽略）：

```bash
export WPG_ONLINE_INPUT_DIAG=1
```

然后再开游戏窗口。日志会显示输入是否读到、是否发出、服务器是否收到。**不会**把密码或 ticket 打到屏幕上。

---

## 测完怎么关

1. 游戏内退出到主菜单 → 关掉两个窗口  
2. 双击 `停止本地Online测试.command`  
3. Docker 可先留着，下次更快

---

## 给开发者的对照（可跳过）

- **根因（2D.1）：** `MainMenu` 换场释放 `LobbyNet.close()` 会清空 `SceneTree.multiplayer_peer`；Online 进房前必须 `LobbyManager.handoff_online_peer()`（与 LAN `_handoff_peer_to_battle` 同合同）。症状：`dedicated_server.log` 里 `ADMIT` 后立刻 `LEAVE`。
- 真实路径：`PlayerInput` → `CombatSandbox._flush_online_input` → `OnlineChannel.send_input` → DS `apply_input` → snapshot v2 → `OnlineReplica` / `apply_net_pose`
- InputMap + LobbyNet 换场回归：`python3 tools/e2e/dedicated/run_world_input.py`
- Peer handoff 单元：`godot --headless --path . --script res://tests/unit/lobby_peer_handoff_test.gd`
- 实体同步：`python3 tools/e2e/dedicated/run_world_entities.py`
- 协议同步：`python3 tools/e2e/dedicated/run_world_sync.py`
