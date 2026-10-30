/// 网络子模块，对应 Arduino 版 ThingBootSDK/Network.h。
///
/// [getNetworkInfo] 返回当前网络连接信息（可用，异步）；
/// WiFi/以太网/GSM 管理在 Flutter 侧无意义，全部为 [ERR_UNSUPPORTED] 桩。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'device.dart';
import 'errors.dart';
import 'types.dart';

/// 网络变化边沿判定（纯逻辑，对应 IDF 版 core.h 的
/// `network_change_dispatch()`：static 记录上次 (connected, current)，
/// 边沿触发；OFFLINE 传断开前类型，ONLINE/TYPE_CHANGED 传新类型；
/// 开机首次连网触发一次 ONLINE）。
class TbNetworkChangeTracker {
  bool? _connected;
  String _type = 'unknown';

  /// 喂入最新 (connected, type)，返回应触发的事件与应传的 type
  /// （无跳变返回 null）。
  (TbNetworkEvent, String)? update(bool connected, String type) {
    final previousConnected = _connected;
    final previousType = _type;
    _connected = connected;
    if (connected) _type = type;

    // 首次采样：已联网按 ONLINE 触发一次（对应开机首次连网），未联网只记录
    if (previousConnected == null) {
      return connected ? (TbNetworkEvent.online, _type) : null;
    }
    if (connected != previousConnected) {
      // OFFLINE 传断开前类型，ONLINE 传新类型
      return connected
          ? (TbNetworkEvent.online, _type)
          : (TbNetworkEvent.offline, previousType);
    }
    if (connected && type != previousType) {
      return (TbNetworkEvent.typeChanged, _type);
    }
    return null;
  }
}

/// 网络子模块，通过 `device.network` 访问。
class TbNetwork {
  // 保留引用以对齐 Arduino 结构，当前版本未使用。
  // ignore: unused_field
  final ThingBootDevice _device;

  TbNetwork(this._device);

  /// 当前网络类型名（写入 reg payload 的 network_type，对应
  /// common/system.h 的 `sys_network()`）。由 [getNetworkInfo]
  /// 按当前联网网卡探测更新，未知时为 'unknown'。
  String networkTypeName = 'unknown';

  TbNetworkChangeCallback? _changeCallback;
  Timer? _changeTimer;
  final TbNetworkChangeTracker _changeTracker = TbNetworkChangeTracker();

  /// 注册网络变化回调，对应 Arduino 的 `Network.onNetworkChange()`。
  ///
  /// IDF 版在主循环 network_check() 后边沿触发；Flutter 无主循环，以 3 秒
  /// 轮询网卡枚举（dart:io 纯系统调用，不起外部进程）在事件循环上下文触发，
  /// 语义一致：OFFLINE 传断开前类型、ONLINE/TYPE_CHANGED 传新类型、开机
  /// 首次连网触发一次 ONLINE。传 null 注销并停止轮询。
  int onNetworkChange(TbNetworkChangeCallback? callback) {
    _changeCallback = callback;
    _changeTimer?.cancel();
    _changeTimer = null;
    if (callback != null) {
      _pollNetworkChange();
      _changeTimer = Timer.periodic(
          const Duration(seconds: 3), (_) => _pollNetworkChange());
    }
    return ERR_OK;
  }

