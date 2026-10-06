# 本地 iOS 构建（Personal Team / Development）

只讲**本地 development 构建**：导出 Xcode project → xcodebuild 签出 `WPG.app` → 打出
development `WPG.ipa`，装到自己设备上测。

**不是** App Store、不是 TestFlight、不是 Ad Hoc / Enterprise 分发。免费 Apple Account
（Personal Team）本来也做不了这些。

---

## Prerequisites

| 项 | 要求 |
| --- | --- |
| 系统 | macOS（iOS 导出只在 macOS 上跑） |
| Xcode | 完整 Xcode，`xcode-select` 必须指向 `Xcode.app`，不是 Command Line Tools |
| Godot | **4.6.2**（与仓库一致，版本不符工具直接失败） |
| Export Templates | Godot 4.6.2 的 `ios.zip` |
| Apple Account | 免费账号即可，不需要付费 Developer Program |
| 签名 | Xcode 里登录了拥有目标 Team 的 Apple ID，Automatic Signing 可用 |

检查环境（不导出）：

```bash
python3 tools/build/export_platform.py ios --check
```

全部通过时输出 10+ 行 `[PASS]`；任何一项不行都给 `[FAIL] IOS_EXPORT_BLOCKED: ...`
或 `[FAIL] IOS_SIGNING_BLOCKED: ...`，退出码非 0。它**不会**在缺条件时假装成功。

---

## Xcode 登录 Apple Account / Personal Team

1. 打开 Xcode → `Settings… → Accounts`
2. 用拥有目标 Team 的 Apple ID 登录
3. 左侧选中账号，右侧能看到 **Team** 与其 **Team ID**（10 位大写字母数字）
   - 免费账号显示为 `xxx (Personal Team)`
4. `Manage Certificates… → + → Apple Development` 确认本机有开发证书

`xcodebuild` 的 Automatic Signing 完全依赖这一步。**仓库里不会、也绝不允许存放**
Apple ID、密码、App Store Connect API Key、`.p12`、`.mobileprovision`、`.secret`。
本机登录状态由 Xcode 自己管理，代码只知道 Team ID。

---

## Team ID

Team ID 只有一个来源：`export_presets.cfg` 的 iOS preset。

```ini
[preset.5.options]
application/app_store_team_id="L6266LV3YM"
```

- 这是 **Team ID**，不是 Apple ID，也不是账号邮箱。
- 工具从 preset 读它，不再在别处复制一份，避免两边不一致。
- Xcode 工程里对应 `DEVELOPMENT_TEAM = L6266LV3YM`、`CODE_SIGN_STYLE = Automatic`，
  导出后工具用 `xcodebuild -showBuildSettings` 反查这三项是否真的写进工程。

换 Team ID：只改 `export_presets.cfg` 这一行，然后重跑 `--check`。

---

## Bundle Identifier

同样只有 `export_presets.cfg` 一个来源，并且**三个平台必须一致**：

| 平台 | 键 |
| --- | --- |
| iOS | `application/bundle_identifier` |
| macOS | `application/bundle_identifier` |
| Android | `package/unique_name` |

当前值：`com.zhih.wpg2`

工具会校验：

- 只允许 `A-Z a-z 0-9 . -`，至少两级 reverse-DNS
- **占位值直接失败**：出现 `example` / `placeholder` / `yourcompany` / `changeme`
  之类会报 `IOS_EXPORT_BLOCKED: invalid/example bundle identifier`，不会蒙混通过

不要在脚本里临时改 bundle id；它必须每次构建都一样。

---

## 命令

```bash
# 1) 环境检查（doctor）
python3 tools/build/export_platform.py ios --check

# 2) 只生成 Xcode project（不编译、不签名，可在没有签名环境时验证导出链路）
python3 tools/build/export_platform.py ios --project-only

# 3) 完整本地 development 构建：project → .app → .ipa
python3 tools/build/export_platform.py ios

# 4) 等价写法
python3 tools/build/export_platform.py --platform ios
python3 tools/build/export_platform.py ios --configuration development   # 默认
python3 tools/build/export_platform.py --platform ios --configuration debug

# 5) 单独构建 iOS（build_all 默认仍然只跑五个正式平台）
python3 tools/build/build_all.py --platform ios
```

也可以进菜单：`python3 tools/build_tools.py` → `13. Build iOS` / `14. iOS Doctor`。

**不支持**的写法（会明确失败，不是静默改行为）：

```bash
python3 tools/build/export_platform.py ios --release            # 拒绝 distribution 命名
python3 tools/build/export_platform.py ios --configuration release   # 拒绝 App Store 路径
```

---

## 构建流程（5 个阶段）

```
阶段 1  Godot export        godot --headless --export-debug iOS → WPG.xcodeproj
阶段 2  Xcode configure     xcodebuild -showBuildSettings 校验
                            DEVELOPMENT_TEAM / CODE_SIGN_STYLE=Automatic / BUNDLE ID
阶段 3  xcodebuild archive  -sdk iphoneos -destination generic/platform=iOS
                            -allowProvisioningUpdates → WPG.xcarchive
阶段 4  .app 校验           从 xcarchive 取出 Products/Applications/WPG.app
阶段 5  development IPA     xcodebuild -exportArchive (method=development)
                            失败时退回「把已签名的 .app 打成 Payload/ zip」并明确标注
```

