# WPG CI/CD 新手手册

这份手册只描述当前仓库已经落地的流程。游戏版本只认 `project.godot` 里的 `application/config/version`。Git 只用 `main` 和临时分支 `dev/<name>`。

当前事实：

- 项目版本是 `1.0.0`
- 本机 Godot 是 `4.6.2`
- GitHub 仓库默认分支现在是长期分支 `dev`，不是 `main`
- 叫 `dev` 的这个分支**不会**触发 WPG CI。触发条件是 `dev/*`，例如 `dev/phase1-ui`

## 三个按钮，不要混

| 名字 | 做什么 | 什么时候跑 |
|---|---|---|
| WPG CI | 检查代码能不能过 | PR 到 main、push 到 main、push 到 `dev/<name>` |
| WPG Build | 打五个平台的测试包 | 你手动 Run，或者 main 上的 WPG CI 成功之后 |
| WPG Release | 按 tag 重新打包并发布到 GitHub Release | 只有 push `vX.Y.Z`，而且这个 tag 正好指向 `origin/main` 的最新提交 |

`dev/<name>` 的每一次 push 只跑 CI，不会自动打五个平台。

## 日常开发

1. 从 `main` 拉出临时分支，名字必须带斜杠，例如 `dev/phase1-ui`。
2. 这一轮的功能、修复、重构、UI、文档、CI、测试都放在这个分支上。不要再拆 `feature/*`。
3. `git push -u origin dev/phase1-ui`。
4. GitHub 自动跑 **WPG CI**。Run 名字类似 `WPG CI — dev/phase1-ui — <完整 sha>`。
5. CI 失败就停。不要构建，不要合并。
6. CI 通过后，如果要在自己电脑上打测试包：

```bash
python3 tools/build_tools.py
```

选 `7. Build All Platforms`。产物在 `build/` 和 `artifacts/`，不会进 Git。

7. 本地测试通过后，开 Pull Request：`dev/phase1-ui` → `main`。
8. PR 会再跑一次 **WPG CI**。Run 名字类似 `WPG CI — PR #42 — dev/phase1-ui`。
9. 必须看到 WPG CI 成功，并且有人 Review / Approve。
10. 合并到 `main`。
11. 合并产生一次 push `main`，再跑 **WPG CI**。
12. 只有这次 CI 成功，**WPG Build** 才会自动打五个平台。CI 失败时 Build 的 `decide` 会把 `should_build` 设为 false，五个构建 job 不运行。
13. 到 Actions 里下载 main 的测试包，自己再玩一次。

想在 `dev/<name>` 上提前看包：Actions → WPG Build → Run workflow，选这个分支。这是手动的，不是 push 自动触发。

## 本地菜单

```bash
python3 tools/build_tools.py
```

也可以不进菜单，直接跑某一项，例如 `python3 tools/build_tools.py 1`。

| 选项 | 做什么 |
|---|---|
| 1 Run CI Checks | 和 GitHub 同一套：Godot 导入与脚本 parse、Architecture Guard、主场景 Smoke、仓库里如果有 `tests/` 或 `*_test.gd` 就跑。失败返回非 0 |
| 2–6 | 只打一个平台，输出到 `build/<平台>/` 和 `artifacts/` |
| 7 Build All | 按 Windows、macOS、Linux、Android、Web 顺序打。任何一个不是 PASS，整体就是 FAIL |
| 8 Show Version | 打印 project.godot 版本、分支、短 commit。如果 HEAD 正好是 tag，会多一行 Tag |
| 9 Set Version | 只改 `project.godot` 的 `config/version`，改完再读一遍核对 |
| 10 Check Release Readiness | 发布前检查。会真的跑一遍 CI |
| 11 Create Release Tag | 只在 main、且等于 `origin/main`、工作区干净、版本合法时，询问后创建并 push `vX.Y.Z`。取消则什么都不做 |
| 12 Exit | 退出 |

状态只用这几种：`[PASS]` `[FAIL]` `[BLOCKED]` `[INFO]` `[WARN]`。`BLOCKED` 不是成功。

## 准备正式发布 v0.4.0

下面用 `0.4.0` 举例。现在仓库里的版本是 `1.0.0`，不要顺手改掉，除非你真的要发布。

1. 用菜单 `9. Set Version`，输入 `0.4.0`。工具只改 `project.godot`。
2. 把这个改动提交，并合并进 `main`。普通 push `main` **不会**创建 GitHub Release。
3. 确认自己就在 `main`，工作区干净，并且本地 `main` 已经 push 到 GitHub，和 `origin/main` 是同一个提交。
4. 运行 Build Tools，选 `10. Check Release Readiness`。
5. 每一行都是 `[PASS]` 才能继续。出现 `[FAIL]` 或 `[BLOCKED]` 就不要打 tag。
6. 选 `11. Create Release Tag`。工具问 `Create tag v0.4.0?`。
7. 输入 `y` 之后，它创建附注 tag 并 `git push origin v0.4.0`。
8. 输入别的内容，或者直接回车，等于取消，本地和远程都不会多出一个 tag。
9. tag push 之后，GitHub 自动跑 **WPG Release**。Run 名字是 `WPG Release — v0.4.0`。
10. Release 会自己重新编译这五个平台，不拿以前 dev/main 的旧包充数。
11. 五个都成功后，才会创建 GitHub Release，并附上：

