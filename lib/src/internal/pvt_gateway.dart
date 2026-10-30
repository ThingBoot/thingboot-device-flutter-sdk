/// 私有化网关：HTTP / WebSocket / TCP 单端口服务、LAN 发现与外置网关上行。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../device.dart';
import '../types.dart';
import '../utils.dart';
import 'proto.dart' as proto;

enum _QueueDest { gateway, api, long }

class _ReportItem {
  final SysTopic topic;
  final _QueueDest dest;
  final int generation;
  final String message;
  const _ReportItem(this.topic, this.dest, this.generation, this.message);
}

class _PvtHttpResult {
  final int status;
  final Map<String, dynamic> body;
  const _PvtHttpResult(this.status, this.body);
}

class _PvtLongConnection {
  final int generation;
  final Socket? socket;
  final WebSocket? webSocket;
  final List<int> rx = <int>[];
  bool authenticated = false;
  int lastSeen = 0;
  int lastPing = 0;
  Timer? authTimer;
  Timer? heartbeat;

  _PvtLongConnection(this.generation, {this.socket, this.webSocket});
}

/// 私有化网关状态与服务，对应 IDF 的 PVT_GATEWAY 与长连接状态机。
class TbPvtGateway {
  final ThingBootDevice _device;

  TbPvtGateway(this._device);

  bool enable = false;
  bool signed = false;
  bool external = false;
  int gatewayId = 0;
  String protocol = 'http';
  String ip = '';
  int port = 0;
  String ntp = '';
  bool ntpAuto = false;
  String api = '';
  int clientPort = 80;
  String key = '';
  String secret = '';

  HttpServer? _httpServer;
  ServerSocket? _tcpServer;
  RawDatagramSocket? _discovery;
  int _activeMs = 0;
  int _signTries = 0;
  int _lastSignMs = 0;
  int _lastNtpMs = 0;
  int _httpStatus = -1;
  bool _httpBusy = false;

  final Map<String, Completer<String>> _replyWaiters = {};
  final Queue<_ReportItem> _reportQueue = Queue<_ReportItem>();
  bool _sending = false;
  _ReportItem? _sendingItem;

  _PvtLongConnection? _long;
  bool _wsConnecting = false;
  int _nextGeneration = 0;
  Future<void> _longSerial = Future<void>.value();

  int get boundPort => clientPort;
  int get httpStatus => _httpStatus;
  bool get longConnected => _long?.authenticated ?? false;

  Future<void> setup() async {
    await close();
    _loadUserInfo();
    _loadInfo(applyProtocol: true);
    _resetRegistration();
    await _startServer();
    await _startDiscovery();
    enable = true;
    _device.pvtMarkOnline();
    _device.debug('PVT', 'gateway $protocol mode, listen on $clientPort');
  }

  void _loadUserInfo() {
    clientPort = 80;
    key = '';
    secret = '';
    try {
      final value = jsonDecode(_device.storage.readSys('user_info'));
      if (value is Map<String, dynamic>) {
        clientPort = cn(value['client']) > 0 ? cn(value['client']) : 80;
        key = cs(value['key']);
        secret = cs(value['secret']);
      }
    } catch (_) {}
  }

  void _loadInfo({bool applyProtocol = false}) {
    external = false;
    gatewayId = 0;
    ip = '';
    port = 0;
    api = '';
    ntp = '';
    ntpAuto = false;
    if (applyProtocol) protocol = 'http';

    dynamic value;
    try {
      value = jsonDecode(_device.storage.readSys('gateway_info'));
    } catch (_) {}
    if (value is! Map<String, dynamic>) return;

    external = value.containsKey('ip');
    if (external) {
      gatewayId = cn(value['gateway']);
      ip = cs(value['ip']);
      port = cn(value['port']);
      if (port == 0 && ip.isNotEmpty) port = 80;
    }
    api = cs(value['api']);
    ntp = cs(value['ntp']);
    if (ntp.isEmpty && external && ip.isNotEmpty) {
      ntp = gatewayUrl('ntp');
      ntpAuto = true;
    }
    if (applyProtocol) {
      final configured = cs(value['proto']);
      if (configured == 'ws' || configured == 'tcp') protocol = configured;
    }
  }

