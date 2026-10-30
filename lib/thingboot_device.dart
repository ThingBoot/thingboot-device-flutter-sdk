/// 芯步设备 SDK（ThingBoot Device SDK）Flutter 移植版。
///
/// 对外接口以 ESP-IDF SDK 为唯一基准：
///
/// ```dart
/// import 'package:thingboot_device/thingboot_device.dart';
///
/// final device = ThingBootDevice();
///
/// Future<void> main() async {
///   device.setProduct('product-key', 'product-secret', 'board', 'flutter', '0.1.0.1');
///   device.order.onOrder((mid, data) {
///     device.order.replyMessage(mid, '{"result":"ok"}');
///   });
///   await device.setup();
/// }
/// ```
library;

export 'src/errors.dart';
export 'src/types.dart';
export 'src/utils.dart';
export 'src/device.dart';
export 'src/config.dart';
export 'src/order.dart';
export 'src/event.dart';
export 'src/message.dart';
export 'src/state.dart';
export 'src/timer.dart';
export 'src/peripheral.dart';
export 'src/network.dart';
export 'src/gateway.dart';
export 'src/bridge.dart';
export 'src/api.dart';
