/// 云平台代发 HTTP 请求，对应 Arduino 版 ThingBootSDK/Api.h。
library;

import 'dart:convert';

import 'device.dart';
import 'errors.dart';
import 'types.dart';
import 'utils.dart';

/// API 请求结果回调：平台/SDK 错误码、HTTP 状态码、响应数据、消息。
typedef TbApiResponseCallback = void Function(
    int code, int status, dynamic data, String msg);

/// 云代发 API 子模块，通过 `device.api` 访问。
class TbApi {
  final ThingBootDevice _device;
  TbApiResponseCallback? _callback;
  bool _pending = false;
  String _mid = '';
  int _since = 0;
  int _timeout = 0;

  TbApi(this._device);

  /// 发起异步请求；同时只允许一个等待响应或超时的请求。
  int request(
    String method,
    String url, {
    Map<String, dynamic>? headers,
    dynamic body,
    String contentType = 'application/json',
    int timeoutMs = 10000,
  }) {
    if (_pending) return ERR_API_BUSY;
    const methods = {'GET', 'POST', 'PUT', 'PATCH', 'DELETE'};
    if (!methods.contains(method) ||
        (!url.startsWith('http://') && !url.startsWith('https://')) ||
        timeoutMs < 1000 ||
        timeoutMs > 60000) {
      return ERR_API_INVALID;
    }

    final payload = jsonEncode({
      'method': method,
      'url': url,
      'headers': headers ?? <String, dynamic>{},
      'content_type': contentType,
      'body': body ?? <String, dynamic>{},
      'timeout': timeoutMs,
    });
    if (utf8.encode(payload).length > 960) return ERR_API_TOO_LARGE;

    final mid = _device.newMid();
    if (!_device.subscribeApi()) return ERR_API_SUBSCRIBE;
    if (!_device.publish(SysTopic.api, payload, mid: mid)) {
      return ERR_API_PUBLISH;
    }

    _mid = mid;
    _since = _device.millis();
    _timeout = timeoutMs + 5000;
    _pending = true;
    return ERR_OK;
  }

  /// 注册响应回调。
  int onResponse(TbApiResponseCallback? callback) {
    _callback = callback;
    return ERR_OK;
  }

  /// 是否有等待响应或超时处理的请求。
  bool pending() => _pending;

  /// 处理 api/server 下行，仅接受当前 pending 的同 mid 应答。
  void dispatchResponse(String content) {
    if (!_pending) return;
    dynamic message;
    try {
      message = jsonDecode(content);
    } catch (_) {
      return;
    }
    if (message is! Map<String, dynamic> || cs(message['mid']) != _mid) return;
    final response = message['data'];
    if (response is! Map<String, dynamic>) return;

    final code = cn(response['code']);
    final status = cn(response['status']);
    final data = response['data'];
    final msg = cs(response['msg']);
    final callback = _callback;
    _clear();
    callback?.call(code, status, data, msg);
  }

  /// 周期超时检查；设备侧在平台超时基础上多等待 5 秒。
  void tick() {
    if (!_pending || _device.millElapsed(_since) < _timeout) return;
    final callback = _callback;
    _clear();
    callback?.call(ERR_API_TIMEOUT, 0, null, 'timeout');
  }

  void _clear() {
    _pending = false;
    _mid = '';
    _since = 0;
    _timeout = 0;
  }
}
