/// 网关子模块（桩），对应 Arduino 版 ThingBootSDK/Gateway.h。
///
/// Flutter 侧无子设备传输层，所有方法返回 [ERR_UNSUPPORTED] / false / 空表。
library;

import 'device.dart';
import 'errors.dart';
import 'types.dart';

/// 子设备记录，对应 Arduino 的 `ThingBootChild`。
class TbChild {
  /// 子设备 ID
  int id = 0;

  /// 子设备键
  String key = '';

  /// 最后活动时间（毫秒，millis 时基）
  int active = 0;

  /// 在线状态
  bool online = false;
}

/// 网关子模块（桩），通过 `device.gateway` 访问。
class TbGateway {
  // 保留引用以对齐 Arduino 结构，当前版本未使用。
  // ignore: unused_field
  final ThingBootDevice _device;

  TbGateway(this._device);

  /// 安装网关 addon（不支持）。
  int install() => ERR_UNSUPPORTED;

  /// 添加子设备（不支持）。
  int addChild(int id, String key, [int active = 0]) => ERR_UNSUPPORTED;

  /// 按 ID 查找子设备（不支持）。
  bool findChild(int id, [TbChild? child]) => false;

  /// 按键查找子设备（不支持）。
  bool findChildByKey(String key, [TbChild? child]) => false;

  /// 更新子设备活动时间（不支持）。
  int updateChildActive(int id) => ERR_UNSUPPORTED;

  /// 子设备列表（不支持）。
  List<int> childList([String type = 'all']) => const [];

  /// 移除子设备（不支持）。
  int removeChild(int id) => ERR_UNSUPPORTED;

  /// 子设备数量（不支持）。
  int countChildren() => 0;

  /// 清空子设备表（不支持）。
  int clearChildren() => ERR_UNSUPPORTED;

  /// 判断子设备是否在线（不支持）。
  bool isChildOnline(int id) => false;

  /// 设定离线判定秒数（不支持）。
  int setOfflineTimeout(int seconds) => ERR_UNSUPPORTED;

  /// 子设备命令回调（不支持）。
  int onChildOrder(
          void Function(int device, SysTopic topic, String mid, String data)?
              callback) =>
      ERR_UNSUPPORTED;
}
