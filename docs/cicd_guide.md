# WPG CI/CD 新手手册

这份手册只描述当前仓库已经落地的流程。游戏版本只认 `project.godot` 里的 `application/config/version`。长期分支有两个：默认分支 `dev`（日常开发 + Netlify 生产分支）和 `main`（只进正式 Release），临时分支是 `dev/<name>`。

当前事实：

- 项目版本是 `1.0.0`
- 本机 Godot 是 `4.6.2`
- GitHub 仓库默认分支现在是长期分支 `dev`，不是 `main`
- `dev`、`dev/<name>`、`main` 的 push 都会触发 WPG CI
- **WPG CI 成功 + push 到 `dev` 或 `dev/<name>`，会自动触发 WPG Dev CD，打出六个平台的 Dev 包**
- `dev` 上每来一个 commit，**Netlify 自己**会构建 Web 并发布到 <https://bwpg.netlify.app>，不用 GitHub Actions

## 三个按钮 + Netlify，不要混

| 名字 | 做什么 | 什么时候跑 |
|---|---|---|
| WPG CI | 检查代码能不能过 | PR 到 main、push 到 main、push 到 `dev` 和 `dev/<name>` |
| WPG Dev CD | 打**六个平台**的 Dev 包，上传 GitHub artifact | WPG CI 成功，而且这次 CI 是 `dev` / `dev/<name>` 的 push；也可以手动 Run |
| WPG Release | 按 tag 重新打包并发布到 GitHub Release | 只有 push `vX.Y.Z`，而且这个 tag 正好指向 `origin/main` 的最新提交 |
| Netlify 构建 | 构建 Web 并发布到 <https://bwpg.netlify.app> | push 到 `dev`（生产分支），由 Netlify 的 Git 集成负责 |

WPG Dev CD **只上传 artifact**：不创建 Release、不打 tag、不 commit、不 push，也不碰 Netlify。

CI 失败、CI 被取消、事件不是 push（PR、`main`、schedule 之类）时，`prepare` 会静默把 `should_build` 设成 `false`，六个构建 job 和 `aggregate` 全部跳过——不构建、不上传，整个 run 仍然是绿的，不会因为"没构建"而报错。

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
12. `main` 上的 CI 只是门禁，**不会**自动打任何平台的包。WPG Dev CD 只认 `dev` 和 `dev/<name>` 的 push；`main` 上的 CI 成功，`prepare` 会静默设 `should_build=false`。
13. 想看最新代码的六个平台包，就去 Actions 里下 `dev` 那次 **WPG Dev CD** 的 artifact。

在 `dev` 或 `dev/<name>` 上 push 一个 commit，WPG CI 一通过 WPG Dev CD 就自动开打，不用手动点。想打一个不是"刚 push"的 commit：Actions → WPG Dev CD → Run workflow，`ref` 填分支 / tag / 完整 SHA，留空就是当前分支最新提交。

## 本地菜单

```bash
python3 tools/build_tools.py
```

也可以不进菜单，直接跑某一项，例如 `python3 tools/build_tools.py 1`。

| 选项 | 做什么 |
|---|---|
| 1 Run CI Checks | 和 GitHub 同一套：Godot 导入与脚本 parse、Architecture Guard、主场景 Smoke、Dev 包命名单元测试（`tools/test/test_dev_naming.py`）。失败返回非 0 |
| 2–6 | 只打一个平台，输出到 `build/<平台>/` 和 `artifacts/` |
| 7 Build All | 按 Windows、macOS、Linux、Android、Web 顺序打。任何一个不是 PASS，整体就是 FAIL |
| 8 Show Version | 打印 project.godot 版本、分支、短 commit。如果 HEAD 正好是 tag，会多一行 Tag |
| 9 Set Version | 只改 `project.godot` 的 `config/version`，改完再读一遍核对 |
| 10 Check Release Readiness | 发布前检查。会真的跑一遍 CI |
| 11 Create Release Tag | 只在 main、且等于 `origin/main`、工作区干净、版本合法时，询问后创建并 push `vX.Y.Z`。取消则什么都不做 |
| 12 Deploy Web to Netlify | 手动兜底：把已有的 `build/web/raw` 用 netlify CLI 发到 <https://bwpg.netlify.app>。不会自己重新导出，先跑 6。平时不走这里 |
| 13 Exit | 退出 |

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

## 六个平台现在怎么算

Dev 包（WPG Dev CD）和正式 Release 包（WPG Release）是两套命名，**不要混**：

