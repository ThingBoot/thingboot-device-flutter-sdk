/// ThingBootDevice 主类，对应 Arduino 版 ThingBootSDK.h 的 `ThingBootDevice`
/// 与 common/core.h、common/system.h 的核心调度逻辑。
library;

import 'dart:async';
import 'dart:convert';

import 'bridge.dart';
import 'config.dart';
import 'errors.dart';
import 'event.dart';
import 'gateway.dart';
import 'internal/mqtt.dart';
import 'internal/proto.dart' as proto;
import 'internal/reg.dart';
import 'internal/storage.dart';
import 'message.dart';
import 'network.dart';
import 'order.dart';
import 'peripheral.dart';
import 'state.dart';
import 'timer.dart';
import 'types.dart';
import 'utils.dart';

/// SDK 版本号，对应 ThingBootSDK/Types.h 的 `THINGBOOT_SDK_VERSION`。
const String kThingBootSdkVersion = '0.1.0';

/// 芯步设备主类。
///
/// 用法与 Arduino 版一致：`setProduct` → `onOrder` 等回调注册 → `setup()`。
/// Arduino 的 `loop()` 不需要（Dart 有事件循环），SDK 内部以 Timer 驱动。
class ThingBootDevice {
  // ------------------------------------------------------------------
  // 产品信息（对应 common/system.h 的 PRODUCT）
  // ------------------------------------------------------------------
  String _productKey = '';
  String _productSecret = '';
  String _board = '';
  String _mcu = '';
  String _firmware = '';
  String _activeCode = '';

  // ------------------------------------------------------------------
  // 设备凭证与系统状态（对应 common/decls.h 的 SYS_INFO SYS）
  // ------------------------------------------------------------------
  int _bench = 0;
  int _deviceId = 0;
  String _deviceKey = '';
  String _deviceSecret = '';
  String _timezone = 'CST-8';
  String _host = kTbApiHost;
  int _port = 80;
  String _mode = 'platform'; // 对应 sys_mode()：platform/safe/private/config
  String _pvt = '';
  // 保留字段以对齐 Arduino 的 SYS.exec，当前版本未使用。
  // ignore: unused_field
  String _exec = '';
  int _gatewayId = 0;
  int _masterId = 0;
  String _mac = '';
  SysState _sysState = SysState.idle;

  /// 设备启动以来的单调毫秒（对应 Arduino millis()，32 位回绕）。
  final Stopwatch _uptime = Stopwatch()..start();

  // ------------------------------------------------------------------
  // NTP 状态（对应 common/ntp.h 的 NTP）
  // ------------------------------------------------------------------
  static const int _ntpIntervalSec = 86400;
  int _ntpStandard = 0; // 标准时间（毫秒）
  int _ntpFetch = 0; // 获取时间的 millis
  int _ntpLast = 0; // 上次请求的 millis
  bool _ntpSuccess = false;
  bool _ntpForced = false;

  // ------------------------------------------------------------------
  // 内部模块
  // ------------------------------------------------------------------
  /// 持久化存储（内部使用）。
  final TbStorage storage = TbStorage();

  /// 注册模块（内部使用）。
  final TbReg reg = TbReg();

  /// MQTT 模块（内部使用）。
  final TbMqtt mqtt = TbMqtt();

  bool _subscribed = false;
  int _connectTryTimes = 0;
  Timer? _reconnectTimer;
  Timer? _eventTimer;
  Timer? _stateTimer;

  // ------------------------------------------------------------------
  // 用户回调（对应 common/globals.h 的 tb_g_*_callback）
  // ------------------------------------------------------------------
  /// 命令回调（由 TbOrder.onOrder 设置）。
  TbOrderCallback? orderCallback;

  /// 配置变化回调（由 TbConfig.onConfig 设置）。
  TbConfigCallback? configCallback;

  /// 设备状态获取回调（由 TbState.onFetch 设置）。
  TbFetchCallback? fetchCallback;

  TbSystemStateCallback? _systemStateChangeCallback;
  TbSystemProgressCallback? _systemProgressCallback;
  TbDebugCallback? _debugCallback;

  // ------------------------------------------------------------------
  // 子模块（Arduino 为大写成员，Dart 按惯例小写开头）
  // ------------------------------------------------------------------
  /// 配置管理（对应 Arduino `device.Config`）
  late final TbConfig config = TbConfig(this);

  /// 命令处理（对应 Arduino `device.Order`）
  late final TbOrder order = TbOrder(this);

  /// 事件管理（对应 Arduino `device.Event`）
  late final TbEvent event = TbEvent(this);

  /// 消息通信（对应 Arduino `device.Message`）
  late final TbMessage message = TbMessage(this);

