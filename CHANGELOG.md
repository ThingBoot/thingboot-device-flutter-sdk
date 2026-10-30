# Changelog

## 0.2.0（原生核心改造阶段 1，2026-10-30）

- Windows x64 新增闭源 C++ 协议核心和 Dart FFI 插件：MD5、URL 编码、MQTT topic、`sys_message` 与 mid 相关路径切换到原生实现，公开 Dart API 不变。
- 提供 Debug/Release 静态库和 SDK 自带 CMake 集成，使用方无需修改 runner；发布包不包含 C++ 核心源码。
- Android、macOS、iOS 在对应阶段完成前保留显式 Dart 实现；Windows 原生加载或 ABI 校验失败会显式报错，不静默回退。
- 改造计划与各阶段验收记录见开发工作区 `NATIVE_CORE_REFACTOR_PLAN.md`。

## 未发布（同步 IDF 基准 2026-10-30）

- 注册与系统信息新增 SDK 名称和版本标识；修正带本机设备 ID 的 config 下行路由。
- MQTT 精简启动订阅并增加全主题限频；新增 `device.api` 云平台异步 HTTP 请求；调试模式支持最长 3600 秒倒计时自动关闭。
- 私有化网关新增 HTTP / WebSocket / TCP 三协议、UDP 19820 发现、内外置绑定和每设备双向签名；改用新签名协议，不再兼容旧 `gateway_info.pwd` 公式。
- 发布链接入芯步平台优先发布、SHA-256 校验与可复现 ZIP；常规发布禁止同版本不同产物覆盖。

## 未发布（设备 ID 稳定性整改 2026-10-04）

- **桌面端设备特征值改硬件级种子（ID 重装系统不变）**：伪 MAC 派生由"第一块有网关网卡 MAC"改为逐级兜底链——Windows：BIOS 序列号 → 主板序列号 → CPU ProcessorId → PCI 内置网卡 MAC（纯 `dart:io` 调 PowerShell，不加插件）；macOS：IOPlatformUUID；Linux：DMI product_uuid → machine-id；最终兜底仍为联网网卡真实 MAC。Android/iOS 派生路径不变。仅首次写存档时派生，已有存档原样保留（老设备身份不受影响）。
- **派生失败可观测**：每级种子的命中来源（`bios_serial`/`cpu_id`/`pci_nic`/`android_id`/`ios_idfv`/`io_uuid`/`dmi_uuid`/`machine_id`/`nic_mac`/`random_fallback`）与派生结果经调试日志输出，失败不再静默吞掉。

## 未发布（同步 IDF 基准 2026-10-04）

- **system 命令应用层转发（限公共/平台语义）**：`system` 为 Map 且含 `bench`（设置工作台=带新 bench 重新 reg）或为字符串 `restart`（应用可自行实现重启）时转发应用层 `orderCallback`；无回调时保持原应答行为。**产品级命令不得进 system**——曾误加的 `mode` 转发已回退（工作模式属产品级命令，应由产品自行处理；system 的 mode 语义是平台/私有化模式）。
- **config 主题批量读（数组格式）**：`data` 为数组 `["restore","autorun"]` 时逐项读并合并应答（config/client，mid 原样带回；单项不存在则不出现）。对齐 IDF SDK 2026-10-01 变更。
- **OTA 主题 type 分支 + `onOTA(type, content)` 回调**：`data` 带 `type` 且非 `firmware` 时只回协议应答并透传完整 content（不断连/不预检/不重启）；`type=="firmware"` 走既有固件路径并额外通知；reg 响应 `data.ota` 显式忽略带 `type` 的条目。对齐 IDF SDK 2026-09-27 变更。
- 核对无需改动项：`getParam`（差一缺陷在移植时已修正，与 IDF 2026-09-22 修复等价）；reg `master` 键多态（数字分支已具备）；`TB_BOARD` 宏为 C 编译期方案，Flutter 不适用。
- 未同步（挂账）：`Network.onNetworkChange`（2026-09-09，Flutter 侧需连接状态监听基础设施，SuperScreen 暂无需求）。

## 0.1.0

- 首个可用版本，接口与 ESP Arduino SDK（v1.4.x）高度一致。
- 已实现：Core（setProduct/setActiveCode/setup 等）、Config、Order、Event、Message、State、Timer、Utils；激活 / reg 注册 / MQTT 连接订阅 / 下行分发 / NTP 全链路。
- 不支持（返回 `ERR_UNSUPPORTED`）：Peripheral、Bridge、Gateway、Network addon（WiFi/以太网/GSM 管理）、OTA、设备重启。
