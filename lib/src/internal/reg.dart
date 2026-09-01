/// HTTP 激活与 reg/v4 注册，严格对应 Arduino 版 common/reg.h。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils.dart';

/// 芯步官方平台 API 地址，对应 common/system.h 的 `TB_API_HOST`。
const String kTbApiHost = 'iot-api.unisoft.cn';

/// 注册结果与状态，对应 common/reg.h 的 `REG` 结构体。
class TbReg {
  /// MQTT 服务器地址（注册接口返回）
  String server = '';

  /// MQTT 服务器端口（注册接口返回）
  int port = 0;

  /// MQTT 客户端 ID（注册接口返回，内含时间戳与加密方式分段）
  String client = '';

  /// 是否已注册成功，对应 REG.success
  bool success = false;

  /// 平台要求/失败后的重试延迟秒数，对应 REG.delay
  int delaySec = 0;

  /// 内部 HTTP 请求，对应 common/system.h 的 `http_request()`（15s 超时，重试 1 次）。
  Future<String> _request(String url, {String body = ''}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final uri = Uri.parse(url);
        final http.Response res;
        if (body.isNotEmpty) {
          res = await http
              .post(uri,
                  headers: {'Content-Type': 'application/json'}, body: body)
              .timeout(const Duration(seconds: 15));
        } else {
          res = await http.get(uri).timeout(const Duration(seconds: 15));
        }
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          return res.body;
        }
      } catch (_) {
        // 网络异常按失败处理，进入重试
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    return '';
  }

  /// 设备激活，对应 common/reg.h 的 `reg_active()`。
  ///
  /// 仅在设备凭证缺失（未预烧录/信息丢失）时调用；[mac] 必须使用稳定的
  /// 设备唯一标识。成功返回响应的 data 对象，否则返回 null。
  Future<Map<String, dynamic>?> active({
    required String activeCode,
    required String productKey,
    required String productSecret,
    required String mac,
    required int ts,
  }) async {
    final sign = tbMd5('$activeCode.$productKey.$mac.$productSecret.$ts');
    final url = 'http://$kTbApiHost/active/'
        '?code=$activeCode&product=$productKey&mac=$mac&sign=$sign&ts=$ts';

    final res = await _request(url);
    if (res.isEmpty) return null;

    Map<String, dynamic> ret;
    try {
      final v = jsonDecode(res);
      if (v is! Map<String, dynamic>) return null;
      ret = v;
    } catch (_) {
      return null;
    }

    if (cn(ret['code']) != 200) return null;
    final data = ret['data'];
    return data is Map<String, dynamic> ? data : null;
  }

  /// 平台注册（reg/v4），对应 common/reg.h 的 `reg_request()` 平台分支。
  ///
  /// 成功时填充 [server]/[port]/[client] 并置 [success]，返回响应 data 对象；
  /// 失败时按需设置 [delaySec] 并返回 null。
  Future<Map<String, dynamic>?> request({
    required String host,
    required int port,
    required int bench,
    required String productKey,
    required String productSecret,
    required int deviceId,
    required String deviceKey,
    required String deviceSecret,
    required String mode,
    required String board,
    required String mcu,
    required String firmware,
    required String networkType,
    required bool needTime,
    required int ts,
  }) async {
    success = false;

    var url = 'reg/v4/'
        '?bench=$bench&product=$productKey&device=$deviceId'
        '&key=$deviceKey&secret=$deviceSecret&mode=$mode';

    // 未完成时间同步时顺便请求服务器时间（对应 reg.h 的 `&time`）
    if (needTime) url += '&time';

    final sign = tbMd5(
        '$bench.$productKey.$deviceId.$deviceKey.$deviceSecret.$productSecret.$ts');
    url += '&sign=$sign&ts=$ts';

    // 对应 reg.h 的 payload
    final payload = jsonEncode({
      'board': board,
      'mcu': mcu,
      'firmware': firmware,
      'network_type': networkType,
    });

    final res = await _request('http://$host:$port/$url', body: payload);
    if (res.isEmpty) {
      // 请求失败，60 秒后再次请求
      delaySec = 60;
      return null;
    }

    Map<String, dynamic> ret;
    try {
      final v = jsonDecode(res);
      if (v is! Map<String, dynamic>) return null;
      ret = v;
    } catch (_) {
      return null;
    }

    final data = ret['data'];

    if (cn(ret['code']) != 200) {
      if (data is Map<String, dynamic> && data.containsKey('delay')) {
        delaySec = cn(data['delay']);
      }
      return null;
    }

    if (data is! Map<String, dynamic>) return null;

    server = cs(data['server']);
    this.port = cn(data['port']);
    client = cs(data['client']);

    success = true;
    return data;
  }
}