关于 `application/export_project_only`：

- preset 正式值保持 **`false`**（Godot 编辑器里仍可整包导出）
- 命令行构建期间工具临时把它置为 `true`，让 Godot **只生成 Xcode project**，
  编译/签名交给 xcodebuild —— 这样阶段边界清楚，失败能定位到具体一步
- 结束后按原始字节写回并校验；`git diff export_presets.cfg` 不会因此变化

---

## 产物目录

```
build/ios/development/
├── project/                  # WPG.xcodeproj + 工程源码（Godot 导出目标）
├── archive/WPG.xcarchive     # xcodebuild 归档
├── app/WPG-ios-development.app
├── ipa/WPG-ios-development.ipa
├── exportOptions-development.plist
build/logs/
├── export-ios.log
├── xcodebuild-ios-showsettings.log
├── xcodebuild-ios-archive.log
└── xcodebuild-ios-export-ipa.log
artifacts/
└── WPG-ios-development-<shortsha>.ipa
```

全部在 `build/` 与 `artifacts/` 下（`.gitignore` 已排除），不会写进源码目录。

打开工程看签名：

```bash
open build/ios/development/project/WPG.xcodeproj
# Signing & Capabilities → Automatically manage signing ✓ → Team = 你的 Personal Team
```

---

## 产物校验（不是 `test -f`）

`.app`：

- 目录存在、`Info.plist` 可解析
- `CFBundleIdentifier` 与 preset Bundle ID 完全一致
- 主可执行文件存在且是 **ARM64**
- `codesign --verify --deep --strict --verbose=2`（不适用时降级并打印真实错误）
- `codesign -d` 的 `TeamIdentifier` 与 preset Team ID 一致
- `embedded.mobileprovision` 存在则解码检查 Team 与过期时间

`.ipa`：

- 文件存在且 `> 0`
- 是合法 zip，`testzip()` 无损坏条目
- 含 `Payload/*.app/Info.plist`
- 解压后对 `Payload` 里的 `.app` 再跑一遍上面全部检查

---

## Personal Team 的限制（免费账号）

- **Provisioning profile 7 天过期**，过期后要重新构建/安装
- 开发证书有效期约 1 年
- 免费账号注册的 App ID（Bundle ID）数量有限（10 个）
- 最多 3 台设备（iPhone/iPad）可用于开发安装
- 不能上传 App Store / TestFlight；不要把这里的 `.ipa` 当成分发包
- 签名状态由本机 Xcode 管理；换机器要重新登录 Apple ID

---

## 常见 signing 错误

### `No Account for Team "XXXXXXXXXX". Add a new account in Accounts settings...`

Xcode 里没有属于这个 Team 的账号（或账号凭据已失效）。

```text
Xcode → Settings → Accounts → 用拥有该 Team 的 Apple ID 登录
```

工具的 `--check` 会先报：
`[FAIL] IOS_SIGNING_BLOCKED: No usable Apple development signing identity / Personal Team provisioning is available.`

### `No profiles for '<bundle id>' were found`

Automatic Signing 还没拿到 development profile。同样先确认账号登录，
然后重跑构建让 Xcode 去申请；不要手工往 preset 里写 `provisioning_profile_uuid_*`。

### `xcode-select is not pointing to Xcode: /Library/Developer/CommandLineTools`

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -license accept
```

工具只检查、给命令，不会替你改系统设置。

### Team ID / 证书对不上

```bash
security find-identity -v -p codesigning      # 看本机可用的签名身份
xcodebuild -project build/ios/development/project/WPG.xcodeproj -showBuildSettings \
  | grep -E "DEVELOPMENT_TEAM|CODE_SIGN_STYLE|PRODUCT_BUNDLE_IDENTIFIER"
```

- 证书 subject 里的 `organizationalUnitName (OU)` 才是签发这张证书的 Team
- preset Team ID、Xcode 账号 Team、证书 OU 三者必须指向同一个 Team
- `CODE_SIGN_STYLE` 必须是 `Automatic`，`PROVISIONING_PROFILE` 必须为空
  （本仓库不允许写死 profile / 证书名）

### Godot 版本不符

仓库固定 **4.6.2**。`godot --version` 不是 4.6.2 时工具直接
`IOS_EXPORT_BLOCKED: Godot 版本是 …，本仓库要求 4.6.2`，不会悄悄用别的版本导出。

---

## 日志与退出码

- `0` 全部成功
- `1` 失败（导出/编译/校验没通过）
- `2` 被环境阻塞（`IOS_EXPORT_BLOCKED` / `IOS_SIGNING_BLOCKED`）

xcodebuild 的完整输出永远写进 `build/logs/*.log`，失败时打印末尾关键诊断，
不吞 stderr。
