<h1 align="center">芯步设备 SDK · Flutter 版</h1>
<p align="center">ThingBoot Device SDK for Flutter</p>
<p align="center"><b>ESP Arduino 版 SDK 的 Flutter 移植 —— 接口高度一致，协议完全一致</b></p>

---

> **授权与计费说明**
>
> - 本 SDK **免费**向开发者开放，不限开发人数、不限编译次数。
> - 每个开发者帐号每年享有 **100 台设备免费接入额度**；设备在芯步控制台注册即可接入。
> - 仅在产品进入**量产阶段**时，才向工厂收取平台接入费，以及开放平台接口调用费（可选）。
> - 未经授权，禁止以任何形式再分发、逆向工程本 SDK，或基于本 SDK 开发同类产品/平台。

## 特性

- **协议完全一致**：主题拼接、消息封装、注册签名、mid 生成均与 Arduino 版逐字节对齐
- **接口高度一致**：`setProduct` / `onOrder` / `replyMessage` / `reportEvent` / `reportState` / `addConfig` / `addTimer` 等方法名与语义照搬 Arduino 版
- **平台直连**：HTTP 激活 → reg/v4 注册 → MQTT 连接订阅（QoS 1），自动断线重连（5~60s 随机退避）
- **纯 Dart 事件循环**：无需 `loop()`，`setup()` 后 SDK 以 Timer 自驱动

## 与 Arduino 版的关系

| | Arduino 版 | Flutter 版 |
|---|---|---|
| 平台 | ESP8266 / ESP32 | Flutter（Android / iOS / 桌面） |
| 协议 | thing/{产品}/{设备}/… MQTT + HTTP 注册 | 完全相同 |
| 外设 / WiFi / 以太网 / GSM / 网关 / 桥接 | 支持 | 桩（返回 `ERR_UNSUPPORTED`） |
| 主循环 | 需在 `loop()` 中调用 `device.loop()` | 不需要（Dart 事件循环） |

## 安装

### 方式一：git 依赖（推荐）

在项目的 `pubspec.yaml` 中：

```yaml
dependencies:
  thingboot_device:
    git:
      url: https://github.com/ThingBoot/thingboot-device-flutter.git
```

### 方式二：pub 依赖

```yaml
dependencies:
  thingboot_device: ^0.1.0
```

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
