/// 键值持久化，对应 Arduino 版 common/rom.h。
///
/// 默认用 shared_preferences，以 `tb.sys.` / `tb.dev.` 前缀区分系统键
/// （ROM_SYS）与设备配置键（ROM_DEVICE）。
///
/// Windows 例外：shared_preferences 的路径取自 exe 版本信息
/// （%APPDATA%\<CompanyName>\<ProductName>\），软件改名/挪目录都会丢失
/// 凭证并导致平台重新发放设备 ID。因此 Windows 上改用固定路径的 JSON 文件
/// （%LOCALAPPDATA%\ThingBoot\<productKey>\storage.json）——锚定产品 key，
/// 与 exe 目录、名称、版本信息均无关。首次初始化时自动从
/// shared_preferences 迁移既有数据。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// 键值持久化封装。
class TbStorage {
  static const String _sysPrefix = 'tb.sys.';
  static const String _devPrefix = 'tb.dev.';

  /// 产品 key（setProduct 时由 device 注入），Windows 固定路径用。
  String productKey = '';

  SharedPreferences? _prefs;

  /// Windows 文件后端：加载后常驻内存（readSys/readDevice 是同步接口）。
  Map<String, String>? _fileData;
  File? _file;
  Future<void> _writeQueue = Future.value();

  bool get _useFile => !kIsWeb && Platform.isWindows && productKey.isNotEmpty;

  /// 初始化（幂等），须在读写前调用。
  Future<void> init() async {
    if (_prefs != null || _fileData != null) return;
    if (_useFile) {
      final base = Platform.environment['LOCALAPPDATA'];
      if (base != null && base.isNotEmpty) {
        _file = File('$base${Platform.pathSeparator}ThingBoot'
            '${Platform.pathSeparator}$productKey'
            '${Platform.pathSeparator}storage.json');
        Map<String, String> data = {};
        if (await _file!.exists()) {
          try {
            final v = jsonDecode(await _file!.readAsString());
            if (v is Map) {
              data = {for (final e in v.entries) '${e.key}': '${e.value}'};
            }
          } catch (_) {
            // 损坏的文件从空开始
          }
        } else {
          // 迁移：shared_preferences 里的既有数据（tb.* 前缀）并入文件
          final prefs = await SharedPreferences.getInstance();
          for (final key in prefs.getKeys()) {
            if (key.startsWith('tb.')) {
              data[key] = prefs.getString(key) ?? '';
            }
          }
          if (data.isNotEmpty) {
            _fileData = data;
            await _flush();
          }
        }
        _fileData ??= data;
        return;
      }
    }
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 落盘（写操作排队串行执行）。
  Future<void> _flush() async {
    final file = _file;
    final data = _fileData;
    if (file == null || data == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(data));
    } catch (_) {
      // 写盘失败不阻断业务（内存态已更新）
    }
  }

  String _read(String prefixedKey) {
    final data = _fileData;
    if (data != null) return data[prefixedKey] ?? '';
    return _prefs?.getString(prefixedKey) ?? '';
  }

  Future<bool> _write(String prefixedKey, String value) async {
    final data = _fileData;
    if (data != null) {
      data[prefixedKey] = value;
      _writeQueue = _writeQueue.then((_) => _flush());
      return true;
    }
    final prefs = _prefs;
    if (prefs == null) return false;
    return prefs.setString(prefixedKey, value);
  }

  /// 读取系统键，对应 common/rom.h 的 `rom_sys_read()`。
  String readSys(String key) => _read(_sysPrefix + key);

  /// 写入系统键，对应 common/rom.h 的 `rom_sys_write()`。
  Future<bool> writeSys(String key, String value) =>
      _write(_sysPrefix + key, value);

  /// 读取设备配置键，对应 common/rom.h 的 `rom_device_read()`。
  String readDevice(String name) => _read(_devPrefix + name);

  /// 写入设备配置键，对应 common/rom.h 的 `rom_device_write()`。
  Future<bool> writeDevice(String name, String value) =>
      _write(_devPrefix + name, value);
}
