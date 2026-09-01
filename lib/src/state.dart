/// 状态管理子模块，对应 Arduino 版 ThingBootSDK/State.h 与
/// common/core.h 的 `state_handle()`。
library;

import 'dart:convert';

import 'device.dart';
import 'errors.dart';
import 'types.dart';

/// 定时状态上报槽位，对应 common/globals.h 的 `state_info`。
class TbStateItem {
  /// 状态名
  String name = '';

  /// 上报间隔（秒）
  int interval = 0;

  /// 上次触发时间（millis 时基）
  int last = 0;

  /// 触发回调
  TbStateReportCallback? callback;

  /// 槽位是否被占用
  bool used = false;
}

/// 状态子模块，通过 `device.state` 访问。
class TbState {
  /// 状态槽位数（对应 ESP32 下的 STATE_MAX = 20）
  static const int stateMax = 20;

  final ThingBootDevice _device;

  /// 状态槽位表（SDK 内部每秒轮询使用）。
  final List<TbStateItem> states =
      List.generate(stateMax, (_) => TbStateItem());

  TbState(this._device);

  /// 注册定时状态上报回调，对应 Arduino 的 `onState()`。
  ///
  /// [interval] 上报间隔，单位秒。
  int onState(String name, int interval, TbStateReportCallback? callback) {
    if (name.isEmpty) return ERR_STATE_NAME_EMPTY;
    if (callback == null) return ERR_STATE_CALLBACK_NULL;
    if (interval == 0) return ERR_STATE_INTERVAL_ZERO;

    // 已存在则更新
    for (final s in states) {
      if (s.used && s.name == name) {
        s.interval = interval;
        s.callback = callback;
        s.last = _device.millis();
        return ERR_OK;
      }
    }

    // 查找空闲槽位
    for (final s in states) {
      if (!s.used) {
        s.name = name;
        s.interval = interval;
        s.callback = callback;
        s.last = _device.millis();
        s.used = true;
        return ERR_OK;
      }
    }

    return ERR_STATE_NO_SLOT;
  }

  /// 立即上报某个状态，对应 Arduino 的 `reportState()`。
  ///
  /// [data] 传 String 时，若为合法 JSON 对象则按对象内嵌，否则按字符串内嵌。
  bool reportState(String name, dynamic data) {
    dynamic payload = data;
    if (data is String) {
      try {
        final parsed = jsonDecode(data);
        if (parsed is Map<String, dynamic>) payload = parsed;
      } catch (_) {
        // 非 JSON，按字符串处理
      }
    }
    final message = jsonEncode({'name': name, 'data': payload});
    return _device.publish(SysTopic.state, message);
  }

  /// 注册设备状态获取回调，对应 Arduino 的 `onFetch()`。
  ///
  /// 设备每次 MQTT 上线后，SDK 通过该回调获取外设当前属性状态并上报平台。
  int onFetch(TbFetchCallback? callback) {
    _device.fetchCallback = callback;
    return ERR_OK;
  }
}
