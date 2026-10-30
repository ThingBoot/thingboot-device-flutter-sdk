<h1 align="center">芯步设备 SDK · Flutter 版</h1>
<p align="center">ThingBoot Device SDK for Flutter</p>
<p align="center"><b>通过统一 Dart API，将 Flutter 应用接入芯步平台</b></p>

---

> **授权与计费说明**
>
> - 本 SDK **免费**向开发者开放，不限开发人数、不限编译次数。
> - 每个开发者帐号每年享有 **100 台设备免费接入额度**；设备在芯步控制台注册即可接入。
> - 仅在产品进入**量产阶段**时，才向工厂收取平台接入费，以及开放平台接口调用费（可选）。
> - 未经授权，禁止以任何形式再分发、逆向工程本 SDK，或基于本 SDK 开发同类产品/平台。

## 功能

- **设备接入**：激活、注册、凭证保存、自动重连和上下线状态通知。
- **平台通信**：MQTT 命令应答、事件与状态上报、配置同步、NTP 和 OTA 通知。
- **配置管理**：注册设备配置项、读取和保存配置、批量读取及配置变化回调。
- **云代发 API**：通过 `device.api` 发起异步 HTTP 请求，接收关联应答和超时结果。
- **私有化接入**：HTTP、WebSocket、TCP、局域网发现和外置网关上行。
- **应用集成**：无需调用 `loop()`，初始化后由 SDK 自动维护后台任务。

## 支持平台

支持 Windows、Android、iOS、macOS 和 Linux，不支持 Web。

Windows x64、Android、macOS 和 iOS 会随应用构建自动集成原生组件，无需手动修改构建工程或现有 Dart 代码。Android 支持 arm64-v8a、armeabi-v7a、x86 和 x86_64，原生组件兼容 16 KB 页大小。macOS 提供 universal 原生库，iOS 提供真机与模拟器静态 XCFramework。其他平台使用标准 Flutter 依赖流程。

## 安装

### Git 依赖

```yaml
dependencies:
  thingboot_device:
    git:
      url: https://github.com/ThingBoot/thingboot-device-flutter-sdk.git
```

### pub 依赖

```yaml
dependencies:
  thingboot_device: ^0.5.0
```

安装或升级后执行：

```bash
flutter pub get
```

Windows 首次升级时建议进行一次干净构建，以刷新原生插件配置。

## 快速开始

```dart
import 'package:thingboot_device/thingboot_device.dart';

final device = ThingBootDevice();

Future<void> main() async {
  device.onDebug((category, message) {
    print('${device.millis()} $category | $message');
  });

  // 在芯步控制台获取产品信息。
  device.setProduct(
    'your-product-key',
    'your-product-secret',
    'your-board',
    'flutter',
    'your-firmware-version',
  );

  // 开发阶段可免费领取激活码：
  // https://www.thingboot.com/developer/center/access/
  device.setActiveCode('your-active-code');

  device.order.onOrder((mid, data) {
    print('收到命令: $data');
    device.order.replyMessage(mid, '{"result":"ok"}');
  });

  device.state.onFetch(() => {'power': false});

  // 自动完成激活、注册、MQTT 连接和订阅。
  await device.setup();
}
```

完整示例见 [example/main.dart](example/main.dart)。

## 常用接口

| 接口 | 用途 |
|---|---|
| `device.setProduct(...)` | 设置产品信息 |
| `device.setActiveCode(...)` | 设置设备激活码 |
| `await device.setup()` | 初始化并接入平台 |
| `device.order.onOrder(cb)` | 接收平台命令 |
| `device.order.replyMessage(mid, data)` | 应答平台命令 |
| `device.event.reportEvent(name, data)` | 上报事件 |
| `device.state.onFetch(cb)` | 上线时提供全量属性 |
| `device.state.onState(name, sec, cb)` | 定时上报状态 |
| `device.config.addConfig(...)` | 注册设备配置项 |
| `device.config.readConfig(...)` | 读取设备配置 |
| `device.config.saveConfig(...)` | 保存设备配置 |
| `device.message.publishMessage(...)` | 发布指定主题消息 |
| `device.api.request(...)` | 发起云代发 HTTP 请求 |
| `device.resume()` | 应用恢复前台时重建连接 |
| `device.dispose()` | 释放定时器和网络资源 |

错误码统一使用 `ERR_OK`、`ERR_CONFIG_*`、`ERR_EVENT_*`、`ERR_TIMER_*` 等常量；当前平台不支持的硬件能力返回 `ERR_UNSUPPORTED`。

## 文档

平台协议和更多接入说明见芯步开发者文档。SDK 版本变化见 [CHANGELOG.md](CHANGELOG.md)。
