/// mqtt_client 封装：连接（含遗嘱）、订阅、发布、断线通知。
///
/// 对应 Arduino 版 common/mqtt.h 中围绕 PubSubClient 的逻辑；
/// 断线重连退避由上层（ThingBootDevice）按 mqtt.h 的 `mqtt_connect()` 实现。
library;

import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// 收到的一条下行消息。
class TbMqttMessage {
  /// 完整主题
  final String topic;

  /// 消息内容（UTF-8 字符串）
  final String payload;

  const TbMqttMessage(this.topic, this.payload);
}

/// MQTT 客户端封装。
class TbMqtt {
  MqttServerClient? _client;
  bool _manualDisconnect = false;

  final StreamController<TbMqttMessage> _controller =
      StreamController<TbMqttMessage>.broadcast();

  /// 下行消息流（订阅的所有主题）。
  Stream<TbMqttMessage> get messages => _controller.stream;

  /// 是否已连接。
  bool get connected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  /// 非主动断开时回调（对应 mqtt.h 中连接丢失的检测点）。
  void Function()? onDisconnected;

  /// 连接 MQTT 服务器，对应 common/mqtt.h 的 `mqtt_connect_process()`。
  ///
  /// keepAlive 60s，遗嘱主题为 event/client、QoS 0、不保留（与 Arduino 一致）。
  Future<bool> connect({
    required String server,
    required int port,
    required String clientId,
    required String username,
    required String password,
    required String willTopic,
    required String willMessage,
  }) async {
    disconnect();

    final client = MqttServerClient(server, clientId);
    client.port = port;
    client.keepAlivePeriod = 60; // 对应 mqtt.h setKeepAlive(60)
    client.logging(on: false);
    client.autoReconnect = false; // 重连由上层按退避策略控制
    client.onDisconnected = _handleDisconnected;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(username, password)
        .withWillTopic(willTopic)
        .withWillMessage(willMessage)
        .withWillQos(MqttQos.atMostOnce)
        .startClean();

    _manualDisconnect = false;

    try {
      final status = await client.connect(username, password);
      if (status?.state == MqttConnectionState.connected) {
        _client = client;
        client.updates?.listen(_onData);
        return true;
      }
    } catch (_) {
      // 连接异常按失败处理
    }

    // 主动清理：避免 disconnect 触发 onDisconnected 误报断线
    _manualDisconnect = true;
    client.disconnect();
    return false;
  }

  /// 订阅指定主题（QoS 1），对应 common/mqtt.h 的 `mqtt_subscribe()`。
  ///
  /// 注意 QoS 必须为 1（Arduino 注释：2 会订阅失败）；全部成功才返回 true。
  bool subscribe(List<String> topics) {
    final client = _client;
    if (client == null || !connected) return false;

    var ok = 0;
    for (final topic in topics) {
      if (client.subscribe(topic, MqttQos.atLeastOnce) != null) {
        ok++;
      }
    }
    return ok == topics.length;
  }

  /// 发布消息（QoS 0，与 Arduino PubSubClient 一致），
  /// 对应 common/mqtt.h 的 `mqtt_publish_message()`。
  bool publish(String topic, String message) {
    final client = _client;
    if (client == null || !connected) return false;

    final builder = MqttClientPayloadBuilder()..addString(message);
    client.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);
    return true;
  }

  /// 主动断开连接，对应 common/mqtt.h 的 `mqtt_disconnect()`。
  void disconnect() {
    final client = _client;
    if (client != null) {
      _manualDisconnect = true;
      client.disconnect();
      _client = null;
    }
  }

  void _handleDisconnected() {
    if (_manualDisconnect) return;
    _client = null;
    onDisconnected?.call();
  }

  void _onData(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final message = event.payload;
      if (message is! MqttPublishMessage) continue;
      final payload =
          MqttPublishPayload.bytesToStringAsString(message.payload.message);
      _controller.add(TbMqttMessage(event.topic, payload));
    }
  }
}
