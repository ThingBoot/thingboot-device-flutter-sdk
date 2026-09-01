/// 协议纯函数：主题拼接、payload 封装/解析、mid 生成。
///
/// 严格对应 Arduino 版 common/mqtt.h 与 common/system.h，全部无副作用，可单测。
library;

import 'dart:convert';

import '../types.dart';
import '../utils.dart';

/// 主题枚举转主题名，对应 common/system.h 的 `sys_topic()`。
String sysTopicName(SysTopic topic) {
  switch (topic) {
    case SysTopic.order:
      return 'order';
    case SysTopic.event:
      return 'event';
    case SysTopic.state:
      return 'state';
    case SysTopic.config:
      return 'config';
    case SysTopic.ntp:
      return 'ntp';
    case SysTopic.ota:
      return 'ota';
    case SysTopic.api:
      return 'api';
    case SysTopic.debug:
      return 'debug';
    case SysTopic.unknown:
      return '';
  }
}

/// 拼接完整 MQTT 主题（平台模式），对应 common/mqtt.h 的 `mqtt_topic()`：
/// `thing/{PRODUCT.key}/{SYS.key}/{topic}/{side}`。
///
/// [side] 上行固定为 `client`，下行订阅固定为 `server`。
String mqttTopic(
    String productKey, String deviceKey, SysTopic topic, String side) {
  final pre = 'thing/$productKey/$deviceKey';
  final name = sysTopicName(topic);
  if (name.isEmpty) return '$pre/$side';
  return '$pre/$name/$side';
}

/// 封装上行消息，对应 common/system.h 的 `sys_message()`：
/// `{"device":N,"mid":"...","data":<raw>,"ts":1234567890123}`。
///
/// [data] 必须是合法 JSON 片段（原样内嵌，不加引号），为空则省略 data 键；
/// [device] 大于 0 时（子设备消息）附加 device 键；[ts] 为毫秒时间戳。
String sysMessage({
  required String mid,
  String data = '',
  int device = 0,
  required int ts,
}) {
  final b = StringBuffer('{');
  if (device > 0) b.write('"device":$device,');
  b.write('"mid":"$mid"');
  if (data.isNotEmpty) b.write(',"data":$data');
  b.write(',"ts":$ts}');
  return b.toString();
}

/// 生成消息 ID（mid，8 位），对应 common/system.h 的 `sys_mid()`：
/// `md5("${SYS.device}${sys_ts()}", 8)`，md5 居中截 8 位。
String newMid(int deviceId, int ts) => tbMd5('$deviceId$ts', 8);

/// MQTT 连接凭证（平台模式）。
class TbMqttCredentials {
  /// 客户端 ID（注册接口返回的 client 原值）
  final String clientId;

  /// 用户名：{PRODUCT.key}.{SYS.key}.{seps[1]}.{seps[2]}
  final String username;

  /// 密码：md5("{PRODUCT.secret}.{SYS.secret}.{seps[1]}.{seps[2]}")
  final String password;

  const TbMqttCredentials({
    required this.clientId,
    required this.username,
    required this.password,
  });
}

/// 由注册返回的 client 计算 MQTT 连接凭证，
/// 对应 common/mqtt.h 的 `mqtt_connect_process()` 平台分支。
///
/// client 中第 2、3 段（按 `.` 拆分，最多 3 段）携带时间戳与加密方式。
TbMqttCredentials mqttCredentials({
  required String productKey,
  required String productSecret,
  required String deviceKey,
  required String deviceSecret,
  required String regClient,
}) {
  final seps = strSplit(regClient, '.', 3);
  final s1 = seps.length > 1 ? seps[1] : '';
  final s2 = seps.length > 2 ? seps[2] : '';
  return TbMqttCredentials(
    clientId: regClient,
    username: '$productKey.$deviceKey.$s1.$s2',
    password: tbMd5('$productSecret.$deviceSecret.$s1.$s2'),
  );
}

/// 解析下行消息，对应 common/core.h `order()`/`config()` 开头的 `JSON.parse()`。
///
/// 非 JSON 对象时返回 null。
Map<String, dynamic>? parseDownlink(String content) {
  try {
    final v = jsonDecode(content);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}
