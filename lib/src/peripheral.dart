/// 外设控制子模块（桩），对应 Arduino 版 ThingBootSDK/Peripheral.h。
///
/// Flutter 应用无 GPIO 能力，所有方法签名照抄 Arduino（参数一致），
/// 方法体返回 [ERR_UNSUPPORTED]。
library;

import 'device.dart';
import 'errors.dart';
import 'types.dart';

/// 按钮事件回调签名，对应 Arduino `setDeviceBtn` 的 callback。
typedef TbBtnCallback = void Function(int num, BtnOper oper, int keep);

/// 外设子模块（桩），通过 `device.peripheral` 访问。
class TbPeripheral {
  // 保留引用以对齐 Arduino 结构，当前版本未使用。
  // ignore: unused_field
  final ThingBootDevice _device;

  TbPeripheral(this._device);

  /// 外设预初始化回调（不支持）。
  int onInitPre(void Function() callback) => ERR_UNSUPPORTED;

  /// 外设初始化回调（不支持）。
  int onInit(void Function() callback) => ERR_UNSUPPORTED;

  /// 配置设备按钮（不支持）。
  int setDeviceBtn(
          int num, int gpioPin, bool triggerLevel, TbBtnCallback callback) =>
      ERR_UNSUPPORTED;

  /// 设定系统按钮（不支持）。
  int setSystemBtn(int num) => ERR_UNSUPPORTED;

  /// 配置设备 LED（不支持）。
  int setDeviceLed(int num, int gpioPin,
          {bool defaultState = false, bool activeLevel = false}) =>
      ERR_UNSUPPORTED;

  /// 设定系统 LED（不支持）。
  int setSystemLed(int num) => ERR_UNSUPPORTED;

  /// 点亮 LED（不支持）。
  int ledOn(int num) => ERR_UNSUPPORTED;

  /// 熄灭 LED（不支持）。
  int ledOff(int num) => ERR_UNSUPPORTED;

  /// 翻转 LED 状态（不支持）。
  int ledToggle(int num, [bool? state]) => ERR_UNSUPPORTED;

  /// LED 闪烁：点亮/熄灭时长（不支持）。
  int ledBlink(int num, int durationMs) => ERR_UNSUPPORTED;

  /// LED 闪烁：闪烁间隔（不支持）。
  int ledBlinkInterval(int num, int intervalMs) => ERR_UNSUPPORTED;

  /// LED 闪烁：闪烁次数，0 表示无限循环（不支持）。
  int ledBlinkTimes(int num, int times) => ERR_UNSUPPORTED;
}
