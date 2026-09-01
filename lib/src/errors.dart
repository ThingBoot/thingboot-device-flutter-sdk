/// 错误码常量，照搬 Arduino 版 ThingBootSDK/Errors.h。
///
/// Arduino 的 `uint16_t` 返回值在 Dart 侧统一为 `int`。
library;

/// 成功
const int ERR_OK = 0;

/* ============================================================
 *  系统核心（10xxx）
 * ============================================================ */
const int ERR_SYSTEM_OK = 0;
const int ERR_SYSTEM_VALUE_NULL = 10011;

/* ============================================================
 *  初始化设置（11xxx）
 * ============================================================ */
const int ERR_SETUP_OK = 0;

/* ============================================================
 *  配置管理（12xxx）
 * ============================================================ */
const int ERR_CONFIG_OK = 0;
const int ERR_CONFIG_NAME_EMPTY = 12001;
const int ERR_CONFIG_MAP_FULL = 12002;
const int ERR_CONFIG_POS_INVALID = 12003;
const int ERR_CONFIG_LENGTH_ZERO = 12004;
const int ERR_CONFIG_NAME_CONFLICT = 12005;
const int ERR_CONFIG_NOT_FOUND = 12010;
const int ERR_CONFIG_VALUE_NULL = 12011;
const int ERR_CONFIG_WRITE_FAILED = 12012;

/* ============================================================
 *  命令处理（13xxx）
 * ============================================================ */
const int ERR_ORDER_OK = 0;

/* ============================================================
 *  事件管理（14xxx）
 * ============================================================ */
const int ERR_EVENT_OK = 0;
const int ERR_EVENT_NAME_EMPTY = 14001;
const int ERR_EVENT_CALLBACK_NULL = 14002;
const int ERR_EVENT_NO_SLOT = 14003;
const int ERR_EVENT_VALUE_NULL = 14011;
const int ERR_EVENT_NOT_FOUND = 14020;

/* ============================================================
 *  消息通信（15xxx）
 * ============================================================ */
const int ERR_MESSAGE_OK = 0;

/* ============================================================
 *  状态管理（16xxx）
 * ============================================================ */
const int ERR_STATE_OK = 0;
const int ERR_STATE_NAME_EMPTY = 16001;
const int ERR_STATE_CALLBACK_NULL = 16002;
const int ERR_STATE_INTERVAL_ZERO = 16003;
const int ERR_STATE_NO_SLOT = 16004;

/* ============================================================
 *  定时器（17xxx）
 * ============================================================ */
const int ERR_TIMER_OK = 0;
const int ERR_TIMER_INTERVAL_ZERO = 17001;
const int ERR_TIMER_CALLBACK_NULL = 17002;
const int ERR_TIMER_NO_SLOT = 17003;

/* ============================================================
 *  外设控制（18xxx）
 * ============================================================ */
const int ERR_PERIPHERAL_OK = 0;
const int ERR_PERIPHERAL_NUM_INVALID = 18001;
const int ERR_PERIPHERAL_NOT_CONFIGURED = 18002;

/* ============================================================
 *  调试（19xxx）
 * ============================================================ */
const int ERR_DEBUG_OK = 0;

/* ============================================================
 *  网络（20xxx）
 * ============================================================ */
const int ERR_NETWORK_OK = 0;
const int ERR_NETWORK_DRIVER_MISSING = 20002;
const int ERR_NETWORK_ABI_MISMATCH = 20003;
const int ERR_GATEWAY_DRIVER_MISSING = 20004;
const int ERR_GATEWAY_CHILD_FULL = 20005;
const int ERR_GATEWAY_CHILD_NOT_FOUND = 20006;

/* ============================================================
 *  桥接通信（21xxx）
 * ============================================================ */
const int ERR_BRIDGE_OK = 0;
const int ERR_BRIDGE_NOT_INITIALIZED = 21001;
const int ERR_BRIDGE_PROTOCOL_INVALID = 21002;
const int ERR_BRIDGE_SEND_FAILED = 21003;
const int ERR_BRIDGE_PARAM_INVALID = 21004;

/// Dart 版新增：当前平台不支持该功能（Arduino 版无此码）。
const int ERR_UNSUPPORTED = 90001;
