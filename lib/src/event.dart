/// 事件管理子模块，对应 Arduino 版 ThingBootSDK/Event.h 与
/// common/core.h 的属性变化事件轮询（带防抖）。
library;

import 'dart:convert';

import 'device.dart';
import 'errors.dart';
import 'types.dart';

/// 属性变化事件槽位，对应 common/globals.h 的 `attribute_event`。
class TbAttributeEvent {
  /// 属性名
  String name = '';

  /// 变化回调
  TbAttributeChangeCallback? callback;

  /// 当前值
  String value = '';

  /// 上次已触发值
  String previous = '';

  /// 防抖期间待确认值
  String pending = '';

  /// 防抖时间（ms），最小 100
  int debounce = 100;

  /// 首次检测到变化的 millis 时间
  int changedAt = 0;

  /// 槽位是否被占用
  bool used = false;
}

/// 事件子模块，通过 `device.event` 访问。
class TbEvent {
  /// 属性事件槽位数（对应 ESP32 下的 ATTRIBUTE_EVENT_MAX = 20）
  static const int attributeEventMax = 20;

  final ThingBootDevice _device;

  /// 属性事件槽位表（SDK 内部轮询使用）。
  final List<TbAttributeEvent> attributes =
      List.generate(attributeEventMax, (_) => TbAttributeEvent());

  TbEvent(this._device);

  static int _clampDebounce(int ms) => ms < 100 ? 100 : ms;

  /// 注册属性变化事件，对应 Arduino 的 `onAttributeChange()`。
  int onAttributeChange(String name, TbAttributeChangeCallback? callback,
      {int debounceMs = 100}) {
    if (name.isEmpty) return ERR_EVENT_NAME_EMPTY;
    if (callback == null) return ERR_EVENT_CALLBACK_NULL;

    final debounce = _clampDebounce(debounceMs);

    // 已存在则更新回调和防抖时间
    for (final e in attributes) {
      if (e.used && e.name == name) {
        e.callback = callback;
        e.debounce = debounce;
        return ERR_OK;
      }
    }

    // 查找空闲槽位
    for (final e in attributes) {
      if (!e.used) {
        e.name = name;
        e.callback = callback;
        e.debounce = debounce;
        e.value = '';
        e.previous = '';
        e.pending = '';
        e.changedAt = 0;
        e.used = true;
        return ERR_OK;
      }
    }

    return ERR_EVENT_NO_SLOT;
  }

  /// 设置属性值，对应 Arduino 的 `setAttribute()`。
  ///
  /// 值变化后经防抖触发 onAttributeChange 注册的回调（由 SDK 周期轮询检测）。
  int setAttribute(String name, String value) {
    if (name.isEmpty) return ERR_EVENT_NAME_EMPTY;

    for (final e in attributes) {
      if (!e.used || e.name != name) continue;
      if (e.value == value) return ERR_OK;
      e.value = value;
      return ERR_OK;
    }

    return ERR_EVENT_NOT_FOUND;
  }

  /// 设置属性变化防抖时间，对应 Arduino 的 `setAttributeDebounce()`。
  int setAttributeDebounce(String name, int debounceMs) {
    if (name.isEmpty) return ERR_EVENT_NAME_EMPTY;

    for (final e in attributes) {
      if (e.used && e.name == name) {
        e.debounce = _clampDebounce(debounceMs);
        return ERR_OK;
      }
    }

    return ERR_EVENT_NOT_FOUND;
  }

  /// 上报事件，对应 Arduino 的 `reportEvent()`：
  /// 消息体为 `{"name":name,"data":<data>}`。
  ///
  /// [data] 传 String 时，若为合法 JSON 对象则按对象内嵌，否则按字符串内嵌；
  /// 也可直接传 `Map<String, dynamic>`。
  bool reportEvent(String name, dynamic data) {
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
    return _device.publish(SysTopic.event, message);
  }
}
