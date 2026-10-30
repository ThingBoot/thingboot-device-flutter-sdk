/// ThingBootDevice 主类，对应 Arduino 版 ThingBootSDK.h 的 `ThingBootDevice`
/// 与 common/core.h、common/system.h 的核心调度逻辑。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform, Process;

import 'api.dart';
import 'bridge.dart';
import 'config.dart';
import 'errors.dart';
import 'event.dart';
import 'gateway.dart';
import 'internal/mqtt.dart';
import 'internal/proto.dart' as proto;
import 'internal/pvt.dart';
import 'internal/pvt_gateway.dart';
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

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

/// SDK 类型与版本号，对应 ThingBootSDK/Types.h 的名称和版本宏。
const String kThingBootSdkName = 'flutter';
const String kThingBootSdkVersion = '0.3.0';
const String kThingBootSdk = '$kThingBootSdkName $kThingBootSdkVersion';

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

  /// OTA 平台事件串（reg 响应的 ota 配置提供），对应 IDF 版 OTA.order_begin/failure。
  String _otaOrderBegin = '';
  String _otaOrderFailure = '';

  /// OTA 升级回调（应用层实现下载/安装/重启）。
  TbOtaCallback? _otaCallback;

  /// OTA 类型化回调（对应 IDF 2026-09-27 onOTA）：data 带 type 时透传。
  TbOtaTypeCallback? _otaTypeCallback;

  /// 私有化 broker 状态（pvt=="broker" 且守卫通过时启用）。
  final TbPvtBroker pvtBroker = TbPvtBroker();

  /// 私有化网关服务（pvt=="gateway" 且守卫通过时启用）。
  late final TbPvtGateway pvtGateway = TbPvtGateway(this);
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

  /// 设备启动时刻（millis 时基），setup() 时记录。
  int _startedMs = 0;

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
  bool _apiSubscribed = false;
  final TbMqttRateLimiter _mqttRate = TbMqttRateLimiter();
  int _connectTryTimes = 0;
  bool _connecting = false;
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

  /// 调试主题上行剩余秒数，0 为关闭，最大 3600。
  int _debugRemaining = 0;

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

  /// 云平台代发 HTTP（对应 Arduino `device.Api`）
  late final TbApi api = TbApi(this);

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
  ///
  /// `pvt` 字段仅在私有化模式下输出（IDF 2026-10-16：非私有化设备不再
  /// 携带恒为空串的 pvt 键，读取方须按"键可能不存在"处理）。
  String getSystemInfo() {
    final info = <String, dynamic>{
      'id': _deviceId,
      'key': _deviceKey,
      'secret': _deviceSecret,
      'mode': _mode,
    };
    if (_mode == 'private') info['pvt'] = _pvt;
    info.addAll({
      'bench': _bench,
      'gateway': _gatewayId,
      'master': _masterId,
      'network': network.networkTypeName,
      'timezone': _timezone,
      'sdk': kThingBootSdk,
    });
    return jsonEncode(info);
  }

  /// 获取设备 ID。
  int getDeviceID() => _deviceId;

  /// 获取设备 key（平台注册发放；未注册为空串）。
  String getDeviceKey() => _deviceKey;

  /// 获取设备唯一标识（MAC；私有化网关登记用）。
  String getMacAddress() => _mac;

  /// 设备启动时刻（millis 时基；私有化网关登记节拍用）。
  int get startedMs => _startedMs;

  /// 私有化 gateway 注入本机命令（对应 core.h 的 order() 直接调用）。
  void dispatchOrder(String content) => _handleOrder(content);

  /// 私有化 gateway 注入配置（对应 config() 直接调用）。
  void dispatchConfig(String content) => _handleConfig(content);

  /// 私有化 gateway 注入对时（对应 ntp() 直接调用）。
  void dispatchNtp(String content) => _handleNtp(content);

  /// 私有化 gateway 上线标记（TCP 服务就绪即在线，对应 SYS_STATE_ONLINE）。
  void pvtMarkOnline() => _goOnline();

  /// 私有化 gateway 的 HTTP 对时写回（对应 ntp_value()）。
  void ntpHttpValue(int fetch, String stamp, String milli) =>
      _ntpValue(fetch, stamp, milli);

  /// notify 提供的秒级标准时间；Flutter 不修改操作系统时钟。
  void ntpHttpTimestamp(int seconds) {
    if (seconds <= 0) return;
    _ntpStandard = seconds * 1000;
    _ntpFetch = millis();
    _ntpSuccess = true;
  }

  /// 供内部模块（pvt gateway 等）写调试日志。
  void debug(String category, String message) => _log(category, message);

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
    // Windows 下凭证存储锚定产品 key 的固定路径（与 exe 目录/元数据无关）
    storage.productKey = key;
    return ERR_OK;
  }

  /// 设置设备激活码（用于未预烧录设备时的平台激活）。
  /// 对应 IDF 版 Core.cpp：接受空字符串（清空激活码），截断到 16 字符。
  int setActiveCode(String code) {
    _activeCode = code.length > 16 ? code.substring(0, 16) : code;
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

  /// 当前调试模式与剩余秒数，由系统命令 `system.debug` 设置。
  bool get debugMode => _debugRemaining > 0;
  int get debugRemaining => _debugRemaining;

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
    _startedMs = millis();

    _setState(SysState.boot);

    // 对应 common/core.h core_setup() 的 rom_setup()/sys_setup()
    _progress('storage', 0);
    await storage.init();
    await _loadSys();
    _progress('storage', 20);

    // 私有化装配（对应 core_setup() 的 pvt_gateway_setup/pvt_broker_setup）
    await _pvtGatewaySetup();
    await _pvtBrokerSetup();

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
    network.dispose();
    mqtt.disconnect();
    pvtGateway.close();
  }

  /// 应用从后台恢复前台时调用：取消重连退避并立即重建连接。
  ///
  /// 移动端 OS 挂起后 TCP 常为半开状态（本地仍显示已连接、broker 已按
  /// 遗嘱判定离线），故恢复时不信任既有连接状态，已连接也直接重建；
  /// 断线等待退避中的场景则跳过等待立即连。gateway 模式无平台连接，忽略。
  Future<void> resume() async {
    if (pvtGateway.enable) return;
    _reconnectTimer?.cancel();
    if (_subscribed) {
      _subscribed = false;
      mqtt.disconnect();
    }
    await _ensureConnection();
  }

  // ==================================================================
  // 内部：私有化 broker 装配（对应 common/pvt_broker.h pvt_broker_setup()）
  // ==================================================================

  /// pvt gateway setup（对应 pvt_gateway_setup() 守卫分支）：
  /// 守卫通过时装配并启动 TCP 服务；无 gateway_info 也工作在网关模式
  /// （纯 TCP 被控，仅 sign/report 不跑）。
  Future<void> _pvtGatewaySetup() async {
    if (_pvt != 'gateway') return;
    // 安全模式/配置模式不进私有化（对应 SYS_MODE_SAFE/ap_config 分支）
    if (_mode == 'safe' || _mode == 'config') return;
    // 强制私有化但未联网 → 回退平台（对应 SYS_MODE_PVT 未联网分支）
    if (_mode == 'private' && !await pvtNetworkCheck()) {
      _mode = '';
      return;
    }
    await pvtGateway.setup();
    _mode = 'private';
    _log('SYS', 'enter pvt gateway mode');
  }

  /// pvt broker setup：守卫分支与 IDF 对齐；启用后 mode 标记为 private，
  /// plat==1 时重置系统级 HTTP 服务器地址为 broker 地址。
  Future<void> _pvtBrokerSetup() async {
    if (_pvt != 'broker') return;
    // 安全模式/配置模式不进私有化（对应 SYS_MODE_SAFE/ap_config 分支）
    if (_mode == 'safe' || _mode == 'config') return;
    // 强制私有化但未联网 → 回退平台（对应 SYS_MODE_PVT 未联网分支；
    // Flutter 无工程模式，engineering 分支不适用）
    if (_mode == 'private' && !await pvtNetworkCheck()) {
      _mode = '';
      return;
    }
    if (!pvtBroker.load(storage)) return;

    _mode = 'private';
    pvtBroker.enable = true;
    // 芯步兼容代理：系统级 HTTP 服务器指向 broker（reg/ntp 走它）
    if (pvtBroker.plat == 1) {
      _host = pvtBroker.host;
      _port = pvtBroker.port;
    }
    _log('SYS', 'enter pvt broker mode: ${pvtBroker.host}:${pvtBroker.port}');
  }

  /// 主题拼接（含私有化前缀矩阵），对应 mqtt_topic()。
  String _topicOf(SysTopic topic, String side) {
    return proto.mqttTopic(_productKey, _deviceKey, topic, side,
        pvtTopic: pvtBroker.enable ? pvtBroker.topic : '',
        pvtClient: pvtBroker.client,
        pvtKey: pvtBroker.key,
        azure: pvtBroker.enable && pvtBroker.azure);
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
  /// gateway 模式分流到 pvtGateway.publish（同步应答捕获 + 上报队列）。
  bool publish(SysTopic topic, String data, {String? mid, int device = 0}) {
    // debug 主题上行门控（对应 IDF 2026-10-09 core_publish）：SYS.debug 关闭
    // 时直接丢弃返回 false；不影响本地 onDebug 调试回调
    if (topic == SysTopic.debug && _debugRemaining == 0) return false;

    final m = mid ?? newMid();
    if (pvtGateway.enable) {
      return pvtGateway.publish(topic, m, data, device);
    }
    if (!_subscribed || !mqtt.connected) return false;
    if (!_mqttRate.allow(topic, millis())) {
      _log('MQTT', 'publish rate limited: ${topic.name}');
      return false;
    }

    final message =
        proto.sysMessage(mid: m, data: data, device: device, ts: sysTs());
    final topicFull = _topicOf(topic, 'client');

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

    // 设备唯一标识（对应 Arduino 的 station MAC）。
    // 优先从硬件稳定特征派生（卸载重装/升级/重装系统 ID 不变；计费依赖 ID
    // 唯一），派生只执行一次并写存档，之后永远读存档（老存档原样保留）。
    // 全路径失败时回退持久化随机伪 MAC（历史行为）。
    _mac = storage.readSys('mac');
    if (_mac.isEmpty) {
      final derived = await _deriveStableMac();
      if (derived != null) {
        _mac = derived;
      } else {
        _mac = _randomMac();
        _log('SYS', 'derive mac seed source=random_fallback mac=$_mac');
      }
      await storage.writeSys('mac', _mac);
    }
  }

  /// 由硬件稳定特征派生伪 MAC（02: 前缀，本地管理地址）；
  /// 仅首次写存档时调用，全路径失败返回 null（调用方回退随机）。
  ///
  /// 种子来源逐级兜底，每级命中/失败均经 `_log` 可观测：
  /// - Android：ANDROID_ID（`android_id`）
  /// - iOS：identifierForVendor（`ios_idfv`）
  /// - Windows：BIOS 序列号 → 主板序列号（`bios_serial`）→ CPU ProcessorId
  ///   （`cpu_id`）→ PCI 内置网卡 MAC（`pci_nic`），全部经 PowerShell 读取
  /// - macOS：IOPlatformUUID（`io_uuid`）
  /// - Linux：DMI product_uuid（`dmi_uuid`）→ /etc/machine-id（`machine_id`）
  /// - 桌面端最终兜底：联网网卡真实 MAC（`nic_mac`，历史行为）
  Future<String?> _deriveStableMac() async {
    if (Platform.isAndroid) {
      // ANDROID_ID：同签名重装不变（恢复出厂才变）
      try {
        return _seedMac(
            'android_id', (await DeviceInfoPlugin().androidInfo).id);
      } catch (e) {
        _log('SYS', 'derive mac android_id failed: $e');
        return null;
      }
    }
    if (Platform.isIOS) {
      // identifierForVendor：同开发商应用重装不变
      try {
        return _seedMac(
            'ios_idfv', (await DeviceInfoPlugin().iosInfo).identifierForVendor);
      } catch (e) {
        _log('SYS', 'derive mac ios_idfv failed: $e');
        return null;
      }
    }
    // 桌面端：硬件级种子兜底链（固件级，重装操作系统不变）
    if (Platform.isWindows) {
      final bios = await _psValue('(Get-CimInstance Win32_BIOS).SerialNumber');
      if (_seedUsable(bios)) return _seedMac('bios_serial', bios);
      final board =
          await _psValue('(Get-CimInstance Win32_BaseBoard).SerialNumber');
      if (_seedUsable(board)) return _seedMac('bios_serial', board);
      final cpu =
          await _psValue('(Get-CimInstance Win32_Processor).ProcessorId');
      if (_seedUsable(cpu)) return _seedMac('cpu_id', cpu);
      // 板载网卡 MAC：PCI 前缀=内置，排除 ROOT\ 虚拟与 USB\ 扩展坞
      final nic = await _psValue('Get-CimInstance Win32_NetworkAdapter | '
          'Where-Object { \$_.PNPDeviceID -like \'PCI*\' -and \$_.MACAddress } | '
          'Sort-Object MACAddress | Select-Object -First 1 -ExpandProperty MACAddress');
      if (_seedUsable(nic)) return _seedMac('pci_nic', nic);
    } else if (Platform.isMacOS) {
      // 固件 UUID
      final out =
          await _runOut('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
      final seed = out == null
          ? null
          : RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"')
              .firstMatch(out)
              ?.group(1);
      if (_seedUsable(seed)) return _seedMac('io_uuid', seed);
    } else if (Platform.isLinux) {
      // DMI 硬件 UUID（新内核限 root），失败兜底 machine-id
      final dmi = await _readTextFile('/sys/class/dmi/id/product_uuid');
      if (_seedUsable(dmi)) return _seedMac('dmi_uuid', dmi);
      final mid = await _readTextFile('/etc/machine-id');
      if (_seedUsable(mid)) return _seedMac('machine_id', mid);
    }
    // 最终兜底：当前联网网卡的真实 MAC（与 IDF 的 station MAC 对齐，历史行为）
    try {
      final info = jsonDecode(await network.getNetworkInfo());
      final seed = info is Map ? info['mac'] as String? : null;
      if (_seedUsable(seed)) return _seedMac('nic_mac', seed);
    } catch (e) {
      _log('SYS', 'derive mac nic_mac failed: $e');
    }
    return null;
  }

  /// 种子是否可用：过滤空值与厂商占位符（如 "To Be Filled By O.E.M."）。
  bool _seedUsable(String? seed) {
    if (seed == null) return false;
    const placeholders = [
      'to be filled by o.e.m.',
      'default string',
      'not specified',
      'system serial number',
      'none',
      '0',
    ];
    return !placeholders.contains(seed.trim().toLowerCase());
  }

  /// 由命中种子派生伪 MAC（同种子同结果），并记录命中来源。
  String _seedMac(String source, String? seed) {
    final hex = tbMd5('thingboot.${seed!.trim()}');
    final mac = '02:${hex.substring(0, 2)}:${hex.substring(2, 4)}:'
            '${hex.substring(4, 6)}:${hex.substring(6, 8)}:${hex.substring(8, 10)}'
        .toUpperCase();
    _log('SYS', 'derive mac seed source=$source mac=$mac');
    return mac;
  }

  /// 调 PowerShell 取单行值，失败或为空返回 null。
  Future<String?> _psValue(String command) async {
    final out =
        await _runOut('powershell', ['-NoProfile', '-Command', command]);
    if (out == null) return null;
    final line = out.trim().split('\n').first.trim();
    return line.isEmpty ? null : line;
  }

  /// 运行外部进程取 stdout，超时/失败返回 null。
  Future<String?> _runOut(String exe, List<String> args) async {
    try {
      final r =
          await Process.run(exe, args).timeout(const Duration(seconds: 10));
      if (r.exitCode != 0) return null;
      return r.stdout as String;
    } catch (e) {
      _log('SYS', 'derive mac run $exe failed: $e');
      return null;
    }
  }

  /// 读文本文件内容（去首尾空白），失败返回 null。
  Future<String?> _readTextFile(String path) async {
    try {
      return (await File(path).readAsString()).trim();
    } catch (_) {
      return null;
    }
  }

  /// 持久化随机伪 MAC（无硬件特征时的兜底，历史行为）。
  String _randomMac() {
    final r = DateTime.now().microsecondsSinceEpoch;
    return '02:${(r & 0xFF).toRadixString(16).padLeft(2, '0')}:${((r >> 8) & 0xFF).toRadixString(16).padLeft(2, '0')}:${((r >> 16) & 0xFF).toRadixString(16).padLeft(2, '0')}:${((r >> 24) & 0xFF).toRadixString(16).padLeft(2, '0')}:${((r >> 32) & 0xFF).toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  // ==================================================================
  // 内部：激活 / 注册 / 连接（对应 common/core.h core_loop()）
  // ==================================================================

  /// 对应 common/reg.h reg_active()。
  ///
  /// 激活码允许为空：免费产品由平台直接发放设备 ID（对应 IDF 版
  /// reg_active() 不检查 tb_g_active_code 是否为空）。
  Future<bool> _active() async {
    if (_deviceId > 0 && _deviceKey.isNotEmpty && _deviceSecret.isNotEmpty) {
      return true;
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
    final newId = cn(data['id']);
    final idChanged = newId > 0 && newId != _deviceId;
    await _sysValue('device', cs(data['id']));
    await _sysValue('key', cs(data['key']));
    await _sysValue('secret', cs(data['secret']));

    // master 键多态（对应 reg.h，同 _regRequest 分支）：
    // 数字 = 主设备 ID（0=解绑）；数组 = mesh 从设备列表（Flutter 清残留）
    final master = data['master'];
    if (master is num) {
      _masterId = master.toInt();
      await _sysValue('master', '$_masterId');
    } else if (master is List) {
      _masterId = 0;
      await _sysValue('master', '0');
    }

    // 对应 reg_active() 的 ID 变化重启分支：Flutter 无法自重启，
    // 仅记录日志；新凭证已在内存与存储中生效，后续注册用新 ID
    if (idChanged) {
      _log('REG', 'device id changed to $newId (restart required on MCU)');
    }

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
      sdk: kThingBootSdk,
      networkType: network.networkTypeName,
      needTime: !_ntpSuccess,
      ts: sysTs(),
    );

    if (data == null) {
      _log('REG', 'reg request failed, delay ${reg.delaySec}s');
      return false;
    }

    _mqttRate.configure(data['rate']);

    // 顺便 NTP（对应 reg_request() 的 ntp_value 调用）
    if (!_ntpSuccess && data.containsKey('time')) {
      _ntpValue(fetch, cs(data['time']), '');
    }

    // 工作台对账
    final bench = cn(data['bench']);
    if (bench > 0) await _sysValue('bench', '$bench');

    // master 键多态（对应 reg.h）：数字 = 本设备的主设备 ID（0=解绑）；
    // 数组 = mesh 从设备列表（仅 mesh 平台需要，Flutter 清残留绑定即可）
    final master = data['master'];
    if (master is num) {
      _masterId = master.toInt();
      await _sysValue('master', '$_masterId');
    } else if (master is List) {
      _masterId = 0;
      await _sysValue('master', '0');
    }

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
    // OTA 平台事件串（对应 IDF 版 reg.h 的 OTA.order_begin/failure）；
    // 显式忽略带 type 的条目（防平台误发代码包配置导致意外装包）
    if (data['ota'] is Map<String, dynamic> &&
        !(data['ota'] as Map).containsKey('type')) {
      final ota = data['ota'] as Map<String, dynamic>;
      _otaOrderBegin = cs(ota['begin']);
      _otaOrderFailure = cs(ota['failure']);
    }

    _log('REG', 'reg client:${reg.client}');
    return true;
  }

  /// 私有化注册（pvt broker 模式），对应 common/reg.h reg_request() 的
  /// 私有化分支：URL 基为 broker_info.reg；签名**不含** productSecret；
  /// 不携带 payload。
  Future<bool> _regRequestPvt() async {
    final ts = sysTs();
    final fetch = millis();
    // url_build 对参数值统一 URL 编码（IDF 2026-10-20）
    var url = urlBuild('${pvtBroker.reg}/', {
      'bench': _bench,
      'product': _productKey,
      'device': _deviceId,
      'key': _deviceKey,
      'secret': _deviceSecret,
      'mode': _mode,
    });
    if (!_ntpSuccess) url += '&time';
    final sign =
        tbMd5('$_bench.$_productKey.$_deviceId.$_deviceKey.$_deviceSecret.$ts');
    url = urlBuild(url, {'sign': sign, 'ts': ts});

    final res =
        await reg.requestPvt(host: _host, port: _port, url: url, ts: ts);
    if (res == null) return false;

    _mqttRate.configure(res['rate']);
    if (!_ntpSuccess && res.containsKey('time')) {
      _ntpValue(fetch, cs(res['time']), '');
    }
    final bench = cn(res['bench']);
    if (bench > 0) await _sysValue('bench', '$bench');

    // 私有化注册响应可二次改写 broker 连接参数（对应 reg.h 263-281）
    if (cn(res['plat']) == 1) pvtBroker.plat = 1;
    final host = cs(res['host']);
    if (host.isNotEmpty) pvtBroker.host = host;
    final port = cn(res['port']);
    if (port > 0) pvtBroker.port = port;
    final topic = cs(res['topic']);
    if (topic.isNotEmpty) pvtBroker.topic = topic;
    if (res['user'] is Map<String, dynamic>) {
      final user = res['user'] as Map<String, dynamic>;
      pvtBroker.client = cs(user['client']);
      pvtBroker.key = cs(user['key']);
      pvtBroker.secret = cs(user['secret']);
    }

    _log('REG', 'pvt reg ok');
    return true;
  }

  /// 对应 common/mqtt.h mqtt_connect() + mqtt_connect_process() + mqtt_subscribe()。
  Future<bool> _mqttConnect() async {
    // 凭证与地址：broker 模式用私有化参数，平台模式用 reg 参数
    // （对应 mqtt.h 的 PVT_BROKER.enable 分支）
    String server, clientId, username, password;
    int port;
    if (pvtBroker.enable) {
      server = pvtBroker.host;
      port = pvtBroker.port;
      clientId = pvtBroker.client;
      username = pvtBroker.key;
      password = pvtBroker.secret;
    } else {
      final cred = proto.mqttCredentials(
        productKey: _productKey,
        productSecret: _productSecret,
        deviceKey: _deviceKey,
        deviceSecret: _deviceSecret,
        regClient: reg.client,
      );
      server = reg.server;
      port = reg.port;
      clientId = cred.clientId;
      username = cred.username;
      password = cred.password;
    }

    // 遗嘱：{"name":"offline"}（对应 mqtt_connect_process() 的 will 设置）
    final willTopic = _topicOf(SysTopic.event, 'client');
    final willMessage = proto.sysMessage(
        mid: newMid(), data: '{"name":"offline"}', ts: sysTs());

    final ok = await mqtt.connect(
      server: server,
      port: port,
      clientId: clientId,
      username: username,
      password: password,
      willTopic: willTopic,
      willMessage: willMessage,
    );
    if (!ok) {
      _log('MQTT', 'connection error');
      return false;
    }

    // 启动只订阅四个必需主题；api/server 在首次 API 请求前按需订阅。
    _apiSubscribed = false;
    final List<String> topics;
    if (pvtBroker.enable && pvtBroker.azure) {
      topics = [_topicOf(SysTopic.unknown, 'server')];
    } else {
      topics = [
        for (final t in const [
          SysTopic.order,
          SysTopic.config,
          SysTopic.ntp,
          SysTopic.ota
        ])
          _topicOf(t, 'server'),
      ];
    }

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

  /// API 请求前按需订阅 api/server，重连后允许重新订阅。
  bool subscribeApi() {
    if (_apiSubscribed) return true;
    if (!_subscribed || !mqtt.connected) return false;
    if (!mqtt.subscribe([_topicOf(SysTopic.api, 'server')])) return false;
    _apiSubscribed = true;
    return true;
  }

  /// 对应 common/core.h core_loop() 的连接保障（注册 → MQTT）。
  /// gateway 模式完全跳过 reg/mqtt（对应 core_loop 的 PVT_GATEWAY 分支）。
  Future<void> _ensureConnection() async {
    if (pvtGateway.enable) return;
    if (_subscribed && mqtt.connected) return;
    if (_connecting) return; // 防重入（退避定时器与 resume() 并发）
    _connecting = true;
    try {
      _connectTryTimes++;

      // 连续 5 次连接失败，重新注册（对应 mqtt_connect() 的 try_times > 5）
      if (_connectTryTimes > 5) {
        _connectTryTimes = 0;
        reg.success = false;
      }

      if (!reg.success) {
        // broker 模式且未配置私有化 reg 地址：免注册直连
        // （对应 reg_check() 的 PVT_BROKER.enable && reg 为空分支）
        if (pvtBroker.enable && pvtBroker.reg.isEmpty) {
          pvtBroker.fillPlatformIdentity(_deviceKey, _deviceSecret);
          reg.success = true;
        } else if (pvtBroker.enable) {
          // 私有化注册
          if (!await _active() || !await _regRequestPvt()) {
            _scheduleReconnect();
            return;
          }
        } else {
          // 注册前确保已激活
          if (!await _active() || !await _regRequest()) {
            _scheduleReconnect();
            return;
          }
        }
      }

      if (await _mqttConnect()) {
        _connectTryTimes = 0;
      } else {
        _scheduleReconnect();
      }
    } finally {
      _connecting = false;
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
    _apiSubscribed = false;
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
    _log(
        'MQTT', 'received message, topic:${msg.topic}, content:${msg.payload}');

    if (strEndsWith(msg.topic, '/order/server')) {
      _handleOrder(msg.payload);
    } else if (strEndsWith(msg.topic, '/config/server')) {
      _handleConfig(msg.payload);
    } else if (strEndsWith(msg.topic, '/ntp/server')) {
      _handleNtp(msg.payload);
    } else if (strEndsWith(msg.topic, '/ota/server')) {
      _handleOta(msg.payload);
    } else if (strEndsWith(msg.topic, '/api/server')) {
      api.dispatchResponse(msg.payload);
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
    var data = message['data'];
    final device = cl(message['device']);

    // 兼容云平台直发未包 data 的下行（如 {"screen":{...},"mid":...}）：
    // 去掉信封键后，其余键作为命令体。IDF 版对无 data 的消息同样失败，
    // 这里做宽松处理（比 IDF 更宽容，不破坏已有行为）。
    if (data == null) {
      final rest = Map<String, dynamic>.from(message)
        ..remove('mid')
        ..remove('ts')
        ..remove('device');
      if (rest.isNotEmpty) data = rest;
    }

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
        publish(SysTopic.order, '{"error":"gateway is not support"}', mid: mid);
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
      } else if (data.containsKey('debug')) {
        // true=3600 秒；数值作为剩余秒数，上限 3600，不应答。
        final v = data['debug'];
        _debugRemaining = v is bool ? (v ? 3600 : 0) : cn(v).clamp(0, 3600);
      } else if (data.containsKey('master')) {
        publish(SysTopic.order, '{"error":"mesh is not support"}', mid: mid);
      } else if (data.containsKey('bench')) {
        // 产品层命令（设置工作台 = 带新 bench 重新 reg）：转发应用层回调
        if (orderCallback != null) {
          orderCallback!(mid, {'system': data});
        } else {
          publish(SysTopic.order, '{"error":"unknow system order"}', mid: mid);
        }
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
        // getNetworkInfo 为异步（网卡枚举是异步 API），完成后应答
        network
            .getNetworkInfo()
            .then((info) => publish(SysTopic.order, info, mid: mid));
        break;
      case 'restart':
        // 桌面/移动应用可自行实现重启：有应用层回调则转发，否则仅应答
        if (orderCallback != null) {
          orderCallback!(mid, {'system': 'restart'});
        } else {
          publish(SysTopic.order, '', mid: mid);
        }
        break;
      case 'state':
        // 对应 core.h 的 state 应答；使用标准 JSON（Arduino 原文为单引号伪 JSON，已弃用）
        publish(SysTopic.order, jsonEncode({'state': deviceStates()}),
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
        publish(SysTopic.order, '{"error":"network is not support"}', mid: mid);
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

    // 本机配置必须落本地；Flutter 无子设备传输层，其他目标不支持转发。
    if (device > 0 && device != _deviceId) {
      publish(SysTopic.config, '{"error":"transfer is not support"}', mid: mid);
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

    // 批量读（对应 IDF 2026-10-01）：data 为数组 ["relay1","relay2"] 时
    // 逐项读并合并应答；单项不存在时该项不出现在应答中
    if (data is List) {
      final merged = <String, dynamic>{};
      for (final item in data) {
        final name = cs(item);
        if (name.isEmpty) continue;
        try {
          final m = jsonDecode(_configTypeRead('', name));
          if (m is Map<String, dynamic>) merged.addAll(m);
        } catch (_) {}
      }
      publish(SysTopic.config, jsonEncode(merged), mid: mid);
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
            ret[item.group] = ret.containsKey(item.group)
                ? '${ret[item.group]},$value'
                : value;
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
      if (key == 'gateway_info') pvtGateway.configChanged();
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

  /// 注册 OTA 升级回调（应用层实现下载/安装/重启）。
  int onOta(TbOtaCallback? callback) {
    _otaCallback = callback;
    return ERR_OK;
  }

  /// 注册 OTA 类型化回调（对应 IDF 2026-09-27 `onOTA`）：OTA 命令带
  /// `type` 时透传（type, 完整 content）；固件路径（无 type 或
  /// type=="firmware"）仍走 [onOta] 既有逻辑，回调仅作通知。
  int onOTA(TbOtaTypeCallback? callback) {
    _otaTypeCallback = callback;
    return ERR_OK;
  }

  /// OTA 包下载地址，对应 IDF 版 ota_begin() 的签名 URL 组包。
  /// [name] 为固件/包名；sign = md5(deviceKey.productSecret.name.ts)。
  /// 参数值统一 URL 编码（IDF 2026-10-20）。
  String otaDownloadUrl(String name) {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sign = tbMd5('$_deviceKey.$_productSecret.$name.$ts');
    return urlBuild('http://$_host/ota/', {
      'key': _deviceKey,
      'name': name,
      'sign': sign,
      'ts': ts,
    });
  }

  /// OTA 结果上报（对应 IDF 版的 `ota/status/` HTTP 回调）。
  /// [message] 成功为 "ok"，失败为错误描述。
  /// 参数值统一 URL 编码（空格为 `%20`，IDF 2026-10-20 起由 `+` 改为标准编码）。
  Future<void> otaStatus(String name, String message) async {
    try {
      await http
          .get(Uri.parse(urlBuild('http://$_host/ota/status/', {
            'device': _deviceId,
            'name': name,
            'message': message,
          })))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // 上报失败不阻断流程
    }
  }

  /// OTA 失败事件（对应 IDF 版 ota_order(OTA.order_failure)）。
  void otaFailure() => _otaOrder(_otaOrderFailure);

  /// 对应 IDF 版 ota_order()：把平台事件串包装为 order 上行消息。
  void _otaOrder(String data) {
    if (data.isEmpty) return;
    publish(SysTopic.order, data);
  }

  /// 处理 OTA 主题的消息，对应 common/mqtt.h 的 `mqtt_ota()`。
  ///
  /// 流程：应答 → 上报 begin 事件 → 回调应用层执行升级。
  /// 应用层未注册回调时按不支持处理（保持原桩行为）。
  void _handleOta(String content) {
    final message = proto.parseDownlink(content);
    if (message == null) return;

    final mid = cs(message['mid']);
    publish(SysTopic.ota, '', mid: mid);

    final data = message['data'];

    // type 分支（对应 IDF 2026-09-27）：代码包等非固件升级只应答 +
    // 透传完整 content 给产品侧回调（不断连/不预检/不重启，产品自定）；
    // 未注册回调时丢弃。type=="firmware" 走固件路径并额外通知。
    if (data is Map<String, dynamic> && data['type'] is String) {
      final type = cs(data['type']);
      if (type != 'firmware') {
        final cb = _otaTypeCallback;
        if (cb == null) {
          _log('OTA', 'typed ota dropped (no onOTA): $type');
          return;
        }
        _log('OTA', 'typed ota: $type');
        cb(type, content);
        return;
      }
      _otaTypeCallback?.call(type, content);
    }

    final name = data is Map<String, dynamic> ? cs(data['name']) : '';
    final cb = _otaCallback;
    if (cb == null || name.isEmpty) {
      _log('OTA', 'ota is not support');
      return;
    }

    _log('OTA', 'begin:$name');
    _otaOrder(_otaOrderBegin);
    cb(name);
  }

  // ==================================================================
  // 内部：周期任务（对应 common/timer.h ticker_setup() 挂载的处理）
  // ==================================================================

  /// 事件轮询（100ms），对应 common/core.h 的 `event_handle()` 与
  /// `event_common()`（状态变化回调在 _setState 中即时触发，此处处理
  /// NTP 请求与属性防抖）。
  void _eventHandle() {
    api.tick();
    // gateway 模式：主流程分流到 pvtGateway（sign/active/report/ntp），
    // 不走 MQTT 的 event_common（对应 core_loop 的 PVT_GATEWAY 分支）
    if (pvtGateway.enable) {
      pvtGateway.process();
      return;
    }
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
    if (_debugRemaining > 0) _debugRemaining--;

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