| 平台 | Dev 包文件名 | 正式 Release 文件名 |
|---|---|---|
| Windows | `WPG_20261005_e34723f_windows.zip` | `WPG-vX.Y.Z-windows.zip` |
| macOS | `WPG_20261005_e34723f_macos.zip` | `WPG-vX.Y.Z-macos.zip` |
| Linux | `WPG_20261005_e34723f_linux.zip` | `WPG-vX.Y.Z-linux.zip` |
| Android | `WPG_20261005_e34723f_android.apk` | `WPG-vX.Y.Z-android.apk` |
| Web | `WPG_20261005_e34723f_web.zip` | `WPG-vX.Y.Z-web.zip` |
| iOS | `WPG_20261005_e34723f_ios.zip` | 正式 Release **不打** iOS |

Dev 包命名规则：

- `20261005` 是**那次 commit 的日期**（`git log -1 --format=%cs`，committer date），不是 workflow 跑的那天。
- `e34723f` 是触发 WPG CI 的那个 commit 的前 7 位，固定 7 位。
- 前缀 `WPG_20261005_e34723f` 由 WPG Dev CD 的 `prepare` job 算**一次**，通过 `WPG_DEV_BUILD_PREFIX` / `WPG_DEV_DATE` / `WPG_DEV_SHA` / `WPG_DEV_BRANCH` 下发给六个构建 job 和 `aggregate`。六个 job 不各自计算，所以不会出现两个平台名字对不上。
- 构建的必须是**触发 WPG CI 的那个 commit**（`github.event.workflow_run.head_sha`），`prepare` 会比对 `git rev-parse HEAD`，对不上直接 `[FAIL]`。绝不用 `github.sha`——那时 `dev` 可能已经有新提交了。
- 命名真源是 `tools/wpg_common.py` 的 `dev_build_prefix()` / `dev_package_basename()`。本地跑 `python3 tools/build/print_meta.py <平台>` 会打印同名的 `artifact_name` / `file_name`。

GitHub Actions 上的 artifact 名：

- **Dev**：文件名去掉扩展名，即 `WPG_20261005_e34723f_windows` 这种，六个平台各一个。另外还有一个 `WPG_20261005_e34723f_meta`，里面是六个包 + `WPG_20261005_e34723f_SHA256SUMS.txt` + `WPG_20261005_e34723f_manifest.json`
- **Release**：`release-windows`、`release-macos`、`release-linux`、`release-android`、`release-web`

`manifest.json` 记录 `project` / `branch` / `commit` / `short_commit` / `commit_date` / `godot` / `build_type`，以及六个平台各自的 `filename`、`sha256`、`size_bytes`。`SHA256SUMS.txt` 是 `哈希␣␣文件名` 两列，Linux 上 `sha256sum -c` 可以直接校验，macOS 上用 `shasum -a 256 -c`。

### WPG Dev CD 的 job 结构

```text
WPG CI 成功（push 到 dev / dev/*）
  └─ WPG Dev CD
       ├─ prepare      gate → 解析 ref → checkout 那个精确 commit → 算一次前缀
       ├─ build-windows   ┐
       ├─ build-macos     │
       ├─ build-linux     │ 六个并行，各自 checkout 同一个 SHA，
       ├─ build-android   │ 用 prepare 下发的前缀命名，
       ├─ build-web       │ 打包后先 verify_package.py 再上传
       └─ build-ios       ┘
       └─ aggregate      下载六个 artifact → SHA256SUMS.txt + manifest.json → 上传 <前缀>_meta
```

每个构建 job 在上传前都会先跑 `python tools/build/verify_package.py <平台>`：包不存在、是空的、zip 打不开、或者缺关键内容（Web 缺 `index.html` + wasm/js/pck，iOS 缺 `WPG.app/Info.plist` + `WPG.xcodeproj/project.pbxproj`），一律 `[FAIL]`，不上传半成品。

### iOS 是未签名的 CI 包

`build-ios` 跑 `tools/build/export_ios_ci.py`：不读 Team ID、不找 .p12 / .mobileprovision、不跑签名预检，`xcodebuild` 全程 `CODE_SIGNING_ALLOWED=NO`，产出的是 **`.zip`，里面是 `WPG.app` + `WPG.xcodeproj`**。