  /// 状态管理（对应 Arduino `device.State`）
  late final TbState state = TbState(this);

  /// 定时器（对应 Arduino `device.Timer`）
  late final TbTimer timer = TbTimer(this);

  /// 外设控制（桩，对应 Arduino `device.Peripheral`）
  late final TbPeripheral peripheral = TbPeripheral(this);

  /// 网络（对应 Arduino `device.Network`）
  late final TbNetwork network = TbNetwork(this);

  /// 网关（桩，对应 Arduino `device.Gateway`）
  late final TbGateway gateway = TbGateway(this);

  /// 桥接（桩，对应 Arduino `device.Bridge`）
  late final TbBridge bridge = TbBridge(this);

  /// 构造函数。
  ThingBootDevice() {
    mqtt.messages.listen(_onMqttMessage);
    mqtt.onDisconnected = _onMqttDisconnected;
  }

  // ==================================================================
  // 系统配置注册表
  // 对应 common/rom.h 的 ROM_SYS（仅保留 Flutter 有意义的系统配置）
  // 配置名 -> [存储键, 系统配置类型]
  // ==================================================================
  static const Map<String, List<String>> _sysConfigs = {
    'pvt': ['pvt', 'mode'],
    'host': ['host', ''],
    'network': ['network_type', 'network'],
    'wifi_ip': ['wifi_ip', 'network'],
    'timezone': ['timezone', ''],
    'gateway_id': ['gateway', ''],
    'master_id': ['master', ''],
    'user': ['user_info', 'mode'],
    'ether_ip': ['ether_ip', 'network'],
    'brand': ['brand_name', ''],
    'wifi': ['wifi', 'network'],
    'gateway': ['gateway_info', 'mode'],
    'broker': ['broker_info', 'mode'],
  };

  /// 查询系统配置名对应的存储键（供 addConfig 冲突检查与 config 下行处理）。
  static String? sysConfigKeyOf(String name) => _sysConfigs[name]?[0];

  // ==================================================================
  // Core 核心接口（对应 ThingBootSDK/Core.h）
  // ==================================================================

  /// 获取 SDK 版本号。
  String getVersion() => kThingBootSdkVersion;

  /// 获取系统信息（JSON 字符串），对应 common/system.h 的 `sys_info()`。
  String getSystemInfo() {
    return jsonEncode({
      'id': _deviceId,
      'key': _deviceKey,
      'secret': _deviceSecret,
      'mode': _mode,
      'pvt': _pvt,
      'bench': _bench,
      'gateway': _gatewayId,
      'master': _masterId,
      'network': network.networkTypeName,
      'timezone': _timezone,
    });
  }

  /// 获取设备 ID。
  int getDeviceID() => _deviceId;

  /// 获取工作台 ID。
  int getBenchID() => _bench;

  /// 设置工作台 ID。
  int setBenchID(int benchID) {
    _sysValue('bench', '$benchID');
    return ERR_OK;
  }

  /// 获取主设备 ID。
  int getMasterID() => _masterId;

  /// 设置主设备 ID。
  int setMasterID(int masterDeviceID) {
    _sysValue('master', '$masterDeviceID');
    return ERR_OK;
  }

  /// 获取网关设备 ID。
  int getGatewayID() => _gatewayId;

  /// 设置网关设备 ID。
  int setGatewayID(int gatewayDeviceID) {
    _sysValue('gateway', '$gatewayDeviceID');
    return ERR_OK;
  }

  /// 获取时区。
  String getTimezone() => _timezone;

  /// 设置时区。
  int setTimezone(String timezone) {
    _sysValue('timezone', timezone);
    return ERR_OK;
  }

  /// 获取当前运行模式：platform / safe / private / config。
  String getMode() => _mode;

  /// 设置运行模式，对应 Arduino 的 `setMode()`。
  int setMode(String mode) {
    if (mode == 'private' || mode == 'pvt') {
      _mode = 'private';
    } else if (mode == 'safe') {
      _mode = 'safe';
    } else if (mode == 'config') {
      _mode = 'config';
    } else {
      _mode = 'platform';
    }

    final romMode =
        _mode == 'private' ? 'pvt' : (_mode == 'platform' ? '' : _mode);
    storage.writeSys('mode', romMode);
    return ERR_OK;
  }

  /// 重启设备（不支持：Flutter 应用无法自重启，仅返回 [ERR_UNSUPPORTED]）。
  int restart([int delayMs = 0]) => ERR_UNSUPPORTED;

  /// 延时指定毫秒数。
  Future<void> delay(int ms) => Future.delayed(Duration(milliseconds: ms));

  /// 设备启动以来的毫秒数（32 位回绕），对应 Arduino `millis()`。
  int millis() => _uptime.elapsedMilliseconds & 0xFFFFFFFF;

