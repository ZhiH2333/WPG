# Phase 2D — 双人同世界移动同步（小白版）

这份说明只教你**怎么点、看什么**。你不需要懂代码、环境变量或 API。

本阶段目标：两个真实玩家**出现在同一个游戏世界**里，并且**能看见对方移动**。

---

## 和 Phase 2C 的差别

| Phase 2C | Phase 2D（本页） |
|---|---|
| 能进同一场 Dedicated Server | 同上 |
| Online 面板显示 `players 2/4` | 还会**进入游戏画面** |
| 不一定能看见对方角色 | **必须**在世界里看见对方并观察移动 |

若只看到面板人数、没有进游戏世界，**不算**本阶段成功。

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
3. 桌面出现两个 WPG 窗口（窗口 A / 窗口 B，登录互不影响）

---

## 第三步：两个账号分别登录

每个窗口都做一遍（**必须两个不同邮箱**）：

1. 主菜单 → 顶栏 **MULTIPLAYER**（或主页 **Multi**）
2. 点 **Online (test)**
3. 打开 **Online Test** 面板
4. 默认地址保持 `http://127.0.0.1:8080`
5. 填 Email / Password / Display name → **Register** → **Verify**（若有验证码会自动填）→ **Login**
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
4. 随后会加载**战斗沙盒游戏世界**（不是只停在 Online 面板）

第二个窗口同样 Join 后，两边都应在游戏世界里。

---

## 第五步：确认两个玩家都在世界里

成功时你应该看到：

1. 自己的角色（镜头跟着你）
2. **另一个角色**站在附近出生点（例如左右错开）
3. 暂停菜单 / HUD 仍可用

若只有自己一个人、怎么等也没有第二个角色：失败。可让两边 Leave 后重新 Join。

---

## 第六步：验证 A 移动时 B 能看见

1. 在**窗口 A** 用键盘/手柄移动你的角色（随便走远一点）
2. 看**窗口 B**：A 对应的那个远端角色应跟着移动
3. 两边的位置大致一致（允许一点点网络延迟，但方向/趋势要对）

---

## 第七步：反向验证 B 移动

1. 在**窗口 B** 移动
2. 看**窗口 A**：应看到 B 的角色移动

两边都能看见对方动，才算双向同步通过。

---

## 第八步：测试 Leave（离开）

1. 在窗口 A 打开暂停菜单 → 退出回主菜单（或等效离开）
2. 看窗口 B：A 的远端角色应**消失**（或提示有人离开）
3. 窗口 B 自己仍可留在世界里，或同样退出

**当前不支持“掉线重连后原样恢复”。** 断线后应安全清理；要再玩请重新 Join Match。

---

## 第九步：确认没有旧玩家残留

1. 两边都回到主菜单
2. 双击 `停止本地Online测试.command`，再重新 `一键启动…`
3. 再开两个窗口、换/用两个账号 Join
4. 世界里应只有**当前这场**的玩家，不应凭空多出上一场的幽灵角色

---

## 成功画面对照

| 步骤 | 成功 | 失败（不要当成成功） |
|---|---|---|
| 登录 | 显示 Player 名 | `Failed… NOT matched` |
| Join | 进入游戏世界 + seat | 一直 Connecting / Join failed / unreachable |
| 同房 | 世界里看到 2 个角色 | 只有面板 `players 2/4`、或世界里只有自己 |
| 移动 | 对方屏幕上你的角色在动 | 对方完全静止 / 传送乱跳且无法辨认 |
| Leave | 对方角色消失 | 幽灵残留、卡死 |

带 `NOT matched`、`Join failed`、`BACKEND`、`unreachable` 的都是**失败**。

---

## 常见问题（最简单处理）

**双击 .command 被拦截**  
右键 → 打开。

**Docker 未运行**  
先开 Docker Desktop，等图标安静，再一键启动。

**找不到 WildBoat**  
确认 `WildBoat` 与 `wpg` 在同一层文件夹。

**Connecting 很久 / 进不了世界**  
再跑一次一键启动；把 `wpg/build/logs/online-test/dedicated_server.log` 发给开发者。

**进了世界但看不见对方**  
确认两边 Join 的是同一时段、都显示 Connected；两边都 Leave 后重进。仍不行把两边座位号发给开发者。

**移动自己有延迟**  
正常：位置以服务器为准。本阶段不做预测/插值优化。

**房间码 / 好友 / 完整战斗**  
本阶段不做。只验证双人同世界 + 移动同步 + Leave 清理。

---

## 测完怎么关

1. 游戏内退出到主菜单 → 关掉两个窗口  
2. 双击 `停止本地Online测试.command`  
3. Docker 可先留着，下次更快

---

## 给开发者的对照（可跳过）

- 入场：`OnlinePanel.enter_world` → `MainMenu._enter_online` → `combat_sandbox`（`GameLaunch.NetRole.ONLINE`）
- 权威：`DsSession` 仿真 + `OnlineProtocol` snapshot v2（match_id / seat / pos / facing）
- 客户端复制：`OnlineReplica` + `CombatSandbox` Online 分支
- 自动化协议同步：`python3 tools/e2e/dedicated/run_world_sync.py`
- 自动化游戏世界实体：`python3 tools/e2e/dedicated/run_world_entities.py`
- **真实 InputMap→flush 移动**（Phase 2D.1）：`python3 tools/e2e/dedicated/run_world_input.py`；小白验收见 `docs/phase-2d1-player-movement-test.md`
- 真实 WildBoat：`python3 tools/e2e/dedicated/run_wildboat_online.py` + 本页手工世界验证
