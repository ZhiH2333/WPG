# 应用图标

本目录分两类东西：

* `logo.png` —— 开屏字标原图（你提供的素材），运行时从 PCK 加载，
  所以必须**能被 Godot 导入**，目录根保持可导入状态。
* `splash.png` —— 由 `logo.png` 生成的开屏底图：字标只占画布宽度的一半，四周留白。
  `application/boot_splash/image` 与 `ui/boot_screen.tscn` 共用它。
* `ios/` `macos/` `android/` `windows/` `web/` `wpg_iOS_Exports/` —— 导出期素材，
  全部由 `tools/icons/generate_icons.py` 从仓库根目录的 `wpg.icon`
  （Apple Icon Composer 文档）生成。每个子目录带 `.gdignore`，Godot 不会把它们
  当游戏资源导入 —— 否则每种外观的 1024 PNG 都会被塞进每个平台的 PCK（约 7 MB）。

重新生成：

```bash
python3 tools/icons/generate_icons.py          # 需要 macOS + Xcode 26（ictool / iconutil）
python3 tools/icons/generate_icons.py --list   # 只看分组
```

## 数据流

```
wpg.icon                      ← 唯一真源（Icon Composer 文档）
  └─ ictool（Xcode 自带）      ← Apple 原生渲染
       ├─ iOS  Default / Dark / TintedDark          → icons/ios/
       └─ macOS Default / Dark / TintedDark          → icons/macos/
  └─ 图层几何重建（icon.json 的 scale=1.21、translation=(-53,70) 点）
       └─ Android 自适应图标前景 / 单色剪影           → icons/android/
```

Apple 平台一律用 `ictool` 渲染，深色、着色（iOS 18+ Tinted）由系统原生适配；
Android / Windows / Web 从原生渲染派生，图层的**比例与位置与 Icon Composer 完全一致**，
只按各平台规范重新排布背景与圆角。

## 各平台接线

| 平台 | 产物 | 接线位置 |
| --- | --- | --- |
| 编辑器 / Linux / Web favicon | `icon.png`（项目根目录，512 满幅） | `project.godot` → `application/config/icon` |
| 开屏（引擎启动图 + 进度条） | `icons/splash.png` | `project.godot` → `application/boot_splash/image` + `stretch_mode=2`，以及 `ui/boot_screen.tscn` |
| iOS / iPadOS | `icons/ios/icon-1024{,_dark,_tinted}.png`、`appstore-1024{,_dark,_tinted}.png` | `export_presets.cfg` → `[preset.5]` `icons/icon_1024x1024*`、`icons/app_store_1024x1024*` |
| iOS / iPadOS（Xcode 原生工程） | `icons/ios/AppIcon.appiconset/` | 直接拖进 Xcode |
| macOS 26 液态玻璃 | `wpg.icon` 本体 | `export_presets.cfg` → `application/liquid_glass_icon`（Godot 交给 `actool` 编译成 `Assets.car`） |
| macOS < 26 / 兜底 | `icons/macos/icon.icns` | `application/icon` |
| Android | `icons/android/ic_launcher_192.png`、`ic_launcher_{foreground,background,monochrome}_432.png` | `launcher_icons/{main_192x192,adaptive_*_432x432}` |
| Windows | `icons/windows/icon.ico`、`console_wrapper.ico` | `application/icon`、`application/console_wrapper_icon` |
| Web | `icons/web/icon-{144,180,512}.png` | `progressive_web_app/icon_*` |
| Web 深浅色 favicon | `icons/web/favicon-{light,dark}.png` | 导出后处理注入，见 `tools/build/export_platform.py` |

### 深浅色适配

* **iOS / iPadOS**：`AppIcon.appiconset` 里每个尺寸都有 `light` / `dark` / `tinted` 三份，
  由 Godot 依据 `icons/*_dark`、`icons/*_tinted` 生成，`Contents.json` 带
  `appearances` (`luminosity: dark` / `tinted`)。
