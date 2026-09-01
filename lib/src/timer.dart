/// 用户定时器子模块，对应 Arduino 版 ThingBootSDK/Timer.h。
///
/// Arduino 每个定时器独占一个 Ticker；Dart 侧用 `Timer.periodic` 实现。
library;

import 'dart:async';

import 'device.dart';
import 'errors.dart';
import 'types.dart';

class _TbUserTimer {
  int interval = 0; // 运行间隔（ms）
  int count = 0; // 0=无限循环，>0=剩余次数
  TbTimerCallback? callback;
  Timer? timer;
  bool used = false;
}

/// 定时器子模块，通过 `device.timer` 访问。
class TbTimer {
  /// 定时器槽位数（对应 ESP32 下的 USER_TIMER_MAX = 20）
  static const int userTimerMax = 20;

  // 保留引用以对齐 Arduino 结构，当前版本未使用。
  // ignore: unused_field
  final ThingBootDevice _device;

  final List<_TbUserTimer> _timers =
      List.generate(userTimerMax, (_) => _TbUserTimer());

  TbTimer(this._device);

  /// 注册用户定时器，对应 Arduino 的 `addTimer()`。
  ///
  /// [intervalMs] 运行间隔（毫秒）；[count] 为 0 时无限循环，大于 0 时
  /// 执行指定次数后自动停止。
  int addTimer(int intervalMs, TbTimerCallback? callback, {int count = 0}) {
    if (intervalMs == 0) return ERR_TIMER_INTERVAL_ZERO;
    if (callback == null) return ERR_TIMER_CALLBACK_NULL;

    for (final t in _timers) {
      if (t.used) continue;

      t.interval = intervalMs;
      t.count = count;
      t.callback = callback;
      t.used = true;

      // 复用槽位时先取消旧的 Timer
      t.timer?.cancel();
      t.timer = Timer.periodic(
          Duration(milliseconds: intervalMs), (_) => _tick(t));

      return ERR_OK;
    }

    return ERR_TIMER_NO_SLOT;
  }

  /// 对应 Arduino Timer.cpp 的 `user_timer_tick()`。
  void _tick(_TbUserTimer t) {
    if (!t.used || t.callback == null) return;

    t.callback!();

    if (t.count > 0) {
      t.count--;
      if (t.count == 0) {
        // 次数耗尽，释放槽位
        t.used = false;
        t.callback = null;
        t.timer?.cancel();
        t.timer = null;
      }
    }
  }
}
