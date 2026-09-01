/// 桥接通信子模块（桩），对应 Arduino 版 ThingBootSDK/Bridge.h。
///
/// Flutter 应用无 UART/SPI 能力，所有方法返回 [ERR_UNSUPPORTED] / 0。
library;

import 'device.dart';
import 'errors.dart';

/// 桥接子模块（桩），通过 `device.bridge` 访问。
class TbBridge {
  // 保留引用以对齐 Arduino 结构，当前版本未使用。
  // ignore: unused_field
  final ThingBootDevice _device;

  TbBridge(this._device);

  /// 配置并启动 UART 桥接（不支持）。
  int setupUart(dynamic port, int baud, {int rxPin = -1, int txPin = -1}) =>
      ERR_UNSUPPORTED;

  /// 配置并启动 SPI 桥接（不支持）。
  int setupSpi(int sck, int miso, int mosi, int cs,
          {int speed = 1000000}) =>
      ERR_UNSUPPORTED;

  /// 发送原始字节数据（不支持）。
  int send(List<int> data) => ERR_UNSUPPORTED;

  /// 发送字符串（不支持）。
  int sendString(String str) => ERR_UNSUPPORTED;

  /// 发送格式化字符串（不支持）。
  int sendPrintf(String fmt, [List<dynamic>? args]) => ERR_UNSUPPORTED;

  /// 接收数据（不支持）。
  int receive(List<int> buffer, {int timeoutMs = 0}) => ERR_UNSUPPORTED;

  /// 查询当前可读取的字节数（不支持）。
  int available() => 0;

  /// 主循环处理（不支持）。
  int handle() => ERR_UNSUPPORTED;

  /// 设置数据接收回调（不支持）。
  int setOnReceive(void Function(List<int> data)? callback) =>
      ERR_UNSUPPORTED;

  /// 设置错误回调（不支持）。
  int setOnError(void Function(int code)? callback) => ERR_UNSUPPORTED;

  /// 获取统计信息（不支持）。
  int getStats() => ERR_UNSUPPORTED;
}