```text
WPG-v0.4.0-windows.zip
WPG-v0.4.0-macos.zip
WPG-v0.4.0-linux.zip
WPG-v0.4.0-android.apk
WPG-v0.4.0-web.zip
SHA256SUMS.txt
```

任何一个平台失败，`publish` 不会跑，GitHub 上不会留下半个 Release。

tag 必须同时满足：

- 格式是 `vX.Y.Z`，例如 `v0.4.0`。`v0.4`、`v0.4.0-beta` 都会失败
- 这个提交正好是 `origin/main` 的最新提交
- `project.godot` 的版本是 `0.4.0`，和 tag 去掉 `v` 之后一致
- 同一套 CI 检查通过
- 五个平台重新构建都通过

## 五个平台现在怎么算

| 平台 | 测试包文件名 | 正式 Release 文件名 |
|---|---|---|
| Windows | `WPG-windows-<7位commit>.zip` | `WPG-vX.Y.Z-windows.zip` |
| macOS | `WPG-macos-<commit>.zip` | `WPG-vX.Y.Z-macos.zip` |
| Linux | `WPG-linux-<commit>.zip` | `WPG-vX.Y.Z-linux.zip` |
| Android | `WPG-android-<commit>.apk` | `WPG-vX.Y.Z-android.apk` |
| Web | `WPG-web-<commit>.zip` | `WPG-vX.Y.Z-web.zip` |

GitHub Actions 上的 artifact 名字另外规定：

- `dev/phase1-ui` 手动构建：`WPG-dev-phase1-ui-windows-<commit>` 这种
- `main` 自动构建：`WPG-main-windows-<commit>` 这种

macOS 第一版不做 Apple 签名，也不做公证。签不了就保持未签名包；环境根本导不出就记 `BLOCKED`，不能写成 PASS。

Android 第一版只要 APK。不做 Google Play、AAB 上架、Firebase、Play App Signing。

Android 需要这三样，而且都不要提交进 Git：

- Android SDK（本机如果装在 `~/Library/Android/sdk`，工具会自己找；CI 用 `android-actions/setup-android`）
- Java 17（本机有 Zulu 17，但没放进 PATH；工具会去 `/Library/Java/JavaVirtualMachines` 找）
- keystore。没有正式 keystore 时，导出的是 **debug 签名 APK**。正式签名可以以后用 GitHub Secret 提供 `WPG_ANDROID_KEYSTORE`，不要把 `.keystore` 或密码写进仓库

Web 打的是整个导出目录的 zip，不只是一个 HTML。包里至少要有 `index.html`，以及 wasm / js / pck 之一。

## 你要在 GitHub 网页上手工设置的东西

这些不能靠 workflow 文件自己打开。

1. **把默认分支改成 `main`。**  
   现在 `origin/HEAD` 指向 `dev`。`WPG Build` 用的 `workflow_run` 只读取**默认分支**上的 `build.yml`。在 Settings → General → Default branch，改成 `main`。改之前，先把这份 CI 文件合并进 `main`，否则默认分支上没有 workflow，自动 Build 不会挂上。

2. **保护 `main`。** Settings → Branches → Add branch ruleset（或经典 Branch protection rule），分支选 `main`：
   - 要求 Pull Request 才能合并
   - 要求至少 1 个 Review / Approve
   - 要求状态检查通过，必选这三个 job：`validate`、`architecture`、`smoke`  
     它们都属于 workflow **WPG CI**。GitHub 的 required check 列表里显示的是 job 名，不是 workflow 名
   - 要求分支在合并前是最新的
   - 不要勾选允许管理员绕过，除非你明确知道自己在干什么
   - 禁止 force push，禁止删除 `main`

3. **不要保护一个长期 `dev`。** 临时分支 `dev/<name>` 合并并确认不再需要后，可以删掉。

4. 第一次跑过 WPG CI 之后，required check 下拉框里才会出现 `validate` / `architecture` / `smoke`。如果列表是空的，先对 `main` 或一个指向 `main` 的 PR 跑通一次 CI，再回来勾选。

5. Release 使用仓库自带的 `GITHUB_TOKEN` 创建 Release。Settings → Actions → General 里，Workflow permissions 要允许 **Read and write permissions**，否则 `publish` 没法创建 Release。

## 本地和 GitHub 为什么是同一套规则

```text
python3 tools/build_tools.py
        │
        ├─ tools/ci/validate.py
        ├─ tools/ci/architecture.py
        ├─ tools/ci/smoke.py
        ├─ tools/build/export_platform.py
        └─ tools/release/guard.py 里也会再调用 tools/ci/run_ci.py

GitHub Actions 调用的是上面这些脚本，不另写一套检查。
```

构建产物目录 `build/`、`artifacts/`、`logs/`、`.tools/` 已写进 `.gitignore`。原来的 `/export/`、`/builds/` 规则还在，没有删。