  /// 计算从某个 millis() 时间点到当前时刻经过的毫秒数（自动处理溢出），
  /// 对应 ThingBootSDK/Utils.h 的 `mill_elapsed()`。
  int millElapsed(int since) {
    final now = millis();
    return now >= since ? now - since : 0xFFFFFFFF - since + now + 1;
  }

  /// 获取当前时间戳（秒），对应 common/system.h 的 `sys_ts(false)`。
  int getTimestamp() => sysTs() ~/ 1000;

  /// 获取当前时间戳（毫秒），对应 common/system.h 的 `sys_ts()`：
  /// NTP 已同步时用 NTP 标准时间，否则回退本机时间。
  int getTimestampMs() => sysTs();

  /// 获取格式化后的当前时间字符串，支持 %Y %m %d %H %M %S 占位符。
  String getTimeString([String format = '%Y-%m-%d %H:%M:%S']) {
    final t = DateTime.fromMillisecondsSinceEpoch(sysTs());
    String two(int v) => v.toString().padLeft(2, '0');
    return format
        .replaceAll('%Y', t.year.toString().padLeft(4, '0'))
        .replaceAll('%m', two(t.month))
        .replaceAll('%d', two(t.day))
        .replaceAll('%H', two(t.hour))
        .replaceAll('%M', two(t.minute))
        .replaceAll('%S', two(t.second));
  }

  /// 设置产品信息，对应 Arduino 的 `setProduct()`。
  int setProduct(
      String key, String secret, String board, String mcu, String firmware) {
    _productKey = key;
    _productSecret = secret;
    _board = board;
    _mcu = mcu;
    _firmware = firmware;
    return ERR_OK;
  }

  /// 设置设备激活码（用于未预烧录设备时的平台激活）。
  int setActiveCode(String code) {
    if (code.isEmpty) return ERR_SYSTEM_VALUE_NULL;
    _activeCode = code;
    return ERR_OK;
  }

  /// 系统状态变化回调。
  int onSystemStateChange(TbSystemStateCallback? callback) {
    _systemStateChangeCallback = callback;
    return ERR_OK;
  }

  /// 系统初始化进度变化回调。
  int onSystemProgress(TbSystemProgressCallback? callback) {
    _systemProgressCallback = callback;
    return ERR_OK;
  }

  /// 设置调试日志回调，对应 Arduino 的 `onDebug()`。
  int onDebug(TbDebugCallback? callback) {
    _debugCallback = callback;
    return ERR_OK;
  }

  // ==================================================================
  // setup：异步初始化（激活 → 注册 → 连 MQTT → 订阅）
  // 对应 common/core.h 的 core_setup() 与 core_loop() 首轮
  // ==================================================================

  /// 系统初始化。
  ///
  /// 完成后若成功订阅则设备上线（onSystemStateChange 收到 online）；
  /// 失败时 SDK 按退避策略在后台持续重试，无需也不能再调用 Arduino 的 loop()。
  Future<int> setup() async {
    _log('SYS', 'T h i n g B o o t ! (Flutter)');

    _setState(SysState.boot);

    // 对应 common/core.h core_setup() 的 rom_setup()/sys_setup()
    _progress('storage', 0);
    await storage.init();
    await _loadSys();
    _progress('storage', 20);

    // 对应 common/timer.h ticker_setup()：事件轮询 100ms、状态轮询 1s
    _eventTimer?.cancel();
    _eventTimer = Timer.periodic(
        const Duration(milliseconds: 100), (_) => _eventHandle());
    _stateTimer?.cancel();
    _stateTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _stateHandle());

    _setState(SysState.loop);

    // 激活（仅凭证缺失时，对应 common/reg.h reg_active()）
    _progress('active', 40);
    if (_deviceId == 0 || _deviceKey.isEmpty || _deviceSecret.isEmpty) {
      await _active();
    }

    // 注册 + 连接（首轮；失败由重连逻辑接管）
    _progress('network', 60);
    await _ensureConnection();
    _progress('done', 100);

