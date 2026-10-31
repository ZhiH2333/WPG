# Phase 2C — 玩家可操作的真实 Online 测试说明（小白版）

这份说明只教你**怎么点**。你不需要懂代码、终端、Docker 细节或服务器配置。

---

## 三种测试，请分清

| 类型 | 谁来做 | 说明 |
|---|---|---|
| **自动化测试** | 开发者 / 脚本 | 机器自动跑，不证明你亲手能玩 |
| **真实服务器联调** | 开发者 | 确认 WildBoat + Dedicated Server 契约 |
| **玩家实际操作测试** | **你（本页）** | 用游戏 UI 登录、进房、退出 |

本页只覆盖第三种。

---

## 开始前准备（只需一次）

1. 电脑已安装 **Docker Desktop**，并保持打开（图标不再转圈）。
2. 本仓库旁边有同级文件夹 `WildBoat`（路径类似：`…/WPG/wpg` 与 `…/WPG/WildBoat`）。
3. 能用 Godot 打开本项目（项目自带编辑器也可）。

---

## 第一步：一键启动测试环境

1. 用 Finder 打开文件夹：  
   `wpg/tools/online/`
2. **双击** `一键启动本地Online测试.command`
3. 若 macOS 提示「无法打开」，右键 → 打开 → 仍要打开。
4. 等到窗口出现「环境已准备好」再继续。  
   - 若提示 Docker 未运行：先打开 Docker Desktop，等它就绪，再双击一次。
5. **不要关闭** Dedicated Server（脚本已在后台跑）。测完再双击 `停止本地Online测试.command`。

这一步会启动：

- 真实 WildBoat（账号 / assign / 验票）
- 真实 Dedicated Server（UDP 游戏端口，默认 `24567`）

---

## 第二步：打开两个游戏窗口

1. 仍在 `wpg/tools/online/`
2. **双击** `打开两个游戏窗口.command`
3. 桌面上会出现两个 WPG 窗口（窗口 A / 窗口 B，会话互相隔离）

也可自己用 Godot 把项目运行两次；若两个窗口登成同一个号，在其中一个点 **Logout** 再登另一个账号。

---

## 第三步：在游戏里进入 Online

每个窗口都做一遍（**两个不同账号**）：

1. 等主菜单出现。
2. 点顶栏 **MULTIPLAYER**（或主页 **Multi**）。
3. 在多人页点最后一行：**Online (test)**  
   右侧说明：`Login → Join Match → Dedicated Server`
4. 弹出 **Online Test (Phase 2C)** 面板。

### 第一次用：注册账号

面板里默认地址是 `http://127.0.0.1:8080`（不要改，除非有人告诉你改）。

1. 填 **Email**、**Password**、**Display name**（两个窗口用不同邮箱）。
2. 点 **Register**。
3. 若出现验证码/token，会自动填进下面一栏 → 点 **Verify**。
4. 点 **Login**。
5. 上方应显示 `Player …`（已登录）。

### 进入同一场真实对局

1. 确认模式下拉框是：**wildboat (real Online)**  
   （不要选 `local_stub`，那不是真实 Online。）
2. 点 **Join Match**（推荐）。  
   它会：真实请求 `/v1/games/assign` → 用返回的 `game_ticket` 连接 Dedicated Server。
3. 状态文字变化预期：
   - `Requesting assignment…`
   - `Connecting to Dedicated Server…`
   - **`Connected — entering game world · seat …`**（随后进入战斗世界）
4. Phase 2D 起：Join 成功后会进入游戏世界，而不只停在面板。  
   双人同世界 / 互相看见移动 / Leave 清理的玩家步骤见：  
   **`docs/phase-2d-player-multiplayer-test.md`**
5. 第二个窗口用**另一个账号**同样 Join Match 后，两边都应进入同一场，世界里出现两个角色。

### 退出对局

1. 点 **Leave Match** → 应显示 `Left match — back in Online lobby`，并回到未连接状态。
2. 点 **Close** 关闭面板，回到 MULTIPLAYER 大厅（LAN 列表等仍在）。

---

## 你应该看到什么（验收对照）

| 步骤 | 成功长什么样 | 失败长什么样（不是成功） |
|---|---|---|
| 登录 | `Logged in` / 显示 Player 名 | `Failed: … — NOT matched` |
| Join Match | `Connected — seat …` | `Join failed: …` / `WildBoat unreachable…` / `Cannot reach Dedicated Server…` |
| 两人同房 | 两边 `players 2/4` | 只有一边 Connected，或两边 match id 不同且人数一直 1 |
| Leave | `Left match — back in Online lobby` | 卡住 Connecting、关不掉 |

**重要：** 状态里带 `NOT matched`、`Join failed`、`BACKEND`、`unreachable` 都表示**没有**进真实对局。不要把失败当成匹配成功。

---

## 常见问题

**Q：双击 .command 没反应 / 被拦截**  
右键 → 打开。或在「系统设置 → 隐私与安全性」里允许。

**Q：提示 Docker 未运行**  
打开 Docker Desktop，等鲸鱼图标安静后，再双击启动脚本。

**Q：提示找不到 WildBoat**  
确认 `WildBoat` 文件夹与 `wpg` 在同一层（都在 `WPG` 下）。

**Q：Connecting 一直转、最后 Cannot reach Dedicated Server**  
先再跑一次「一键启动」。若仍失败，把 `wpg/build/logs/online-test/dedicated_server.log` 发给开发者。

**Q：Failed / WildBoat unreachable — match NOT joined**  
后端不可用。脚本会 fail closed，**不会**假装匹配成功。检查 Docker / 再启动。

**Q：两个窗口登录成同一个号**  
在一个窗口点 Logout，换另一个邮箱登录。或用「打开两个游戏窗口.command」（会话已隔离）。

**Q：房间码 / 公开房间浏览器 / Quick Match Online**  
**本阶段未实现**，不要当成已支持。当前 Online 测试入口是 assign → Dedicated Server。

**Q：LAN 还能玩吗？**  
能。MULTIPLAYER 里原来的 Create room / LAN rooms / Invite 都还在；Online 是多出来的一行。

---

## 安全提醒（给你放心）

- 游戏客户端**不会**携带服务器 S2S 密码。
- 登录用的 Access / Refresh Token **不会**发给 Dedicated Server；进房只用短命 `game_ticket`。
- 本机会话文件标明 **NOT secure**（开发阶段），正式安全保险库以后再做。

---

## 测完怎么关

1. 两个游戏窗口：Leave Match → Close → 关掉窗口。
2. 双击 `停止本地Online测试.command`（停 Dedicated Server）。
3. Docker / WildBoat 可继续留着，下次测更快；要彻底关可在 Docker Desktop 里 Stop。

---

## 给开发者的对照（可跳过）

- UI 入口：`MainMenu` → MULTIPLAYER → `Online (test)` → `online/ui/online_panel.tscn`
- 一键脚本：`tools/online/start_local_online_test.sh`
- 自动化真实 Online：`python3 tools/e2e/dedicated/run_wildboat_online.py`
- 契约：`docs/phase-2b-api-contract.md`、`docs/dedicated-server.md`
