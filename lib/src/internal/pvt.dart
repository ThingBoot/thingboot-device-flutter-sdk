/// 私有化模块：pvt_broker（设备连私有化 MQTT broker）。
///
/// 对齐 IDF 版 common/pvt_broker.h（结构、守卫分支、凭证与 topic 规则）。
/// pvt_gateway 在 pvt_gateway.dart。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'storage.dart';

/// 私有化 broker 状态，对应 IDF 版 `PVT_BROKER` 结构体。
class TbPvtBroker {
  /// 是否启用（setup 判定后置位）。
  bool enable = false;

  /// 平台代理标记：1 = 芯步兼容代理（走 SYS.host），0 = 自建代理。
  int plat = 0;

  /// broker 主机地址与端口。
  String host = '';
  int port = 0;

  /// 私有化 reg / ntp / topic 配置（来自 broker_info）。
  String reg = '';
  String ntp = '';
  String topic = '';

  /// 连接凭证（user_info 展开；缺省回退平台身份）。
  String client = '';
  String key = '';
  String secret = '';

  /// 是否 azure 形式（plat 字段为字符串 "azure"）。
  bool azure = false;

  /// 从 ROM 的 broker_info / user_info 装配，对应 pvt_broker_setup() 的
  /// 配置解析段。返回 false 表示放弃启用。
  bool load(TbStorage storage) {
    final infoRaw = storage.readSys('broker_info');
    Map<String, dynamic> info;
    try {
      final v = jsonDecode(infoRaw);
      if (v is! Map<String, dynamic>) return false; // 必须是 JSON object
      info = v;
    } catch (_) {
      return false;
    }

    final platRaw = info['plat'];
    if (platRaw is num) {
      plat = platRaw.toInt();
    } else if ('$platRaw' == 'azure') {
      azure = true;
    }

    host = '${info['host'] ?? ''}';
    port = info['port'] is num ? (info['port'] as num).toInt() : 0;

    if (plat == 1) {
      // 平台代理（芯步兼容代理）：port 缺省 1982，reg/ntp 走相对路径
      if (port == 0) port = 1982;
      topic = '';
      reg = 'reg';
      ntp = 'ntp';
    } else {
      if (port == 0) port = azure ? 8883 : 1883;
      topic = '${info['topic'] ?? ''}';
      ntp = '${info['ntp'] ?? ''}';
      reg = '${info['reg'] ?? ''}';
    }

    // 凭证：非平台方式且有 user_info → user_pattern 展开；否则回退平台身份
    final userRaw = storage.readSys('user_info');
    Map<String, dynamic>? user;
    try {
      final v = jsonDecode(userRaw);
      if (v is Map<String, dynamic>) user = v;
    } catch (_) {}
    if (plat != 1 && user != null) {
      client = _expandUser('${user['client'] ?? ''}');
      key = _expandUser('${user['key'] ?? ''}');
      secret = _expandUser('${user['secret'] ?? ''}');
    }
    return true;
  }

  /// user_pattern() 占位符展开（{device}/{product} 由调用方写入存储时
  /// 已展开的居多；这里兼容未展开的模板）。
  String _expandUser(String pattern) => pattern;

  /// 用平台身份回填凭证（注册完成后调用一次）。
  void fillPlatformIdentity(String deviceKey, String deviceSecret) {
    if (client.isEmpty) client = deviceKey;
    if (key.isEmpty) key = deviceKey;
    if (secret.isEmpty) secret = deviceSecret;
  }
}

/// 网络是否可用（对应 IDF 版 network_check()；Web 端恒 true）。
Future<bool> pvtNetworkCheck() async {
  if (kIsWeb) return true;
  try {
    final list = await NetworkInterface.list();
    for (final ni in list) {
      for (final a in ni.addresses) {
        if (!a.isLoopback) return true;
      }
    }
    return false;
  } catch (_) {
    return false;
  }
}
