# Changelog

## 0.1.0

- 首个可用版本，接口与 ESP Arduino SDK（v1.4.x）高度一致。
- 已实现：Core（setProduct/setActiveCode/setup 等）、Config、Order、Event、Message、State、Timer、Utils；激活 / reg 注册 / MQTT 连接订阅 / 下行分发 / NTP 全链路。
- 不支持（返回 `ERR_UNSUPPORTED`）：Peripheral、Bridge、Gateway、Network addon（WiFi/以太网/GSM 管理）、OTA、设备重启。