- 它**不是**可以装到手机上的 `.ipa`。真机安装继续走本地 Personal Team：`python3 tools/build/export_platform.py ios`。
- 导出期间 `export_presets.cfg` 里的 `application/export_project_only` 会被临时置 `true`，结束后按**原始字节**恢复并校验，所以本地 iOS 构建不受影响。
- 正式 Release（WPG Release）只有五个平台，没有 iOS，这条边界没有变。

macOS 第一版不做 Apple 签名，也不做公证。签不了就保持未签名包；环境根本导不出就记 `BLOCKED`，不能写成 PASS。

Android 第一版只要 APK。不做 Google Play、AAB 上架、Firebase、Play App Signing。

Android 需要这三样，而且都不要提交进 Git：

- Android SDK（本机如果装在 `~/Library/Android/sdk`，工具会自己找；CI 用 `android-actions/setup-android`）
- Java 17（本机有 Zulu 17，但没放进 PATH；工具会去 `/Library/Java/JavaVirtualMachines` 找）
- keystore。没有正式 keystore 时，导出的是 **debug 签名 APK**。正式签名可以以后用 GitHub Secret 提供 `WPG_ANDROID_KEYSTORE`，不要把 `.keystore` 或密码写进仓库

Web 打的是整个导出目录的 zip，不只是一个 HTML。包里至少要有 `index.html`，以及 wasm / js / pck 之一。

## dev 提交后自动部署 Web 到 Netlify

正式地址是 <https://bwpg.netlify.app>，内容是 `dev` 分支的最新 Web 构建。**这一段和 GitHub Actions 无关**，是 Netlify 自己的 Git 集成在干活：

```text
push dev
  └─ Netlify（生产分支 = dev）读取仓库根的 netlify.toml
       └─ command: python3 tools/deploy/netlify_build.py
            ├─ tools/ci/install_godot.py          下载 Godot 4.6.2 与导出模板
            ├─ tools/build/export_platform.py web 导出到 build/web/raw
            └─ 复检 build/web/raw
       └─ publish: build/web/raw  →  https://bwpg.netlify.app
```

- WPG CI 和部署是两条独立的路。CI 挂了 Netlify 照样会构建；它只看 Netlify 自己那次构建成不成功。
- WPG Dev CD 也和 Netlify 无关。它打出来的 Web 包只是一个 GitHub artifact，Netlify 既不读 `artifacts/`，也不读包名；`netlify.toml` 和 `tools/deploy/netlify_build.py` 在 Dev CD 落地过程中**一行没改**。Dev 包改名成 `WPG_20261005_e34723f_web.zip` 对 <https://bwpg.netlify.app> 没有任何影响。
- `dev/<name>`、`main`、PR 都不影响正式站，因为生产分支是 `dev`。
- Web 导出是 `variant/thread_support=false`，不需要 COOP/COEP 响应头，Netlify 静态托管直接能跑。
- 发布前会检查 `build/web/raw` 里有没有 `index.html` 和 wasm / js / pck；缺了就 `FAIL`，Netlify 不会发布坏包。
- 现在的包大约 74 MB、16 个文件，最大单文件 `index.pck` 约 37 MB。Netlify 官方对单个文件的**建议**值是 10 MB 以内，静态部署实际能过。
- Netlify 的静态资源默认 `max-age=0, must-revalidate`，而且每次原子部署会自动失效旧缓存，所以不用自己写 `_headers`。

### 仓库里负责这件事的三个文件

| 文件 | 作用 |
|---|---|
| `netlify.toml` | 告诉 Netlify 跑什么命令、发布哪个目录、哪些构建直接跳过。**文件里的设置优先级高于网页上的 Build settings** |
| `tools/deploy/netlify_build.py` | 构建入口。装 Godot → 导出 Web → 复检产物，三步任一失败就非 0 退出 |
| `tools/wpg_common.py` 的 `web_package_problem()` | 判断一个导出目录能不能发布。导出、Netlify 构建、手动发布共用它 |

`netlify_build.py` 存在的原因：`install_godot.py` 只会把 Godot 路径写进 GitHub Actions 的 `GITHUB_ENV` / `GITHUB_PATH`，Netlify 上没有这两个变量，所以要自己把它接进 `GODOT_BIN`。

### 你在 Netlify 上要确认的设置

站点已经连好 GitHub，只需要确认这几项（都在 Project configuration → Developer settings → Continuous deployment）：