* **macOS**：`wpg.icon` 经 `actool` 编译成 `Assets.car`，系统按外观自行取用；
  `Info.plist` 里同时写入 `CFBundleIconName`。
* **Web**：Godot 只写一份浅色 `*.icon.png`，构建时补上深色版本并注入
  `media="(prefers-color-scheme: dark|light)"` 的 `<link>`。
* **Android**：系统没有夜间启动图标概念，使用浅色外观；
  Android 13+ 由 `ic_launcher_monochrome` 提供主题图标（深色五官做了镂空）。

### 蒙版与圆角

* iOS / macOS / Windows：使用 `ictool` 的原生圆角与投影，不做二次裁切。
* Android 旧版启动图标：保留原生圆角（`ic_launcher_192.png`）。
* Android 自适应图标：108 dp 画布，1024 画布映射到中间 72 dp 安全区，
  圆角形状交给启动器的蒙版，因此前景不做裁切、可以溢出安全区。
* App Store / Google Play / PWA / `apple-touch-icon`：**满幅不透明**，
  因为这些位置由系统自己套用圆角或圆形蒙版，提前切角会造成二次裁切。

## 注意

* `wpg_iOS_Exports/` 是设计阶段从 Icon Composer 手工导出的参考图，不参与构建，
  只加了 `.gdignore` 防止被导入。
* `logo.png` 是你提供的素材，生成器不会改写它。
* 生成需要 macOS 与 Xcode 26+；CI（Linux）直接使用仓库里已提交的产物，
  不会重新生成。改动 `wpg.icon` 后请在 macOS 上重跑生成器并提交产物。
* `tools/ci/architecture.py` 的 `_icon_guards()` 会校验这里的所有接线。

### 启动画面的比例（踩过的坑）

`application/boot_splash/stretch_mode` 的默认值是 `1`（`Keep`），而 Godot 的 `Keep`
是按**窗口长边**撑满：

```cpp
case SPLASH_STRETCH_MODE_KEEP:
  if (window.width > window.height) {                 // 横屏
    screenrect.size.y = window.height;                // 高度撑满
    screenrect.size.x = img.width * window.height / img.height;
  }
```

1196×270 的字标在 2280×1080 上会被放大到 **4784px 宽**，只露出中间的 48%
（"Wild Pigeon" 只剩 "ild Pig"），而且白色字标盖满全高，底部的进度条看不见了。

所以这里固定用 `stretch_mode=2`（`Keep Width`）：永远等比铺满宽度、垂直居中，
字标完整可见，上下留出背景色给进度条。`tools/ci/architecture.py` 有守卫锁住这个值。
### 开屏：字标缩小 + 进度条 + 交叉渐入

Godot 4 **没有内建启动进度条** —— `RenderingServer` 只在启动时用
`set_boot_image_with_stretch()` 画一次静态图，之后到主场景就绪之间没有任何绘制代码，
而且那段时间里还没有 GDScript 在跑（全量源码搜索 `boot_progress` 为空）。
所以进度条只能由一个真正的场景提供：

* `ui/boot_screen.tscn` 是 `run/main_scene`。它自身几乎瞬时加载完，
  再把 `ui/main_menu.tscn` 丢给 `ResourceLoader.load_threaded_request()` 后台加载。
* 字标用与 `application/boot_splash` **完全相同**的规则绘制（满宽等比、垂直居中），
  并且共用同一张 `splash.png`，所以从引擎启动图切到这个场景时画面不会跳。
* 「缩小」靠的是 `splash.png` 的留白：Godot 的 boot_splash 没有缩放百分比选项，
  只能把字标放进一张大画布里（`SPLASH_LOGO_RATIO = 0.5`，见生成器）。
* 进度条颜色/高度与 `ui/loading_screen.tscn` 一致，观感连续。
* 加载完成后做**交叉渐入**：新场景挂到上层从 0 淡到 1，开屏全程保持不透明当底。
  两层同时对淡会在中段把整屏拉向清屏色（alpha 被吃两次，画面暗一下），
  所以只淡入新场景，等它盖满再丢掉开屏。
