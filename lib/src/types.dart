/// 公共枚举与结构体，对应 Arduino 版 ThingBootSDK/Enums.h、ThingBootSDK/Types.h。
library;

/// 系统消息主题，对应 ThingBootSDK/Enums.h 的 `SYS_TOPIC`。
enum SysTopic {
  /// 未知主题（对应 TOPIC_UNKNOWN）
  unknown,

  /// 命令（对应 TOPIC_ORDER）
  order,

  /// 事件（对应 TOPIC_EVENT）
  event,

  /// 状态（对应 TOPIC_STATE）
  state,

  /// 配置（对应 TOPIC_CONFIG）
  config,

  /// 时间同步（对应 TOPIC_NTP）
  ntp,

  /// 固件升级（对应 TOPIC_OTA）
  ota,

  /// 开放平台 API（对应 TOPIC_API）
  api,

  /// 调试（对应 TOPIC_DEBUG）
  debug,
}

/// 系统状态，对应 ThingBootSDK/Enums.h 的 `SYS_STATE`。
enum SysState {
  /// 系统空闲，不上报状态（对应 SYS_STATE_IDLE）
  idle,

  /// 启动（对应 SYS_STATE_BOOT）
  boot,

  /// 进入主循环（对应 SYS_STATE_LOOP）
  loop,

  /// 在线（对应 SYS_STATE_ONLINE）
  online,

  /// 离线（对应 SYS_STATE_OFFLINE）
  offline,
}

/// 按钮操作，对应 ThingBootSDK/Enums.h 的 `BTN_OPER`。
enum BtnOper {
  /// 空闲（对应 BTN_IDLE）
  idle,

  /// 按下（对应 BTN_DOWN）
  down,

  /// 抬起（对应 BTN_UP）
  up,
}

/// 命令回调：首参为消息 ID（mid），第二参为命令数据（对应 Arduino 的 JSONVar，
/// 在 Dart 侧为 `Map<String, dynamic>`、`String` 等 JSON 解析结果）。
typedef TbOrderCallback = void Function(String mid, dynamic data);

/// 配置变化回调：(配置名, 新值)。
typedef TbConfigCallback = void Function(String name, String value);

/// 系统状态变化回调：(当前状态, 之前状态)。
typedef TbSystemStateCallback = void Function(
    SysState current, SysState previous);

/// 系统初始化进度回调：(阶段描述, 进度百分比)。
typedef TbSystemProgressCallback = void Function(String desc, double progress);

/// 调试日志回调：(分类, 内容)，对应 Arduino 的 `onDebug`。
typedef TbDebugCallback = void Function(String category, String message);

/// 设备状态获取回调：设备每次 MQTT 上线后由 SDK 调用，返回全部属性当前值，
/// 对应 Arduino `onFetch`（返回 JSONVar，Dart 侧为 Map）。
typedef TbFetchCallback = Map<String, dynamic> Function();

/// 定时状态上报回调：(状态名)。
typedef TbStateReportCallback = void Function(String name);

/// 属性变化回调：(当前值, 之前值)。
typedef TbAttributeChangeCallback = void Function(
    String current, String previous);

/// 用户定时器回调。
typedef TbTimerCallback = void Function();
