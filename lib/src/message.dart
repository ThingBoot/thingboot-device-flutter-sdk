/// 消息通信子模块，对应 Arduino 版 ThingBootSDK/Message.h。
library;

import 'device.dart';
import 'types.dart';

/// 消息子模块，通过 `device.message` 访问。
class TbMessage {
  final ThingBootDevice _device;

  TbMessage(this._device);

  /// 生成消息 ID（mid，8 位），与 SDK 内部同规则（md5 居中截 8 位），
  /// 对应 Arduino 的 `mid()`。
  String mid() => _device.newMid();

  /// 向平台发布消息，对应 Arduino 的 `publishMessage()`。
  ///
  /// [data] 为合法 JSON 片段；[mid] 为空时自动生成；[device] 大于 0 时
  /// 标记消息来源设备（子设备上行）。
  bool publishMessage(SysTopic topic, String data,
      {String? mid, int device = 0}) {
    return _device.publish(topic, data, mid: mid, device: device);
  }
}