    return ERR_OK;
  }

  /// 释放资源（取消所有周期任务与连接）。
  void dispose() {
    _reconnectTimer?.cancel();
    _eventTimer?.cancel();
    _stateTimer?.cancel();
    mqtt.disconnect();
  }

  // ==================================================================
  // 内部：时间与 mid
  // ==================================================================

  /// 对应 common/system.h 的 `sys_ts()`。
  int sysTs() {
    if (_ntpSuccess && _ntpStandard > 0) {
      return _ntpStandard + millElapsed(_ntpFetch);
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// 生成 mid，对应 common/system.h 的 `sys_mid()`。
  String newMid() => proto.newMid(_deviceId, sysTs());

  // ==================================================================
  // 内部：发布（对应 common/system.h sys_publish() / common/mqtt.h mqtt_publish()）
  // ==================================================================

  /// 发布消息。未订阅成功时直接返回 false（与 Arduino mqtt_publish 一致）。
  bool publish(SysTopic topic, String data, {String? mid, int device = 0}) {
    if (!_subscribed || !mqtt.connected) return false;

    final m = mid ?? newMid();
    final message =
        proto.sysMessage(mid: m, data: data, device: device, ts: sysTs());
    final topicFull =
        proto.mqttTopic(_productKey, _deviceKey, topic, 'client');

    _log('MQTT', 'publish topic:$topicFull');
    _log('MQTT', 'publish message:$message');

    return mqtt.publish(topicFull, message);
  }

  /// 配置变化通知（供 TbConfig 与 config 下行处理调用）。
  void notifyConfigChange(String name, String value) {
    configCallback?.call(name, value);
  }

  // ==================================================================
  // 内部：系统值持久化（对应 common/system.h sys_value()）
  // ==================================================================

  Future<void> _sysValue(String name, String value) async {
    switch (name) {
      case 'bench':
        _bench = cn(value);
        break;
      case 'device':
        _deviceId = cl(value);
        break;
      case 'key':
        _deviceKey = value;
        break;
      case 'secret':
        _deviceSecret = value;
        break;
      case 'timezone':
        _timezone = value;
        break;
      case 'gateway':
        _gatewayId = cl(value);
        break;
      case 'master':
        _masterId = cl(value);
        break;
      case 'host':
        _host = value;
        break;
      case 'pvt':
        _pvt = value;
        break;
    }
    _log('SYS', 'sys value $name:$value');
    await storage.writeSys(name, value);
  }

  /// 对应 common/system.h sys_setup()：从持久化恢复系统状态。
  Future<void> _loadSys() async {
    _bench = cn(storage.readSys('bench'));
    _deviceId = cl(storage.readSys('device'));
    _deviceKey = storage.readSys('key');
    _deviceSecret = storage.readSys('secret');
    _pvt = storage.readSys('pvt');

    // 运行模式（读完后复位，对应 sys_mode()）
    final mode = storage.readSys('mode');
    if (mode == 'pvt') _mode = 'private';
    if (mode == 'safe') _mode = 'safe';
    if (mode == 'config') _mode = 'config';
    await storage.writeSys('mode', '');

    _timezone = storage.readSys('timezone');
    if (_timezone.isEmpty) _timezone = 'CST-8';

    _gatewayId = cn(storage.readSys('gateway'));
    _masterId = cn(storage.readSys('master'));

    // 平台地址与端口（对应 sys_setup() 的 host 解析）
    var host = storage.readSys('host');
    var port = 80;
    if (host.isNotEmpty) {
      final pos = host.indexOf(':');
      if (pos > 0) {
        port = int.tryParse(host.substring(pos + 1)) ?? 80;
        host = host.substring(0, pos);
      }
      _host = host;
      _port = port;
    }

    // 设备唯一标识（对应 Arduino 的 station MAC；Flutter 侧持久化伪 MAC）
    _mac = storage.readSys('mac');
    if (_mac.isEmpty) {
      final r = DateTime.now().microsecondsSinceEpoch;
      _mac =
          '02:${(r & 0xFF).toRadixString(16).padLeft(2, '0')}:${((r >> 8) & 0xFF).toRadixString(16).padLeft(2, '0')}:${((r >> 16) & 0xFF).toRadixString(16).padLeft(2, '0')}:${((r >> 24) & 0xFF).toRadixString(16).padLeft(2, '0')}:${((r >> 32) & 0xFF).toRadixString(16).padLeft(2, '0')}'
              .toUpperCase();
      await storage.writeSys('mac', _mac);
    }
  }

  // ==================================================================
  // 内部：激活 / 注册 / 连接（对应 common/core.h core_loop()）
  // ==================================================================

  /// 对应 common/reg.h reg_active()。
  Future<bool> _active() async {
    if (_deviceId > 0 && _deviceKey.isNotEmpty && _deviceSecret.isNotEmpty) {
      return true;
    }
    if (_activeCode.isEmpty) {
      _log('REG', 'device is not activated and no active code');
      return false;
    }

    final data = await reg.active(
      activeCode: _activeCode,
      productKey: _productKey,
      productSecret: _productSecret,
      mac: _mac,
      ts: millis(),
    );
    if (data == null) return false;

    // 保存品牌信息（对应 reg_active() 的 brand 分支）
    final brand = data['brand'];
    if (brand is Map<String, dynamic>) {
      await storage.writeSys('brand_name', cs(brand['name']));
      await storage.writeSys('brand_pre', cs(brand['pre']));
      await storage.writeSys('brand_debug', cs(brand['debug']));
      await storage.writeSys('brand_psk', cs(brand['psk']));
    }

    // 保存设备基础信息
    await _sysValue('device', cs(data['id']));
    await _sysValue('key', cs(data['key']));
    await _sysValue('secret', cs(data['secret']));

    return true;
  }

  /// 对应 common/reg.h reg_request() 平台分支。
  Future<bool> _regRequest() async {
    if (_deviceId == 0 || _deviceKey.isEmpty) return false;

    final fetch = millis();
    final data = await reg.request(
      host: _host,
      port: _port,
      bench: _bench,
      productKey: _productKey,
      productSecret: _productSecret,
      deviceId: _deviceId,
      deviceKey: _deviceKey,
      deviceSecret: _deviceSecret,
      mode: _mode,
      board: _board,
      mcu: _mcu,
      firmware: _firmware,
      networkType: network.networkTypeName,
      needTime: !_ntpSuccess,
      ts: sysTs(),
    );

    if (data == null) {
      _log('REG', 'reg request failed, delay ${reg.delaySec}s');
      return false;
    }

    // 顺便 NTP（对应 reg_request() 的 ntp_value 调用）
    if (!_ntpSuccess && data.containsKey('time')) {
      _ntpValue(fetch, cs(data['time']), '');
    }

    // 工作台对账
    final bench = cn(data['bench']);
    if (bench > 0) await _sysValue('bench', '$bench');

    // 私有化信息（如有，仅保存不使用）
    if (data['broker'] is Map<String, dynamic>) {
      await storage.writeSys('broker_info', jsonEncode(data['broker']));
    }
    if (data['gateway'] is Map<String, dynamic>) {
      await storage.writeSys('gateway_info', jsonEncode(data['gateway']));
    }
    if (data['user'] is Map<String, dynamic>) {
      await storage.writeSys('user_info', jsonEncode(data['user']));
    }
    if (data['pvt'] is String) {
      await _sysValue('pvt', cs(data['pvt']));
    }

    _log('REG', 'reg client:${reg.client}');
    return true;
  }

  /// 对应 common/mqtt.h mqtt_connect() + mqtt_connect_process() + mqtt_subscribe()。
  Future<bool> _mqttConnect() async {
    final cred = proto.mqttCredentials(
      productKey: _productKey,
      productSecret: _productSecret,
      deviceKey: _deviceKey,
      deviceSecret: _deviceSecret,
      regClient: reg.client,
    );

    // 遗嘱：{"name":"offline"}（对应 mqtt_connect_process() 的 will 设置）
    final willTopic =
        proto.mqttTopic(_productKey, _deviceKey, SysTopic.event, 'client');
    final willMessage = proto.sysMessage(
        mid: newMid(), data: '{"name":"offline"}', ts: sysTs());

    final ok = await mqtt.connect(
      server: reg.server,
      port: reg.port,
      clientId: cred.clientId,
      username: cred.username,
      password: cred.password,
      willTopic: willTopic,
      willMessage: willMessage,
    );
    if (!ok) {
      _log('MQTT', 'connection error');
      return false;
    }

    // 订阅 8 个 server 主题（QoS 1），对应 mqtt_subscribe() 默认分支
    final topics = [
      for (final t in SysTopic.values)
        if (t != SysTopic.unknown)
          proto.mqttTopic(_productKey, _deviceKey, t, 'server'),
    ];

    if (!mqtt.subscribe(topics)) {
      _log('MQTT', 'subscription error');
      mqtt.disconnect();
      return false;
    }

    _subscribed = true;
    _log('MQTT', 'subscribed');
    _goOnline();
    return true;
  }

  /// 对应 common/core.h core_loop() 的连接保障（注册 → MQTT）。
  Future<void> _ensureConnection() async {
    if (_subscribed && mqtt.connected) return;

    _connectTryTimes++;

    // 连续 5 次连接失败，重新注册（对应 mqtt_connect() 的 try_times > 5）
    if (_connectTryTimes > 5) {
      _connectTryTimes = 0;
      reg.success = false;
    }

    if (!reg.success) {
      // 注册前确保已激活
      if (!await _active() || !await _regRequest()) {
        _scheduleReconnect();
        return;
      }
    }

    if (await _mqttConnect()) {
      _connectTryTimes = 0;
    } else {
      _scheduleReconnect();
    }
  }

  /// 断线重连退避：随机 5~60 秒（对应 mqtt_connect() 的 rand_num(5, 60)）。
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delaySec = randNum(5, 60);
    _log('MQTT', 'waiting to connect, delay ${delaySec}s');
    _reconnectTimer =
        Timer(Duration(seconds: delaySec), () => _ensureConnection());
  }

  /// 上线：对应 common/core.h event_handle() 的 SYS_STATE_ONLINE 分支。
  void _goOnline() {
    _setState(SysState.online);

    // 上线即发 online 事件（非安全模式携带全量属性）
    if (_mode == 'safe') {
      publish(SysTopic.event, '{"name":"online"}');
    } else {
      publish(SysTopic.event,
          '{"name":"online","state":${jsonEncode(deviceStates())}}');
    }
  }

  /// 返回设备所有属性的当前值，对应 common/core.h 的 `device_states()`。
  Map<String, dynamic> deviceStates() {
    final states = fetchCallback?.call();
    return states is Map<String, dynamic> ? states : <String, dynamic>{};
  }

  void _setState(SysState state) {
    if (_sysState == state) return;
    final previous = _sysState;
    _sysState = state;
    _systemStateChangeCallback?.call(state, previous);
  }

  void _onMqttDisconnected() {
    if (_subscribed) {
      _subscribed = false;
      _log('MQTT', 'disconnected');
      _setState(SysState.offline);
    }
    _scheduleReconnect();
  }

  // ==================================================================
  // 内部：下行消息分发（对应 common/mqtt.h mqtt_receive_callback()）
  // ==================================================================

  void _onMqttMessage(TbMqttMessage msg) {
    _log('MQTT', 'received message, topic:${msg.topic}, content:${msg.payload}');

    if (strEndsWith(msg.topic, '/order/server')) {
      _handleOrder(msg.payload);
    } else if (strEndsWith(msg.topic, '/config/server')) {
      _handleConfig(msg.payload);
    } else if (strEndsWith(msg.topic, '/ntp/server')) {
      _handleNtp(msg.payload);
    } else if (strEndsWith(msg.topic, '/ota/server')) {
      _handleOta(msg.payload);
    }
  }

  /// 处理命令主题的消息，对应 common/core.h 的 `order()`。
  void _handleOrder(String content) {
    _log('SYS', 'executing order:$content');

    // 完全拦截没有ID的设备
    if (_deviceId == 0) return;

    final message = proto.parseDownlink(content);
    if (message == null) return;

    final mid = cs(message['mid']);
    final data = message['data'];
    final device = cl(message['device']);

    // 对应 common/core.h order_process() 的转发分支：无网关/组网能力，回不支持
    if (device > 0 && device != _deviceId) {
      publish(SysTopic.order, '{"error":"transfer is not support"}', mid: mid);
      return;
    }

    if (data is Map<String, dynamic>) {
      // 系统命令
      if (data.containsKey('system')) {
        _orderSystem(mid, data['system']);
        if (data.length == 1) return;
      }

      // 网关命令（对应 common/core.h order_gateway()，v1 不支持）
      if (data.containsKey('gateway')) {
        publish(SysTopic.order, '{"error":"gateway is not support"}',
            mid: mid);
        if (data.length == 1) return;
      }
    }

    // 产品自有命令
    orderCallback?.call(mid, data);
  }

  /// 应答系统指令，对应 common/core.h 的 `order_system()`。
  void _orderSystem(String mid, dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data.containsKey('exec')) {
        // 设置执行模式
        publish(SysTopic.order, '', mid: mid);
        _exec = cs(data['exec']);
      } else if (data.containsKey('host')) {
        _sysValue('host', cs(data['host']));
        publish(SysTopic.order, '', mid: mid);
        // Arduino 随后 sys_restart()；Flutter 无法自重启，新 host 在下次连接生效
      } else if (data.containsKey('gsm_order')) {
        publish(SysTopic.order, '{"error":"gsm is not support"}', mid: mid);
      } else if (data.containsKey('master')) {
        publish(SysTopic.order, '{"error":"mesh is not support"}', mid: mid);
      } else {
        publish(SysTopic.order, '{"error":"unknow system order"}', mid: mid);
      }
      return;
    }

    final order = cs(data);
    switch (order) {
      case 'info':
        publish(SysTopic.order, getSystemInfo(), mid: mid);
        break;
      case 'network':
        publish(SysTopic.order, network.getNetworkInfo(), mid: mid);
        break;
      case 'restart':
        // 仅应答；Flutter 应用无法自重启
        publish(SysTopic.order, '', mid: mid);
        break;
      case 'state':
        // 对应 core.h 的 state 应答；使用标准 JSON（Arduino 原文为单引号伪 JSON，已弃用）
        publish(SysTopic.order,
            jsonEncode({'state': deviceStates()}),
            mid: mid);
        break;
      case 'ble_start':
      case 'ble_stop':
      case 'ble_reset':
        publish(SysTopic.order, '{"error":"ble is not support"}', mid: mid);
        break;
      case 'wifi_connect':
      case 'wifi_connect_multi':
      case 'wifi_disconnect':
      case 'ether_connect':
      case 'ether_disconnect':
      case 'gsm_connect':
      case 'gsm_disconnect':
        publish(SysTopic.order, '{"error":"network is not support"}',
            mid: mid);
        break;
      case 'mesh_enable':
      case 'mesh_disable':
        publish(SysTopic.order, '{"error":"mesh is not support"}', mid: mid);
        break;
      case 'ntp':
        _ntpForced = true;
        publish(SysTopic.order, '', mid: mid);
        break;
      case 'reg':
        publish(SysTopic.order, '', mid: mid);
        reg.success = false;
        _ensureConnection();
        break;
      case 'private':
        storage.writeSys('mode', 'pvt');
        publish(SysTopic.order, '', mid: mid);
        break;
      case 'platform':
        storage.writeSys('mode', '');
        publish(SysTopic.order, '', mid: mid);
        break;
      default:
        publish(SysTopic.order, '{"error":"unknow system order"}', mid: mid);
    }
  }

  /// 处理配置主题的消息，对应 common/config.h 的 `config()`。
  void _handleConfig(String content) {
    final message = proto.parseDownlink(content);
    if (message == null) return;

    final mid = cs(message['mid']);
    final device = cl(message['device']);

    // 转发（不支持，原样回发，对应 config() 的 device>0 分支）
    if (device > 0) {
      publish(SysTopic.config, cs(message['data']), mid: mid, device: device);
      return;
    }

    _log('CONFIG', 'config:$content');

    final data = message['data'];

    if (data is String) {
      // 旧写法（已弃用，保留兼容）：按名字读配置
      final info = _configTypeRead('', data);
      publish(SysTopic.config, info, mid: mid);
      return;
    }

    if (data is! Map<String, dynamic>) return;

    if (data.containsKey('name')) {
      final name = cs(data['name']);
      if (data.containsKey('info')) {
        // 写入操作
        final ret = _configTypeWrite('', name, cs(data['info']));
        publish(SysTopic.config, '{"ret":"$ret"}', mid: mid);
      } else {
        // 读取操作
        final info = _configTypeRead('', name);
        publish(SysTopic.config, info, mid: mid);
      }
    } else if (data.containsKey('fetch')) {
      // 支持 {"fetch":"device"}
      var type = cs(data['fetch']);
      if (type.isEmpty) type = 'device';
      final configs = _configTypeRead(type, 'fetch');
      publish(SysTopic.config, configs, mid: mid);
    } else {
      // 支持 {"relay1":0,"relay2":0} 这种格式
      final ret = <String, dynamic>{};
      for (final name in data.keys) {
        ret[name] = _configTypeWrite('', name, cs(data[name]));
      }
      publish(SysTopic.config, jsonEncode(ret), mid: mid);
    }
  }

  /// 读配置，对应 common/config.h 的 `config_type_read()`。
  String _configTypeRead(String type, String name) {
    if (name.isEmpty) return '{}';

    final ret = <String, String>{};

    if (type != 'device') {
      // 系统配置（ROM_SYS 中有 name 的项）
      _sysConfigs.forEach((configName, keyType) {
        if (name != configName && name != 'fetch') return;
        if (type.isNotEmpty && keyType[1] != type) return;
        ret[configName] = storage.readSys(keyType[0]);
      });
    }

    if (type == 'device' || type.isEmpty) {
      // 设备配置（addConfig 注册的项）
      for (final item in config.items) {
        if (item.hide) continue;

        if (item.group.isNotEmpty) {
          if (name == 'fetch' || name == item.group) {
            final value = storage.readDevice(item.name);
            ret[item.group] =
                ret.containsKey(item.group) ? '${ret[item.group]},$value' : value;
          }
        } else {
          if (name == 'fetch' || name == item.name) {
            ret[item.name] = storage.readDevice(item.name);
          }
        }
      }
    }

    return jsonEncode(ret);
  }

  /// 写配置，对应 common/config.h 的 `config_type_write()`。
  String _configTypeWrite(String type, String name, String info) {
    if (name.isEmpty) return 'no this config';

    String key = '';
    var isDeviceKey = false;

    if (type != 'device') {
      final keyType = _sysConfigs[name];
      if (keyType != null && (type.isEmpty || keyType[1] == type)) {
        key = keyType[0];
      }
    }

    if (type == 'device' || (type.isEmpty && key.isEmpty)) {
      for (final item in config.items) {
        if (item.name == name) {
          key = item.name;
          isDeviceKey = true;
          break;
        }
      }
    }

    if (key.isEmpty) return 'unknow config';

    // 写入（storage 写入是异步的，这里同步发起，与 Arduino EEPROM.commit 等价语义）
    if (isDeviceKey) {
      storage.writeDevice(key, info);
    } else {
      storage.writeSys(key, info);
    }

    notifyConfigChange(name, info);
    return 'ok';
  }

  /// 处理 NTP 主题的消息，对应 common/ntp.h 的 `ntp()`。
  void _handleNtp(String content) {
    _log('NTP', 'order:$content');

    final message = proto.parseDownlink(content);
    if (message == null) return;

    final data = message['data'];
    if (data is! Map<String, dynamic>) return;

    final fetch = cl(data['fetch']);
    if (fetch == _ntpLast) {
      _ntpValue(fetch, cs(data['stamp']), cs(data['milli']));
    }
  }

  /// NTP 时间计算，对应 common/ntp.h 的 `ntp_value()`。
  void _ntpValue(int fetch, String stamp, String milli) {
    final useTime = millElapsed(fetch) ~/ 2;
    if (useTime > 2500) return;

    var time = stamp;
    if (time.length == 10) {
      // 对应 ntp_value()：毫秒不足 3 位时，在秒数后补 0 再拼接原毫秒串
      var m = milli;
      while (m.length < 3) {
        time += '0';
        m = '${m}0'; // 仅为终止循环计数
      }
      time += milli;
    }

    if (time.length == 13) {
      final standardTime = int.tryParse(time);
      if (standardTime != null && standardTime > 0) {
        _ntpFetch = fetch;
        _ntpStandard = standardTime - useTime;
        _ntpSuccess = true;
        _log('NTP', 'time synchronized');
      }
    }
  }

  /// 处理 OTA 主题的消息，对应 common/mqtt.h 的 `mqtt_ota()`。
  ///
  /// Flutter 侧不支持固件 OTA，仅按协议应答。
  void _handleOta(String content) {
    final message = proto.parseDownlink(content);
    if (message == null) return;

    final mid = cs(message['mid']);
    publish(SysTopic.ota, '', mid: mid);
    _log('OTA', 'ota is not support');
  }

  // ==================================================================
  // 内部：周期任务（对应 common/timer.h ticker_setup() 挂载的处理）
  // ==================================================================

  /// 事件轮询（100ms），对应 common/core.h 的 `event_handle()` 与
  /// `event_common()`（状态变化回调在 _setState 中即时触发，此处处理
  /// NTP 请求与属性防抖）。
  void _eventHandle() {
    // 对应 event_common()：在线时按需发起 NTP 请求
    if (_sysState == SysState.online && _mode != 'safe') {
      final needUpdate =
          !_ntpSuccess || millElapsed(_ntpFetch) > _ntpIntervalSec * 1000;
      final isUpdating = _ntpLast > 0 && millElapsed(_ntpLast) < 60000;

      if ((_ntpForced || (needUpdate && !isUpdating)) && _subscribed) {
        _ntpForced = false;
        _ntpLast = millis();
        // 对应 event_common()：sys_publish(TOPIC_NTP, C(NTP.last))
        publish(SysTopic.ntp, '$_ntpLast');
      }
    }

    // 属性变化事件轮询：带防抖（对应 event_handle() 的 ATTRIBUTE_EVENTS 段）
    for (final e in event.attributes) {
      if (!e.used || e.callback == null) continue;

      // 当前值与已触发值相同：取消待处理变化
      if (e.value == e.previous) {
        e.changedAt = 0;
        e.pending = '';
        continue;
      }

      // 首次检测到变化
      if (e.changedAt == 0) {
        e.changedAt = millis();
        e.pending = e.value;
        continue;
      }

      // 防抖期间值又变了，重置计时
      if (e.value != e.pending) {
        e.changedAt = millis();
        e.pending = e.value;
        continue;
      }

      // 防抖时间到，触发回调
      if (millElapsed(e.changedAt) >= e.debounce) {
        final previous = e.previous;
        e.previous = e.value;
        e.changedAt = 0;
        e.pending = '';
        e.callback!(e.value, previous);
      }
    }
  }

  /// 状态轮询（1s），对应 common/core.h 的 `state_handle()`。
  void _stateHandle() {
    final now = millis();

    for (final s in state.states) {
      if (!s.used || s.callback == null) continue;

      if (millElapsed(s.last) >= s.interval * 1000) {
        s.last = now;
        s.callback!(s.name);
      }
    }
  }

  // ==================================================================
  // 内部：日志与进度
  // ==================================================================

  void _log(String category, String message) {
    _debugCallback?.call(category, message);
  }

  /// 对应 common/system.h 的 `sys_progress()`。
  void _progress(String desc, double progress) {
    _systemProgressCallback?.call(desc, progress);
  }
}
