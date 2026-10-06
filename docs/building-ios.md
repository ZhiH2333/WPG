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
application/app_store_team_id="334R786Y6V"
```

- 这是 **Team ID**，不是 Apple ID，也不是账号邮箱。
- 工具从 preset 读它，不再在别处复制一份，避免两边不一致。
- Xcode 工程里对应 `DEVELOPMENT_TEAM` = 同一个 Team ID、`CODE_SIGN_STYLE = Automatic`，
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

## iOS 图标（preset 必须接线）

`export_presets.cfg` 的 iOS preset 里所有 `icons/*` 键都必须指向真实存在的
`res://` 文件，否则 `tools/ci/architecture.py` 的「图标接线」守卫会 FAIL（CI 红）。

当前接线：每个尺寸键指向 `icons/ios/AppIcon.appiconset/` 里**同像素尺寸**的成品，
且同时覆盖 light / dark / tinted 三套：

```
icons/settings_58x58      = res://icons/ios/AppIcon.appiconset/Icon-29@2x.png        (58px)
icons/notification_114x114= res://icons/ios/AppIcon.appiconset/Icon-38@3x.png        (114px)
icons/iphone_180x180      = res://icons/ios/AppIcon.appiconset/Icon-60@3x.png        (180px)
icons/ipad_167x167        = res://icons/ios/AppIcon.appiconset/Icon-83.5@2x.png      (167px)
icons/ios_192x192         = res://icons/ios/AppIcon.appiconset/Icon-64@3x.png        (192px)
… 共 45 个键
icons/icon_1024x1024      = res://icons/ios/icon-1024.png                            (母版)
icons/app_store_1024x1024 = res://icons/ios/appstore-1024.png                        (母版)
```

- 图标唯一真源是 `wpg.icon/`，用 `python3 tools/icons/generate_icons.py` 重新生成；
  它会同时重建 `icons/ios/AppIcon.appiconset/`，**改完图标记得把 preset 里对应键指回去**。
- `icons/ios/.gdignore` 会让这些 PNG 不进 PCK（导出期素材不能进包），
  但 Godot 导出时仍能按 `res://` 路径读到它们。
- Godot 导出后会在工程里生成 `WPG/Images.xcassets/AppIcon.appiconset`
  （16 个尺寸 × light/dark/tinted = 48 张），Xcode 直接使用。
- 不要留空键：空值 = 守卫失败。

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

### `Your team has no devices from which to generate a provisioning profile`

免费 Personal Team **必须先有一台已注册的设备**，Apple 才会签发 development
provisioning profile；没有设备就一定出不了 `.app` / `.ipa`。

```text
Xcode → Window → Devices and Simulators → 选中你的 iPhone/iPad → Use for Development
```

前提（缺一不可）：

- 数据线连接，电脑弹窗点「信任」
- 手机已解锁；iOS 16+ 要打开 `设置 → 隐私与安全性 → 开发者模式`
- 设备在 Xcode 里显示为可用（`xcrun devicectl list devices` 能看到它）

验证：

```bash
xcrun devicectl list devices      # 应列出你的设备
python3 tools/build/export_platform.py ios --check
```

`--check` 在「有 profile」之前会先看设备状态，直接把上面那条修复命令打出来，
不会假装环境就绪（`IOS_SIGNING_BLOCKED`，退出码 2）。

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
