/// 命令处理子模块，对应 Arduino 版 ThingBootSDK/Order.h。
library;

import 'device.dart';
import 'errors.dart';
import 'types.dart';

/// 命令子模块，通过 `device.order` 访问。
class TbOrder {
  final ThingBootDevice _device;

  TbOrder(this._device);

  /// 设置命令回调，对应 Arduino 的 `onOrder()`。
  ///
  /// 回调首参为消息 ID（mid），第二参为命令数据；
  /// 应答时将同一个 mid 传给 [replyMessage]，平台据此关联命令与应答。
  int onOrder(TbOrderCallback? callback) {
    _device.orderCallback = callback;
    return ERR_OK;
  }

  /// 命令应答，对应 Arduino 的 `replyMessage()`。
  ///
  /// [mid] 为收到的命令消息 ID，[data] 为合法 JSON 片段。
  bool replyMessage(String mid, String data) {
    return _device.publish(SysTopic.order, data, mid: mid);
  }
}
