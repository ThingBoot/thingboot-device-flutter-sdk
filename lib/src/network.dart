/// 网络子模块，对应 Arduino 版 ThingBootSDK/Network.h。
///
/// [getNetworkInfo] 返回本机网络基本信息（可用）；
/// WiFi/以太网/GSM 管理在 Flutter 侧无意义，全部为 [ERR_UNSUPPORTED] 桩。
library;

import 'dart:convert';
import 'dart:io';

import 'device.dart';
import 'errors.dart';

/// 网络子模块，通过 `device.network` 访问。
class TbNetwork {
  // 保留引用以对齐 Arduino 结构，当前版本未使用。
  // ignore: unused_field
  final ThingBootDevice _device;

  TbNetwork(this._device);

  /// 当前网络类型名（写入 reg payload 的 network_type，对应
  /// common/system.h 的 `sys_network()`）。
  String networkTypeName = 'unknown';

  /// addon 安装（不支持）。
  int installEthernet() => ERR_UNSUPPORTED;

  /// addon 安装（不支持）。
  int installGSM() => ERR_UNSUPPORTED;

  /// 获取当前网络信息（JSON 字符串），对应 Arduino 的 `getNetworkInfo()`
  /// 与 common/networks.h 的 `network_info()`。
  ///
  /// Flutter 侧返回本机基础信息：平台与主机名（网卡枚举为异步 API，
  /// 与 Arduino 同步签名不一致，故不携带）。
  String getNetworkInfo() {
    return jsonEncode({
      'type': networkTypeName,
      'platform': Platform.operatingSystem,
      'hostname': Platform.localHostname,
    });
  }

  /// 连接 WiFi（不支持）。
  int connectWiFi([String? ssid, String? psk]) => ERR_UNSUPPORTED;

  /// 断开 WiFi（不支持）。
  int disconnectWiFi() => ERR_UNSUPPORTED;

  /// 清空 WiFi 配置（不支持）。
  int clearWiFiConfig() => ERR_UNSUPPORTED;

  /// 添加 WiFi 配置（不支持）。
  int addWiFiConfig(String ssid, String psk, [int? pos]) => ERR_UNSUPPORTED;

  /// 更新 WiFi 配置（不支持）。
  int updateWiFiConfig(String ssid, String psk) => ERR_UNSUPPORTED;

  /// 删除 WiFi 配置（不支持）。
  int deleteWiFiConfig(dynamic ssidOrPos) => ERR_UNSUPPORTED;

  /// 获取 WiFi 配置（不支持）。
  int getWiFiConfig() => ERR_UNSUPPORTED;

  /// 设置以太网 SPI 片选引脚和复位引脚（不支持）。
  int setEthernetPin(int cs, [int rst = -1]) => ERR_UNSUPPORTED;

  /// 尝试连接以太网（不支持）。
  int tryConnectEthernet() => ERR_UNSUPPORTED;

  /// 连接以太网（不支持）。
  int connectEthernet() => ERR_UNSUPPORTED;

  /// 断开以太网（不支持）。
  int disconnectEthernet() => ERR_UNSUPPORTED;

  /// 尝试连接 GSM（不支持）。
  int tryConnectGSM() => ERR_UNSUPPORTED;

  /// 连接 GSM（不支持）。
  int connectGSM() => ERR_UNSUPPORTED;

  /// 断开 GSM（不支持）。
  int disconnectGSM() => ERR_UNSUPPORTED;

  /// 设置 GSM 串口（不支持）。
  int setGSMSerialPort(dynamic serial, [int baud = 0]) => ERR_UNSUPPORTED;
}