  /// 配置即时应用只重载网关/API/NTP；proto 仍在重启后生效。
  void configChanged() {
    if (!enable) return;
    _clearGatewayQueue();
    _loadInfo();
    _resetRegistration();
  }

  Future<void> _startServer() async {
    if (kIsWeb) return;
    for (var candidate = clientPort; candidate < clientPort + 10; candidate++) {
      try {
        if (protocol == 'tcp') {
          final server =
              await ServerSocket.bind(InternetAddress.anyIPv4, candidate);
          server.listen(_acceptTcp);
          _tcpServer = server;
        } else {
          final server =
              await HttpServer.bind(InternetAddress.anyIPv4, candidate);
          if (protocol == 'ws') {
            server.listen(_onWebSocketRequest);
          } else {
            server.listen(_onRequest);
          }
          _httpServer = server;
        }
        clientPort = candidate;
        return;
      } catch (_) {}
    }
    throw StateError('pvt gateway: no free port in $clientPort..');
  }

  Future<void> _startDiscovery() async {
    if (kIsWeb) return;
    try {
      _discovery = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 19820,
          reuseAddress: true);
      _discovery!.broadcastEnabled = true;
      _discovery!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = _discovery!.receive();
        if (packet == null || packet.data.length > 512) return;
        _onDiscover(packet);
      });
    } catch (error) {
      _device.debug('PVT', 'discovery bind failed: $error');
    }
  }

  void _onDiscover(Datagram packet) {
    if (_device.getDeviceID() == 0) return;
    dynamic request;
    try {
      request = jsonDecode(utf8.decode(packet.data));
    } catch (_) {
      return;
    }
    if (request is! Map<String, dynamic> ||
        cs(request['action']) != 'discover' ||
        request['gateway'] is! num ||
        request['port'] is! num) {
      return;
    }
    final requestGateway = cn(request['gateway']);
    final requestPort = cn(request['port']);
    if (requestGateway == 0 || requestPort == 0 || requestPort > 65535) return;
    final body = utf8.encode(jsonEncode({
      'gateway': gatewayId,
      'device': _device.getDeviceID(),
      'port': clientPort,
    }));
    if (body.length <= 512) {
      _discovery?.send(body, packet.address, 19820);
    }
  }

  Future<void> close() async {
    enable = false;
    final long = _long;
    _long = null;
    if (long != null) await _closeLongResources(long);
    await _httpServer?.close(force: true);
    await _tcpServer?.close();
    _httpServer = null;
    _tcpServer = null;
    _discovery?.close();
    _discovery = null;
    _reportQueue.clear();
    _sending = false;
    _sendingItem = null;
    for (final waiter in _replyWaiters.values) {
      if (!waiter.isCompleted) waiter.complete('');
    }
    _replyWaiters.clear();
  }

  // -------------------------------------------------------------------
  // HTTP API
  // -------------------------------------------------------------------

  Future<void> _onRequest(HttpRequest req) async {
    final action =
        req.uri.path.startsWith('/') ? req.uri.path.substring(1) : req.uri.path;
    final source = req.connectionInfo?.remoteAddress.address ?? '';
    switch (action) {
      case '':
        return _text(req, _infoPage());
      case 'order':
      case 'control':
      case 'config':
      case 'ntp':
        final body = await utf8.decoder.bind(req).join();
        final result = await _apiResponse(action, req.uri.query, body, source);
        return _json(req, result);
      case 'notify':
        final body = await utf8.decoder.bind(req).join();
        return _json(req, await _notify(body, req.uri.query, source));
      default:
        return _notFound(req);
    }
  }

  String _infoPage() {
    final info = jsonDecode(_device.getSystemInfo()) as Map<String, dynamic>;
    final brand = _device.storage.readSys('brand_name');
    return 'device id:\t${info['id'] ?? 0}\r\n'
        'device key:\t${info['key'] ?? ''}\r\n'
        'device tag:\t$key\r\n'
        'network type:\t${info['network'] ?? ''}\r\n'
        'gateway ip:\t$ip\r\n'
        'gateway port:\t$port\r\n'
        'gateway linked:\t${signed ? 'yes' : 'no'}\r\n'
        'device brand:\t${brand.isEmpty ? '-' : brand}\r\n';
  }

  String _auth(String params) {
    final sign = getParam(params, 'sign');
    final ts = getParam(params, 'ts');
    if (sign.isEmpty || secret.isEmpty) return 'ok';
    if (ts.isEmpty) return 'missing ts';
    final now = _device.getTimestamp();
    if (now >= 1700000000 && ts != '0') {
      final stamp = int.tryParse(ts);
      if (stamp == null || (now - stamp).abs() > 300) return 'expired';
    }
    return tbMd5('$secret.$ts') == sign ? 'ok' : 'wrong sign';
  }

  Future<Map<String, dynamic>> _apiResponse(
      String action, String params, String body, String source) async {
    if (action == 'config') {
      try {
        final root = jsonDecode(body);
        if (root is Map<String, dynamic> && root.containsKey('gateway_info')) {
          return await _manage(params, root, source);
        }
      } catch (_) {}
    }
    final auth = _auth(params);
    if (auth != 'ok') return _result(500, auth);
    return _apiProcess(action, body);
  }

  Future<Map<String, dynamic>> _apiProcess(String action, String body,
      {void Function(String mid)? onMid}) async {
    if (body.isEmpty) return _result(500, 'empty data');
    if (utf8.encode(body).length > 960) return _result(413, 'too large');
    dynamic data;
    try {
      data = jsonDecode(body);
    } catch (_) {}
    if (data is! Map<String, dynamic>) return _result(500, 'wrong format data');
    if (action == 'config' && data.containsKey('gateway_info')) {
      return _result(400, 'management requires HTTP');
    }

    final mid = _device.newMid();
    onMid?.call(mid);
    final content = proto.sysMessage(mid: mid, data: body, ts: _device.sysTs());
    final completer = Completer<String>();
    _replyWaiters[mid] = completer;
    switch (action) {
      case 'order':
      case 'control':
        _device.dispatchOrder(content);
      case 'config':
        _device.dispatchConfig(content);
      case 'ntp':
        _device.dispatchNtp(content);
    }
    final reply = await completer.future
        .timeout(const Duration(seconds: 3), onTimeout: () => '');
    _replyWaiters.remove(mid);
    dynamic replyData;
    try {
      final value = jsonDecode(reply);
      if (value is Map<String, dynamic>) replyData = value;
    } catch (_) {}
    return {
      'code': 200,
      if (replyData != null) 'data': replyData,
      'msg': replyData != null ? 'ok' : reply
    };
  }

  Map<String, dynamic> _result(int code, String msg, [dynamic data]) => {
        'code': code,
        if (data is Map<String, dynamic>) 'data': data,
        'msg': msg
      };

  Future<Map<String, dynamic>> _manage(
      String params, Map<String, dynamic> root, String source) async {
    final info = root['gateway_info'];
    if (info is! Map<String, dynamic> ||
        info['gateway'] is! num ||
        info['ip'] is! String ||
        info['port'] is! num) {
      return _result(400, 'wrong format data');
    }
    final newGateway = cn(info['gateway']);
    final newIp = cs(info['ip']);
    final newPort = cn(info['port']);
    if (newIp.isEmpty) {
      if (newGateway != 0 || newPort != 0)
        return _result(400, 'wrong format data');
      if (!external || ip.isEmpty || source != ip)
        return _result(500, 'wrong source');
    } else {
      final address = InternetAddress.tryParse(newIp);
      if (newGateway == 0 ||
          newPort == 0 ||
          newPort > 65535 ||
          address == null ||
          address.type != InternetAddressType.IPv4 ||
          newIp == '0.0.0.0' ||
          source != newIp) {
        return _result(400, 'wrong format data');
      }
    }
    if (secret.isNotEmpty && getParam(params, 'sign').isEmpty) {
      return _result(500, 'missing sign');
    }
    final auth = _auth(params);
    if (auth != 'ok') return _result(500, auth);
    return await _storeBinding(newGateway, newIp, newPort)
        ? _result(200, 'ok')
        : _result(500, 'storage_error');
  }

  Future<bool> _storeBinding(int newGateway, String newIp, int newPort) async {
    dynamic current;
    try {
      current = jsonDecode(_device.storage.readSys('gateway_info'));
    } catch (_) {}
    final merged = <String, dynamic>{};
    if (current is Map<String, dynamic>) {
      for (final entry in current.entries) {
        if (entry.key != 'pwd') merged[entry.key] = entry.value;
      }
    }
    merged['gateway'] = newGateway;
    merged['ip'] = newIp;
    merged['port'] = newPort;
    if (!await _device.storage.writeSys('gateway_info', jsonEncode(merged))) {
      return false;
    }
    _clearGatewayQueue();
    _loadInfo();
    _resetRegistration();
    return true;
  }

  Future<Map<String, dynamic>> _notify(
      String body, String params, String source) async {
    dynamic info;
    try {
      info = jsonDecode(body);
    } catch (_) {}
    if (info is! Map<String, dynamic>) return _result(400, 'wrong format data');
    if (secret.isNotEmpty && getParam(params, 'sign').isEmpty) {
      return _result(500, 'missing sign');
    }
    final auth = _auth(params);
    if (auth != 'ok') return _result(500, auth);

    if (external && ip.isNotEmpty) {
      if (source != ip) return _result(500, 'wrong source');
      if (info.containsKey('ip') && cs(info['ip']) != ip) {
        return _result(400, 'wrong format data');
      }
      if (info.containsKey('port')) {
        final newPort = cn(info['port']);
        if (newPort == 0 || newPort > 65535) {
          return _result(400, 'wrong format data');
        }
        dynamic stored;
        try {
          stored = jsonDecode(_device.storage.readSys('gateway_info'));
        } catch (_) {}
        if (stored is! Map<String, dynamic>) stored = <String, dynamic>{};
        stored['port'] = newPort;
        if (!await _device.storage
            .writeSys('gateway_info', jsonEncode(stored))) {
          return _result(500, 'storage_error');
        }
        port = newPort;
      }
      if (ntpAuto || ntp.isEmpty) {
        ntp = gatewayUrl('ntp');
        ntpAuto = true;
      }
    }
    final timestamp = cn(info['ts']);
    if (timestamp > 0) _device.ntpHttpTimestamp(timestamp);
    return _result(200, 'ok');
  }

  // -------------------------------------------------------------------
  // WebSocket / TCP 单长连接
  // -------------------------------------------------------------------

  Future<void> _onWebSocketRequest(HttpRequest req) async {
    if (_long != null || _wsConnecting) {
      req.response.statusCode = 503;
      await req.response.close();
      return;
    }
    _wsConnecting = true;
    try {
      final socket = await WebSocketTransformer.upgrade(req);
      if (_long != null) {
        await socket.close();
        return;
      }
      socket.pingInterval = const Duration(seconds: 30);
      final connection = _acceptLong(webSocket: socket);
      socket.listen(
        (data) {
          if (data is String) {
            _onLongText(connection, data);
          } else {
            _closeLong(connection);
          }
        },
        onDone: () => _closeLong(connection),
        onError: (_) => _closeLong(connection),
      );
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    } finally {
      _wsConnecting = false;
    }
  }

  void _acceptTcp(Socket socket) {
    if (_long != null) {
      socket.destroy();
      return;
    }
    final connection = _acceptLong(socket: socket);
    socket.listen(
      (data) => _onTcpData(connection, data),
      onDone: () => _closeLong(connection),
      onError: (_) => _closeLong(connection),
    );
  }

  _PvtLongConnection _acceptLong({Socket? socket, WebSocket? webSocket}) {
    _nextGeneration = (_nextGeneration + 1) & 0xFFFFFFFF;
    if (_nextGeneration == 0) _nextGeneration = 1;
    final now = _device.millis();
    final connection = _PvtLongConnection(_nextGeneration,
        socket: socket, webSocket: webSocket)
      ..lastSeen = now
      ..lastPing = now;
    _long = connection;
    connection.authTimer = Timer(const Duration(seconds: 5), () {
      if (!connection.authenticated) _closeLong(connection);
    });
    connection.heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_long != connection) return;
      if (_device.millElapsed(connection.lastSeen) > 120000) {
        _closeLong(connection);
        return;
      }
      if (connection.authenticated &&
          connection.webSocket == null &&
          _device.millElapsed(connection.lastPing) > 30000) {
        connection.lastPing = _device.millis();
        if (!_queueLong(connection, {'action': 'ping'})) _closeLong(connection);
      }
    });
    return connection;
  }

  void _onTcpData(_PvtLongConnection connection, List<int> data) {
    if (_long != connection) return;
    connection.rx.addAll(data);
    if (connection.rx.length > 2048) {
      _closeLong(connection);
      return;
    }
    var handled = 0;
    while (handled < 16) {
      final end = connection.rx.indexOf(10);
      if (end < 0) break;
      var length = end;
      if (length > 0 && connection.rx[length - 1] == 13) length--;
      final text =
          utf8.decode(connection.rx.sublist(0, length), allowMalformed: true);
      connection.rx.removeRange(0, end + 1);
      _onLongText(connection, text);
      handled++;
      if (_long != connection) return;
    }
  }

  void _onLongText(_PvtLongConnection connection, String text) {
    if (_long != connection) return;
    connection.lastSeen = _device.millis();
    _longSerial = _longSerial.then((_) => _processLong(connection, text));
  }

  Future<void> _processLong(_PvtLongConnection connection, String text) async {
    if (_long != connection) return;
    dynamic input;
    try {
      input = jsonDecode(text);
    } catch (_) {}
    if (input is! Map<String, dynamic>) {
      await _closeLong(connection);
      return;
    }
    var action = cs(input['action']);
    if (!connection.authenticated) {
      if (action != 'auth' ||
          _auth('sign=${cs(input['sign'])}&ts=${cs(input['ts'])}') != 'ok') {
        await _closeLong(connection);
        return;
      }
      connection.authenticated = true;
      connection.authTimer?.cancel();
      if (!_queueLong(
          connection, {'action': 'auth', 'code': 200, 'msg': 'ok'})) {
        await _closeLong(connection);
      }
      return;
    }
    if (action == 'auth') {
      await _closeLong(connection);
      return;
    }
    if (action == 'ping') {
      if (!_queueLong(connection, {'action': 'pong'}))
        await _closeLong(connection);
      return;
    }
    if (action.isEmpty) action = 'order';
    if (const {'order', 'control', 'config', 'ntp'}.contains(action)) {
      var mid = cs(input['mid']);
      if (!input.containsKey('data')) {
        if (mid.isEmpty) mid = _device.newMid();
        if (!_queueLong(connection, {
          'action': action,
          'mid': mid,
          'code': 400,
          'msg': 'missing data'
        })) {
          await _closeLong(connection);
        }
        return;
      }
      final payload = jsonEncode(input['data']);
      var internalMid = '';
      final result = await _apiProcess(action, payload,
          onMid: (value) => internalMid = value);
      result['action'] = action;
      result['mid'] = mid.isEmpty ? internalMid : mid;
      if (!_queueLong(connection, result)) await _closeLong(connection);
      return;
    }
    if (!_queueLong(
        connection, {'action': action, 'code': 400, 'msg': 'unknown action'})) {
      await _closeLong(connection);
    }
  }

  bool _queueLong(_PvtLongConnection connection, Map<String, dynamic> message) {
    if (_long != connection || !connection.authenticated) return false;
    return _enqueue(_ReportItem(SysTopic.event, _QueueDest.long,
        connection.generation, jsonEncode(message)));
  }

  Future<void> _closeLong(_PvtLongConnection connection) async {
    if (_long != connection) return;
    _long = null;
    await _closeLongResources(connection);
  }

  Future<void> _closeLongResources(_PvtLongConnection connection) async {
    connection.authTimer?.cancel();
    connection.heartbeat?.cancel();
    final socket = connection.socket;
    final webSocket = connection.webSocket;
    if (webSocket != null) {
      await webSocket.close();
    } else {
      socket?.destroy();
    }
    if (_sendingItem?.generation == connection.generation) {
      _sending = false;
      _sendingItem = null;
    }
    final retained = _reportQueue
        .where((item) =>
            item.dest != _QueueDest.long ||
            item.generation != connection.generation)
        .toList();
    _reportQueue
      ..clear()
      ..addAll(retained);
  }

  // -------------------------------------------------------------------
  // 三目的地上行与有界队列
  // -------------------------------------------------------------------

  bool publish(SysTopic topic, String mid, String data, int device) {
    if (utf8.encode(data).length > 960) return false;
    final message = proto.sysMessage(
        mid: mid, data: data, device: device, ts: _device.sysTs());
    final waiter = _replyWaiters.remove(mid);
    if (waiter != null && !waiter.isCompleted) waiter.complete(message);

    var queued = false;
    if (external && ip.isNotEmpty && port > 0) {
      queued = _enqueue(_ReportItem(topic, _QueueDest.gateway, 0, message)) ||
          queued;
    }
    if (api.isNotEmpty) {
      queued =
          _enqueue(_ReportItem(topic, _QueueDest.api, 0, message)) || queued;
    }
    final connection = _long;
    if (topic == SysTopic.event &&
        connection != null &&
        connection.authenticated) {
      dynamic payload;
      try {
        payload = jsonDecode(data);
      } catch (_) {
        payload = data;
      }
      queued = _queueLong(
              connection, {'action': 'event', 'mid': mid, 'data': payload}) ||
          queued;
    }
    return queued;
  }

  bool _enqueue(_ReportItem item) {
    if (_reportQueue.length >= 10) return false;
    _reportQueue.add(item);
    return true;
  }

  void _clearGatewayQueue() {
    final retained =
        _reportQueue.where((item) => item.dest != _QueueDest.gateway).toList();
    _reportQueue
      ..clear()
      ..addAll(retained);
  }

  void process() {
    if (!enable) return;
    _drainQueue();
    if (external && ip.isNotEmpty && port > 0 && !_httpBusy) {
      _signTick();
      _activeTick();
    }
    _ntpTick();
  }

  void _drainQueue() {
    if (_sending || _reportQueue.isEmpty) return;
    final item = _reportQueue.first;
    if (item.dest == _QueueDest.gateway && _httpBusy) return;
    _reportQueue.removeFirst();

    if (item.dest == _QueueDest.long) {
      final connection = _long;
      if (connection == null || connection.generation != item.generation)
        return;
      _sending = true;
      _sendingItem = item;
      try {
        if (connection.webSocket != null) {
          connection.webSocket!.add(item.message);
        } else {
          connection.socket!.add(utf8.encode('${item.message}\n'));
        }
        final flush = connection.socket?.flush() ?? Future<void>.value();
        flush.timeout(const Duration(seconds: 10)).then((_) {
          if (_sendingItem == item) {
            _sending = false;
            _sendingItem = null;
          }
        }).catchError((_) {
          _closeLong(connection);
        });
      } catch (_) {
        _closeLong(connection);
      }
      return;
    }

    final message = '{"device":${_device.getDeviceID()},'
        '"type":"${proto.sysTopicName(item.topic)}","message":${item.message}}';
    if (item.dest == _QueueDest.api) {
      http
          .post(Uri.parse(api),
              headers: {'Content-Type': 'application/json'}, body: message)
          .timeout(const Duration(seconds: 10))
          .catchError((_) => http.Response('', 0));
      return;
    }
    _gatewayPost('report', message).then((result) {
      if (_deviceNotFound(result)) {
        _resetRegistration();
        _signTick(force: true);
      }
    });
  }

  // -------------------------------------------------------------------
  // 外置网关登记、心跳与 NTP
  // -------------------------------------------------------------------

  String _query() {
    if (secret.isEmpty) return '';
    final now = _device.getTimestamp();
    final ts = now >= 1700000000 ? now : 0;
    return '?sign=${tbMd5('$secret.$ts')}&ts=$ts';
  }

  String gatewayUrl(String action) => 'http://$ip:$port/$action';

  Future<_PvtHttpResult> _gatewayPost(String action, String body) async {
    if ((action != 'sign' && !signed) ||
        !external ||
        ip.isEmpty ||
        port == 0 ||
        _httpBusy) {
      return const _PvtHttpResult(-1, {});
    }
    _httpBusy = true;
    _httpStatus = -1;
    try {
      final result =
          await _post('${gatewayUrl('device/$action')}${_query()}', body);
      _httpStatus = result.status;
      if (result.status == 200) _activeMs = _device.millis();
      return result;
    } finally {
      _httpBusy = false;
    }
  }

  Future<_PvtHttpResult> _post(String url, String body) async {
    try {
      final response = await http
          .post(Uri.parse(url),
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 10));
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {}
      return _PvtHttpResult(response.statusCode,
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{});
    } catch (_) {
      return const _PvtHttpResult(-1, {});
    }
  }

  bool _deviceNotFound(_PvtHttpResult result) =>
      result.status == 200 &&
      cn(result.body['code']) == 404 &&
      cs(result.body['msg']) == 'device_not_found';

  void _resetRegistration() {
    signed = false;
    _activeMs = 0;
    _signTries = 0;
    _lastSignMs = 0;
    _httpStatus = -1;
  }

  void _signTick({bool force = false}) {
    if (signed || !external || ip.isEmpty || port == 0 || _httpBusy) return;
    final now = _device.millis();
    if (!force && now < 5000) return;
    if (!force && _lastSignMs > 0) {
      final interval = _signTries <= 3
          ? 5000
          : _signTries <= 10
              ? 60000
              : 300000;
      if (_device.millElapsed(_lastSignMs) < interval) return;
    }
    _lastSignMs = now;
    if (_signTries < 255) _signTries++;
    _gatewayPost(
        'sign',
        jsonEncode({
          'id': _device.getDeviceID(),
          'port': clientPort,
          'mac': _device.getMacAddress(),
        })).then((result) async {
      if (result.status == 200 && cn(result.body['code']) == 200) {
        signed = true;
        _activeMs = _device.millis();
        _device.debug('PVT', 'gateway signed');
      } else if (_deviceNotFound(result)) {
        await _storeBinding(0, '', 0);
      }
    });
  }

  void _activeTick() {
    if (!signed || _device.millElapsed(_activeMs) <= 60000) return;
    _gatewayPost('active', '').then((result) {
      if (result.status == 200 && cn(result.body['code']) == 200) {
        _activeMs = _device.millis();
      } else if (_deviceNotFound(result)) {
        _resetRegistration();
        _signTick(force: true);
      }
    });
  }

  void _ntpTick() {
    if (ntp.isEmpty ||
        (_lastNtpMs > 0 && _device.millElapsed(_lastNtpMs) < 86400000)) {
      return;
    }
    _lastNtpMs = _device.millis();
    final fetch = _device.millis();
    http
        .get(Uri.parse(ntp))
        .timeout(const Duration(seconds: 10))
        .then((response) {
      try {
        final value = jsonDecode(response.body);
        if (value is Map && value['data'] is Map) {
          final data = value['data'] as Map;
          _device.ntpHttpValue(fetch, cs(data['stamp']), cs(data['milli']));
        }
      } catch (_) {}
    }).catchError((_) {});
  }

  // -------------------------------------------------------------------
  // HTTP 响应
  // -------------------------------------------------------------------

  Future<void> _json(HttpRequest req, Map<String, dynamic> result) async {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(result));
    await req.response.close();
  }

  Future<void> _text(HttpRequest req, String body) async {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.text
      ..write(body);
    await req.response.close();
  }

  Future<void> _notFound(HttpRequest req) async {
    req.response
      ..statusCode = 404
      ..headers.contentType = ContentType.text
      ..write('Not found');
    await req.response.close();
  }
}
