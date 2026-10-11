# Godot 4.6.2 与 webrtc-native 1.2.2

核对日期：2026-10-10。生产 `export_presets.cfg` 没有改。

## 引擎

本机编辑器：`4.6.2.stable.official.71f334935`（macOS arm64）。

官方扩展：`godotengine/webrtc-native` tag `1.2.2-stable`（2026-09-30）。

- 包：`godot-extension-webrtc_native.zip`
- sha256：`98e9446921740d995bd9ca1be48798dc3c2ceed51e044a25ce18b3cff11f56e5`
- `compatibility_minimum = 4.3`
- 依赖：libdatachannel 0.24.6，mbedTLS 3.6.7
- 入口：`webrtc_extension_init`
- 排除 tag：`web`、`no-webrtc`。HTML5 仍用引擎自带 WebRTC，不走这个原生库。

在本机 Godot 4.6.2 headless 里，`WebRTCPeerConnection.initialize({})` 成功，并且 `WebRTCLibPeerConnection` 已注册。4.3 的 compatibility 声明和 4.6.2 实际加载是一致的。

Headless 不会自动发现扩展。游戏进程读 `.godot/extension_list.cfg`。编辑器第一次导入项目时会自己写这份清单。

## 预编译库（已解压核对，不是从源码编的）

| 平台 | 官方包里的库 | 本机是否跑过 |
|---|---|---|
| Windows x86_64 / x86_32 / arm64 | debug + release DLL | 否 |
| macOS universal（x86_64 + arm64） | debug + release framework | 是，debug framework，本机 arm64 |
| Linux x86_64 / x86_32 / arm64 / arm32 | debug + release .so | arm64 在 Docker 里跑过 headless。其余架构只核对了文件 |
| Android arm64 / x86_64 | debug + release .so | 否。没有 32 位 Android 库 |
| iOS arm64 / 模拟器 | 包内有，本任务不测 | 否 |

Android 导出仍然需要 `INTERNET`。生产 Android preset 里这个权限已经是打开的，这次没有改任何 preset。

## 源码构建（未在本机执行）

本机没有 scons。下面是 1.2.2 的上游方式，供以后补库，不是这次的构建记录。

```bash
git clone --recurse-submodules https://github.com/godotengine/webrtc-native.git
cd webrtc-native
git checkout 1.2.2-stable
# Godot 4 默认 api_version=4.3，子模块是 godot-cpp / libdatachannel / mbedTLS
scons platform=linux target=template_release arch=x86_64
scons platform=windows target=template_release arch=x86_64
scons platform=macos target=template_release
scons platform=android target=template_release arch=arm64
```

Godot 4 这条分支的平台名是 `macos`，不是 README 里 Godot 3 的 `osx`。Android 需要 `ANDROID_NDK_ROOT`。产物在 `bin/extension/addons/webrtc_native/`。

## 1.2.2 做不到的配置

`WebRTCLibPeerConnection::_initialize` 只读取 `iceServers` 和 `libdatachannel` 里的 `enableIceTcp`、`enableIceUdpMux`、`portRangeBegin`、`portRangeEnd`、`mtu`。没有 `iceTransportPolicy`。因此「只填 TURN」仍会收集 host candidate。要证明数据走中继，必须让直连先失败，再看 TURN 模式能否双向收发，并且双方都出现 `typ relay`。

## 这次实际跑过的结果

| 检查 | 结果 |
|---|---|
| 信令单测（建房、加入、SDP/ICE、取消、空闲回收、拒绝快照） | 通过 |
| macOS 扩展加载 | 通过 |
| 主工程不加载这份扩展 | 通过 |
| 本机回环：超时、取消、双向数据、断开 | 通过。这是 127.0.0.1，不是跨网 |
| Linux arm64 扩展加载 | 通过。容器里的 Godot 4.6.2 headless 用了官方 linux arm64 库 |
| TURN 中继数据路径 | 通过，范围限于两个 Linux 容器。直连被 iptables 丢弃后双方超时；只加 coturn 后双向 ping/pong，并且出现 `typ relay`。不是公网，也不是两台物理机器 |
| 两台不同网络的桌面设备 | 阻塞。这台机器上没有第二台设备 |