  /// 轮询网卡枚举做边沿判定（类型取首张有地址的非回退网卡，启发式）。
  Future<void> _pollNetworkChange() async {
    try {
      final list = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLinkLocal: false,
          includeLoopback: false);
      var connected = false;
      var type = 'unknown';
      for (final ni in list) {
        if (ni.addresses.isEmpty) continue;
        connected = true;
        type = _guessType(ni.name);
        break;
      }
      final event = _changeTracker.update(connected, type);
      if (event != null) _changeCallback?.call(event.$1, event.$2);
    } catch (_) {
      // 枚举失败本轮跳过，下轮重试
    }
  }

  /// 停止网络变化轮询（device.dispose 调用）。
  void dispose() {
    _changeTimer?.cancel();
    _changeTimer = null;
  }

  /// addon 安装（不支持）。
  int installEthernet() => ERR_UNSUPPORTED;

  /// addon 安装（不支持）。
  int installGSM() => ERR_UNSUPPORTED;

  /// 获取当前网络信息（JSON 字符串），对应 Arduino 的 `getNetworkInfo()`
  /// 与 common/networks.h 的 `network_info()`。
  ///
  /// 返回格式与 MCU 版一致（仅当前联网方式，不含全部网卡）：
  /// `{"type":"wifi|ether","mac":"..","ip":"..","gateway":"..","mask":"..","dns":".."}`。
  /// 与 MCU 版的差异：channel/signal/ssid/psk（WiFi 专有）在桌面/移动端
  /// 无跨平台 API，不携带；某字段获取失败时按 IDF 惯例省略该字段。
  /// 异步签名：网卡枚举与系统命令查询是异步 API。
  Future<String> getNetworkInfo() async {
    final info = <String, dynamic>{};
    try {
      if (Platform.isWindows) {
        await _collectWindows(info);
      } else if (Platform.isLinux || Platform.isAndroid) {
        await _collectLinux(info);
      } else if (Platform.isMacOS) {
        await _collectMacOS(info);
      }
    } catch (_) {
      // 查询失败时按 unknown 返回
    }
    // 回退：至少给出网卡枚举的 IP
    if (!info.containsKey('ip')) {
      await _collectFallback(info);
    }
    final type = (info['type'] as String?) ?? 'unknown';
    networkTypeName = type;
    return jsonEncode(info..['type'] = type);
  }

  /// Windows：PowerShell Get-NetIPConfiguration 取默认路由网卡的信息
  /// （结构化输出，不受系统显示语言影响）。
  Future<void> _collectWindows(Map<String, dynamic> info) async {
    const ps = 'Get-NetIPConfiguration | Where-Object { \$null -ne '
        r'$_.IPv4DefaultGateway } | Select-Object -First 1 | ForEach-Object {'
        r'[pscustomobject]@{'
        r'ifName = $_.InterfaceAlias;'
        r'ifDesc = $_.NetAdapter.InterfaceDescription;'
        r'mac = $_.NetAdapter.MacAddress;'
        r'ip = $_.IPv4Address.IPAddress;'
        r'prefix = $_.IPv4Address.PrefixLength;'
        r'gateway = $_.IPv4DefaultGateway.NextHop;'
        r'dns = (($c = $_) | ForEach-Object { ($_.DNSServer | Where-Object '
        r'{ $_.AddressFamily -eq 2 }).ServerAddresses }) -join ","'
        '} } | ConvertTo-Json';
    final res = await Process.run('powershell', ['-NoProfile', '-Command', ps]);
    if (res.exitCode != 0) return;
    final v = jsonDecode(res.stdout as String);
    if (v is! Map) return;

    info['type'] = _guessType('${v['ifName']} ${v['ifDesc']}');
    final mac = (v['mac'] as String?) ?? '';
    if (mac.isNotEmpty) info['mac'] = mac.replaceAll('-', ':').toLowerCase();
    // 一张网卡可绑多个 IP，PowerShell 此时返回数组，取第一个
    _putIfNotEmpty(info, 'ip', _firstScalar(v['ip']));
    final prefix = _firstScalar(v['prefix']);
    if (prefix is int) info['mask'] = _prefixToMask(prefix);
    _putIfNotEmpty(info, 'gateway', _firstScalar(v['gateway']));
    _putIfNotEmpty(info, 'dns', _firstScalar(v['dns']));
  }

  /// PowerShell ConvertTo-Json 的字段在单值时是标量、多值时是数组，
  /// 统一取第一个标量。
  static dynamic _firstScalar(dynamic v) {
    if (v is List) return v.isEmpty ? null : v.first;
    return v;
  }

  /// Linux/Android：ip route 取默认路由网卡，ip addr 取地址，
  /// resolv.conf 取 DNS，sysfs 取 MAC。
  Future<void> _collectLinux(Map<String, dynamic> info) async {
    // 默认路由：default via <gw> dev <if>
    final route = await Process.run('ip', ['route', 'show', 'default']);
    if (route.exitCode != 0) return;
    final m = RegExp(r'default via (\S+) dev (\S+)')
        .firstMatch(route.stdout as String);
    if (m == null) return;
    final gateway = m.group(1)!;
    final ifName = m.group(2)!;

    info['type'] = _guessType(ifName);
    _putIfNotEmpty(info, 'gateway', gateway);

    // 地址与前缀：inet <ip>/<prefix>
    final addr = await Process.run('ip', ['-o', 'addr', 'show', 'dev', ifName]);
    if (addr.exitCode == 0) {
      final am = RegExp(r'inet (\S+)/(\d+)').firstMatch(addr.stdout as String);
      if (am != null) {
        info['ip'] = am.group(1);
        info['mask'] = _prefixToMask(int.parse(am.group(2)!));
      }
    }

    // MAC
    final macFile = File('/sys/class/net/$ifName/address');
    if (macFile.existsSync()) {
      _putIfNotEmpty(info, 'mac', macFile.readAsStringSync().trim());
    }

    // DNS
    final resolv = File('/etc/resolv.conf');
    if (resolv.existsSync()) {
      final dns = RegExp(r'^nameserver\s+(\S+)', multiLine: true)
          .allMatches(resolv.readAsStringSync())
          .map((m) => m.group(1)!)
          .join(',');
      _putIfNotEmpty(info, 'dns', dns);
    }
  }

  /// macOS：route get default 取网关与网卡，ifconfig 取地址/MAC，
  /// resolv.conf 取 DNS。
  Future<void> _collectMacOS(Map<String, dynamic> info) async {
    final route = await Process.run('route', ['-n', 'get', 'default']);
    if (route.exitCode != 0) return;
    final text = route.stdout as String;
    final gw = RegExp(r'gateway:\s+(\S+)').firstMatch(text)?.group(1);
    final ifName = RegExp(r'interface:\s+(\S+)').firstMatch(text)?.group(1);
    if (ifName == null) return;

    info['type'] = _guessType(ifName);
    _putIfNotEmpty(info, 'gateway', gw);

    final ifc = await Process.run('ifconfig', [ifName]);
    if (ifc.exitCode == 0) {
      final out = ifc.stdout as String;
      final im = RegExp(r'inet (\S+) netmask (0x[0-9a-fA-F]+)').firstMatch(out);
      if (im != null) {
        info['ip'] = im.group(1);
        info['mask'] = _hexMaskToMask(im.group(2)!);
      }
      final mm = RegExp(r'ether (\S+)').firstMatch(out);
      _putIfNotEmpty(info, 'mac', mm?.group(1));
    }

    final resolv = File('/etc/resolv.conf');
    if (resolv.existsSync()) {
      final dns = RegExp(r'^nameserver\s+(\S+)', multiLine: true)
          .allMatches(resolv.readAsStringSync())
          .map((m) => m.group(1)!)
          .join(',');
      _putIfNotEmpty(info, 'dns', dns);
    }
  }

  /// 回退路径：仅用 dart:io 网卡枚举给出类型与 IP（无网关/掩码/DNS）。
  Future<void> _collectFallback(Map<String, dynamic> info) async {
    try {
      final list = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLinkLocal: false,
          includeLoopback: false);
      for (final ni in list) {
        if (ni.addresses.isEmpty) continue;
        info['type'] ??= _guessType(ni.name);
        info['ip'] = ni.addresses.first.address;
        break;
      }
    } catch (_) {}
  }

  /// 按网卡名/描述启发式判断类型。
  static String _guessType(String name) {
    final n = name.toLowerCase();
    if (n.contains('wifi') ||
        n.contains('wlan') ||
        n.contains('wi-fi') ||
        n.contains('wireless') ||
        n.contains('802.11') ||
        n.contains('无线')) {
      return 'wifi';
    }
    if (n.startsWith('wl')) return 'wifi'; // Linux 无线网卡命名惯例
    if (n.contains('eth') ||
        n.contains('ethernet') ||
        n.contains('以太网') ||
        n.contains('local area') ||
        n.startsWith('en')) {
      // Linux 有线命名 en*/eth*；macOS en0 通常为 WiFi，但无更可靠特征时按有线
      return 'ether';
    }
    if (n.contains('ppp') || n.contains('cellular') || n.contains('wwan')) {
      return 'gsm';
    }
    return 'unknown';
  }

  static void _putIfNotEmpty(
      Map<String, dynamic> info, String key, dynamic value) {
    if (value is String && value.isNotEmpty) info[key] = value;
  }

  /// 前缀长度转点分掩码（如 24 → 255.255.255.0）。
  static String _prefixToMask(int prefix) {
    final v =
        prefix >= 32 ? 0xFFFFFFFF : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    return '${v >> 24 & 0xFF}.${v >> 16 & 0xFF}.${v >> 8 & 0xFF}.${v & 0xFF}';
  }

  /// macOS ifconfig 的十六进制掩码转点分（如 0xffffff00 → 255.255.255.0）。
  static String _hexMaskToMask(String hex) {
    final v = int.tryParse(hex) ?? 0;
    return '${v >> 24 & 0xFF}.${v >> 16 & 0xFF}.${v >> 8 & 0xFF}.${v & 0xFF}';
  }

  /// 连接 WiFi（不支持）。
  int connectWiFi([String? ssid, String? psk]) => ERR_UNSUPPORTED;

  /// 断开 WiFi（不支持）。
  int disconnectWiFi() => ERR_UNSUPPORTED;

  /// 清空 WiFi 配置（不支持）。
  int clearWiFiConfig() => ERR_UNSUPPORTED;

  /// 添加 WiFi 配置（不支持）。
  int addWiFiConfig(String ssid, String psk, [int? pos]) => ERR_UNSUPPORTED;

  /// 更新 WiFi 配置（不支持）。
  int updateWiFiConfig(String ssid, String psk) => ERR_UNSUPPORTED;

  /// 删除 WiFi 配置（不支持）。
  int deleteWiFiConfig(dynamic ssidOrPos) => ERR_UNSUPPORTED;

  /// 获取 WiFi 配置（不支持）。
  int getWiFiConfig() => ERR_UNSUPPORTED;

  /// 设置以太网 SPI 片选引脚和复位引脚（不支持）。
  int setEthernetPin(int cs, [int rst = -1]) => ERR_UNSUPPORTED;

  /// 尝试连接以太网（不支持）。
  int tryConnectEthernet() => ERR_UNSUPPORTED;

  /// 连接以太网（不支持）。
  int connectEthernet() => ERR_UNSUPPORTED;

  /// 断开以太网（不支持）。
  int disconnectEthernet() => ERR_UNSUPPORTED;

  /// 尝试连接 GSM（不支持）。
  int tryConnectGSM() => ERR_UNSUPPORTED;

  /// 连接 GSM（不支持）。
  int connectGSM() => ERR_UNSUPPORTED;

  /// 断开 GSM（不支持）。
  int disconnectGSM() => ERR_UNSUPPORTED;

  /// 设置 GSM 串口（不支持）。
  int setGSMSerialPort(dynamic serial, [int baud = 0]) => ERR_UNSUPPORTED;
}