1. **Build command / Publish directory 留空。** 仓库根的 `netlify.toml` 会覆盖它们；两边都填容易对不上。
2. **Production branch = `dev`。** 这样只有 `dev` 的 commit 进正式站。
3. **Branch deploys 保持 "Deploy only the production branch"**，除非你确实想给其它分支单独的预览地址。
4. **Deploy Previews 建议关掉。** PR 到 `dev` 也会触发一次完整构建（要现下 Godot 和导出模板，几分钟）。`netlify.toml` 里已经有一行 `ignore = '[ "$CONTEXT" = "deploy-preview" ]'` 让它直接跳过；如果你确实想要 PR 预览地址，删掉那一行。这一行是「只在 preview 时跳过」，`$CONTEXT` 取不到时只会多构建，不会漏掉 `dev` 的正式部署。

还有一个前提：`netlify.toml` 必须**在 `dev` 分支上**。Netlify 读的是「这次要部署的那个分支」里的配置文件，`dev` 上没有它就只会用网页上的 Build settings（现在是空的），构建会找不到 publish 目录。

第一次构建失败时看 Netlify 的 deploy log。日志里 `[FAIL]` 那一行会直接说缺什么；把那段发出来就能定位。

### 手动兜底

Netlify 的构建坏掉、或者你想把本机刚导出的那一版直接推上去时，可以用 CLI 覆盖发布：

```bash
python3 tools/build_tools.py
# 先 6. Build Web，再 12. Deploy Web to Netlify

# 或者不进菜单
python3 tools/build/export_platform.py web
NETLIFY_AUTH_TOKEN=xxx NETLIFY_SITE_ID=yyy python3 tools/deploy/deploy_netlify.py
```

- 这条手动路**不参与**平时的自动部署，只是兜底。
- token 从 Site configuration → General → Site information 拿 Site ID，头像 → User settings → Applications → Personal access tokens 拿 token。**不要提交进仓库。**
- 没配这两个环境变量时，第 12 项只会打一行 `BLOCKED` 就退出，不会上传。
- 部署完脚本会带 cache buster 请求一次线上地址核对，核对不通过只记 `WARN`。

## 你要在 GitHub 网页上手工设置的东西

这些不能靠 workflow 文件自己打开。

1. **默认分支必须是 `dev`，而且 `build.yml` 必须存在于 `dev` 上。**  
   `WPG Dev CD` 用 `workflow_run` 触发，GitHub 只会去**默认分支**上读这次 workflow 文件。现在 `origin/HEAD` 指向 `dev`，`build.yml` 也在 `dev` 上，所以 `dev` / `dev/<name>` 的 WPG CI 一成功就会挂上 Dev CD。  
   **不要把默认分支改成 `main`**——那样 `workflow_run` 会去 `main` 找 `build.yml`，`dev` 的自动构建会静默不触发（还不报错）。真要改，先把 `build.yml` 合并进 `main` 再改。Web 部署不经过 Actions，不受这条影响。  
   WPG Dev CD 只上传 artifact，声明了 `permissions: contents: read`，不需要改仓库的 Workflow permissions。

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

6. **只有手动兜底才需要的两个值。** 自动部署走 Netlify 的 Git 集成，不需要任何 GitHub Secret。只有你想用菜单 `12. Deploy Web to Netlify` 时，才要在本机 export `NETLIFY_AUTH_TOKEN` 和 `NETLIFY_SITE_ID`。

## 本地和 GitHub 为什么是同一套规则

```text
python3 tools/build_tools.py
        │
        ├─ tools/ci/validate.py
        ├─ tools/ci/architecture.py
        ├─ tools/ci/smoke.py
        ├─ tools/test/test_dev_naming.py     （Dev 包命名单元测试）
        ├─ tools/build/export_platform.py
        ├─ tools/build/export_ios_ci.py      （未签名 iOS CI 包，GitHub Actions 用）
        ├─ tools/build/print_meta.py         （算 Dev 前缀、artifact 名）
        ├─ tools/build/verify_package.py     （上传前复检产物）
        ├─ tools/build/dev_meta.py           （SHA256SUMS.txt + manifest.json）
        ├─ tools/deploy/netlify_build.py     （Netlify 用它构建 Web）
        ├─ tools/deploy/deploy_netlify.py    （手动兜底发布）
        └─ tools/release/guard.py 里也会再调用 tools/ci/run_ci.py

GitHub Actions 调用的是上面这些脚本，Netlify 调用的也是同一个 netlify_build.py，不另写一套。
```

构建产物目录 `build/`、`artifacts/`、`logs/`、`.tools/` 已写进 `.gitignore`。原来的 `/export/`、`/builds/` 规则还在，没有删。
