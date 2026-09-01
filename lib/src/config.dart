/// 设备配置管理，对应 Arduino 版 ThingBootSDK/Config.h 与 common/config.h。
library;

import 'dart:async';

import 'device.dart';
import 'errors.dart';
import 'types.dart';

/// 设备配置映射项，对应 common/rom.h 的 `rom_map_device`。
class TbConfigItem {
  /// 名称（同时作为存储键与对外名称）
  final String name;

  /// 存储位置（Arduino 为 pos+1000；Dart 仅作冲突检查与兼容保留）
  final int pos;

  /// 最大长度
  final int length;

  /// 分组名，可为空
  final String group;

  /// 读取全部配置（fetch）时是否隐藏
  final bool hide;

  TbConfigItem({
    required this.name,
    required this.pos,
    required this.length,
    this.group = '',
    this.hide = false,
  });
}

/// 配置管理子模块，通过 `device.config` 访问。
class TbConfig {
  final ThingBootDevice _device;

  final List<TbConfigItem> _items = [];

  /// 已注册的配置项（SDK 内部处理 config 下行时使用）。
  List<TbConfigItem> get items => List.unmodifiable(_items);

  TbConfig(this._device);

  TbConfigItem? _find(String name) {
    for (final item in _items) {
      if (item.name == name) return item;
    }
    return null;
  }

  /// 添加设备配置项，对应 Arduino 的 `addConfig()`。
  ///
  /// [pos] 取值 0~1999；[hide] 为 true 时 fetch 全部配置时不可见。
  int addConfig(String name, int pos, int length,
      {String group = '', bool hide = false}) {
    if (name.isEmpty) return ERR_CONFIG_NAME_EMPTY;
    if (pos >= 2000) return ERR_CONFIG_POS_INVALID;
    if (length == 0) return ERR_CONFIG_LENGTH_ZERO;

    // 禁止占用系统键（对应 Arduino 中 rom_sys_item 检查）
    if (ThingBootDevice.sysConfigKeyOf(name) != null) {
      return ERR_CONFIG_NAME_CONFLICT;
    }

    // 已存在则不再重复添加
    if (_find(name) != null) return ERR_OK;

    _items.add(TbConfigItem(
        name: name, pos: pos + 1000, length: length, group: group, hide: hide));
    return ERR_OK;
  }

  /// 按 name 读取设备配置值，对应 Arduino 的 `readConfig()`。
  ///
  /// name 为空时返回 [defaultValue]。
  String readConfig(String name, [String defaultValue = '']) {
    if (name.isEmpty) return defaultValue;
    if (_find(name) == null) return '';
    return _device.storage.readDevice(name);
  }

  /// 按 name 保存设备配置值，对应 Arduino 的 `saveConfig()`。
  Future<int> saveConfig(String name, String value) async {
    if (name.isEmpty) return ERR_CONFIG_NAME_EMPTY;
    if (_find(name) == null) return ERR_CONFIG_NOT_FOUND;

    if (!await _device.storage.writeDevice(name, value)) {
      return ERR_CONFIG_WRITE_FAILED;
    }

    _device.notifyConfigChange(name, value);
    return ERR_OK;
  }

  /// 清空所有设备配置项的值，对应 Arduino 的 `clearConfig()`。
  Future<int> clearConfig() async {
    for (final item in _items) {
      if (!await _device.storage.writeDevice(item.name, '')) {
        return ERR_CONFIG_WRITE_FAILED;
      }
      _device.notifyConfigChange(item.name, '');
    }
    return ERR_OK;
  }

  /// 清空指定设备配置项的值，对应 Arduino 的 `resetConfig()`。
  Future<int> resetConfig(String name) async {
    if (name.isEmpty) return ERR_CONFIG_NAME_EMPTY;
    if (_find(name) == null) return ERR_CONFIG_NOT_FOUND;

    if (!await _device.storage.writeDevice(name, '')) {
      return ERR_CONFIG_WRITE_FAILED;
    }

    _device.notifyConfigChange(name, '');
    return ERR_OK;
  }

  /// 配置变化回调，对应 Arduino 的 `onConfig()`。
  int onConfig(TbConfigCallback? callback) {
    _device.configCallback = callback;
    return ERR_OK;
  }
}
