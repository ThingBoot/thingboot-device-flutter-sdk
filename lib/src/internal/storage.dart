/// 键值持久化，对应 Arduino 版 common/rom.h。
///
/// Arduino 用 EEPROM 分区存储；Flutter 侧用 shared_preferences，
/// 以 `tb.sys.` / `tb.dev.` 前缀区分系统键（ROM_SYS）与设备配置键（ROM_DEVICE）。
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// 键值持久化封装。
class TbStorage {
  static const String _sysPrefix = 'tb.sys.';
  static const String _devPrefix = 'tb.dev.';

  SharedPreferences? _prefs;

  /// 初始化（幂等），须在读写前调用。
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 读取系统键，对应 common/rom.h 的 `rom_sys_read()`。
  String readSys(String key) {
    return _prefs?.getString(_sysPrefix + key) ?? '';
  }

  /// 写入系统键，对应 common/rom.h 的 `rom_sys_write()`。
  Future<bool> writeSys(String key, String value) async {
    final prefs = _prefs;
    if (prefs == null) return false;
    return prefs.setString(_sysPrefix + key, value);
  }

  /// 读取设备配置键，对应 common/rom.h 的 `rom_device_read()`。
  String readDevice(String name) {
    return _prefs?.getString(_devPrefix + name) ?? '';
  }

  /// 写入设备配置键，对应 common/rom.h 的 `rom_device_write()`。
  Future<bool> writeDevice(String name, String value) async {
    final prefs = _prefs;
    if (prefs == null) return false;
    return prefs.setString(_devPrefix + name, value);
  }
}
