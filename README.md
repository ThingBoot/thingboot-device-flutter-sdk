<h1 align="center">芯步设备 SDK · Flutter 版</h1>
<p align="center">ThingBoot Device SDK for Flutter</p>
<p align="center"><b>以 ESP-IDF SDK 为唯一基准 —— Dart API 稳定，原生协议核心闭源分发</b></p>

---

> **授权与计费说明**
>
> - 本 SDK **免费**向开发者开放，不限开发人数、不限编译次数。
> - 每个开发者帐号每年享有 **100 台设备免费接入额度**；设备在芯步控制台注册即可接入。
> - 仅在产品进入**量产阶段**时，才向工厂收取平台接入费，以及开放平台接口调用费（可选）。
> - 未经授权，禁止以任何形式再分发、逆向工程本 SDK，或基于本 SDK 开发同类产品/平台。

## 特性

- **协议以 IDF 为唯一基准**：主题拼接、消息封装、注册签名、mid 生成均与 ESP-IDF 版对齐
- **公开 API 稳定**：`setProduct` / `onOrder` / `replyMessage` / `reportEvent` / `reportState` / `addConfig` / `addTimer` 等接口保持现有语义
- **闭源原生核心**：Windows 的 MD5、URL、MQTT topic 与 `sys_message` 已由 C++ 静态核心提供，发布包不含核心源码
- **平台直连**：HTTP 激活 → reg/v4 注册 → MQTT 连接订阅（QoS 1），自动断线重连（5~60s 随机退避）
- **云代发 API**：`device.api` 支持异步 HTTP 请求、同 mid 应答与超时处理
- **私有化接入**：HTTP / WebSocket / TCP 单端口服务、LAN 发现与外置网关上行的 Flutter 实现
- **Dart 事件循环**：无需 `loop()`，`setup()` 后 SDK 以 Timer 自驱动

## 与 ESP-IDF 版的关系

| | ESP-IDF 版 | Flutter 版 |
|---|---|---|
| 平台 | ESP32 系列 | Flutter（Android / iOS / 桌面） |
| 协议 | thing/{产品}/{设备}/… MQTT + HTTP 注册 | 以 IDF 为唯一基准 |
| 纯协议核心 | C++ 源码基准 | 分平台闭源二进制 + Dart FFI 薄包装 |
| 外设 / WiFi / 以太网 / GSM / 网关 / 桥接 | 支持 | 桩（返回 `ERR_UNSUPPORTED`） |
| 主循环 | 需在 `loop()` 中调用 `device.loop()` | 不需要（Dart 事件循环） |

### 分阶段平台支持

- **Windows x64**：第一阶段原生核心已接入；SDK 自带 FFI 插件、Debug/Release 静态库和 CMake 配置，使用方无需修改 runner。
- **Android / macOS / iOS**：对应原生阶段完成前，显式保留同语义的 Dart 纯逻辑实现，现有功能不因 Windows 改造而退化。
- 原生库加载失败或 ABI 不匹配会显式报错，不会静默切换实现。Web 不支持。

## 安装

### 方式一：git 依赖（推荐）

在项目的 `pubspec.yaml` 中：

```yaml
dependencies:
  thingboot_device:
    git:
      url: https://github.com/ThingBoot/thingboot-device-flutter-sdk.git
```

### 方式二：pub 依赖

```yaml
dependencies:
  thingboot_device: ^0.2.0
```

Windows 首次升级或切换本 SDK 版本后，请重新执行 `flutter pub get` 和干净构建，让 FFI 插件注册及原生链接配置重新生成。最终构建目录应包含 `thingboot_device.dll`，其核心来自静态 `.lib`，不需要额外分发 `.lib` 文件。

SDK 开发者修改 `native/` 后，先运行 `python tool/build_native_windows.py` 重建 Debug/Release 静态库和测试 DLL，再执行测试与 `python release.py --no-git`。发布脚本会拒绝缺失或陈旧的原生库。

## 快速开始

```dart
import 'package:thingboot_device/thingboot_device.dart';

final device = ThingBootDevice();

Future<void> main() async {
  // 调试信息打印
  device.onDebug((category, message) {
    print('${device.millis()} $category | $message');
  });

  // 设置产品信息（在芯步控制台获取）
  device.setProduct(
    'your-product-key',
    'your-product-secret',
    'your-board',
    'flutter',
    '0.1.0.1',
  );

  // 设备接入激活码（开发阶段免费领取）：
  // https://www.thingboot.com/developer/center/access/
  device.setActiveCode('your-active-code');

  // 注册平台命令回调（首参为消息 ID mid，应答时原样传回）
  device.order.onOrder((mid, data) {
    print('收到命令: $data');
    device.order.replyMessage(mid, '{"result":"ok"}');
  });

  // 设备每次上线后，SDK 通过该回调获取全量属性并上报
  device.state.onFetch(() => {'power': false});

  // 异步初始化：激活 → 注册 → 连 MQTT → 订阅
  await device.setup();
}
```

完整示例见 [example/main.dart](example/main.dart)。

## 接口对照

Arduino 版子模块为大写成员（`device.Config`），Flutter 版按 Dart 惯例为小写（`device.config`），方法名保持 camelCase 原样：

| Arduino | Flutter | 说明 |
|---|---|---|
| `device.setProduct(...)` | `device.setProduct(...)` | 产品信息 |
| `device.Order.onOrder(cb)` | `device.order.onOrder(cb)` | 命令回调 |
| `device.Order.replyMessage(mid, data)` | `device.order.replyMessage(mid, data)` | 命令应答 |
| `device.Event.reportEvent(name, data)` | `device.event.reportEvent(name, data)` | 事件上报 |
| `device.State.onState(name, sec, cb)` | `device.state.onState(name, sec, cb)` | 定时状态上报 |
| `device.State.onFetch(cb)` | `device.state.onFetch(cb)` | 上线全量属性上报 |
| `device.Config.addConfig(...)` | `device.config.addConfig(...)` | 设备配置 |
| `device.Timer.addTimer(ms, cb)` | `device.timer.addTimer(ms, cb)` | 用户定时器 |
| `device.Message.publishMessage(...)` | `device.message.publishMessage(...)` | 消息发布 |
| `device.setup()` / `device.loop()` | `await device.setup()` | 初始化（无 loop） |

错误码常量（`ERR_OK`、`ERR_CONFIG_*`、`ERR_EVENT_*`、`ERR_TIMER_*` 等）与 Arduino 版 `ThingBootSDK/Errors.h` 完全一致；Flutter 版另加 `ERR_UNSUPPORTED`（90001），用于当前平台不支持的外设/网关/桥接等桩方法。

## 文档

完整协议与平台语义见芯步公共文档（docs 目录下的 HTML 主题文档）。
