/// 设备配置管理，对应 Arduino 版 ThingBootSDK/Config.h 与 common/config.h。
library;

import 'dart:async';

import 'device.dart';
import 'errors.dart';
import 'types.dart';

/// 配置存储位置：SDK 托管（免 pos/length），对应 IDF 版的 `TB_CONFIG_AUTO`。
///
/// Flutter 存储为按名键值（shared_preferences / JSON 文件），天然支持自动
/// 分配（与 IDF 的 NVS 后端同级能力）；显式 pos 仅作兼容保留。
const int kTbConfigAuto = 0xFFFF;

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

  /// 配置项注册上限（对应 IDF/Arduino 的 ROM_DEVICE_MAX；Dart 按名 KV 存储
  /// 无 EEPROM 布局约束，2026-10-22 用户定为 256，超出返回
  /// [ERR_CONFIG_MAP_FULL]）。
  static const int kTbConfigMax = 256;

  TbConfig(this._device);

  TbConfigItem? _find(String name) {
    for (final item in _items) {
      if (item.name == name) return item;
    }
    return null;
  }

  /// 添加设备配置项，对应 Arduino 的 `addConfig()`。
  ///
  /// [pos] 缺省为 [kTbConfigAuto]（SDK 托管，免 pos/length，IDF 2026-10-14
  /// 签名语义）；显式 [pos] 取值 0~1999（仅作冲突检查与兼容保留，Dart 存储
  /// 按名键值不依赖位置）。[length] 语义为最大长度，0=默认 64（AUTO 路径）；
  /// 显式 pos 时 length 不可为 0。[hide] 为 true 时 fetch 全部配置时不可见。
  int addConfig(String name,
      {int pos = kTbConfigAuto,
      int length = 0,
      String group = '',
      bool hide = false}) {
    if (name.isEmpty) return ERR_CONFIG_NAME_EMPTY;
    if (pos != kTbConfigAuto) {
      if (pos >= 2000) return ERR_CONFIG_POS_INVALID;
      if (length == 0) return ERR_CONFIG_LENGTH_ZERO;
    }

    // 禁止占用系统键（对应 Arduino 中 rom_sys_item 检查）
    if (ThingBootDevice.sysConfigKeyOf(name) != null) {
      return ERR_CONFIG_NAME_CONFLICT;
    }

    // 已存在则不再重复添加
    if (_find(name) != null) return ERR_OK;

    // 注册表满（对应 Arduino ROM_DEVICE_MAX 上限）
    if (_items.length >= kTbConfigMax) return ERR_CONFIG_MAP_FULL;

    _items.add(TbConfigItem(
        name: name,
        // AUTO 标记原样保留（固定槽位 pos+1000 最大 2999，不会撞）；
        // length 0 按 IDF 语义落为默认最大长度 64
        pos: pos == kTbConfigAuto ? kTbConfigAuto : pos + 1000,
        length: length == 0 ? 64 : length,
        group: group,
        hide: hide));
    return ERR_OK;
  }

  /// 按 name 读取设备配置值，对应 Arduino 的 `readConfig()`。
  ///
  /// 配置未注册 **或值为空串** 时返回 [defaultValue]（IDF 2026-10-15 语义
  /// 统一：存储后端区分不了"从未写"和"写了空串"，统一按"无有效值"处理）。
  String readConfig(String name, [String defaultValue = '']) {
    if (name.isEmpty) return defaultValue;
    if (_find(name) == null) return defaultValue;
    final value = _device.storage.readDevice(name);
    return value.isEmpty ? defaultValue : value;
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
