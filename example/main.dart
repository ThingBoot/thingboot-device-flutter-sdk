/// 最小示例：参照 Arduino examples/Switch 的流程。
///
/// setProduct → 注册回调（onOrder/onFetch/onDebug）→ addConfig → setup()。
/// 与 Arduino 版的差异：无需 loop()（Dart 有事件循环），setup() 为异步。
library;

import 'dart:async';

import 'package:thingboot_device/thingboot_device.dart';

final device = ThingBootDevice();

// 模拟继电器状态（真实场景替换为业务状态）
bool relayState = false;

Future<void> main() async {
  // 调试信息打印
  device.onDebug((category, message) {
    print('[${device.millis()}] $category | $message');
  });

  // 产品信息，请到芯步产品中心定义和查看
  device.setProduct(
    'xxx', // 产品代号[Key]
    'xxxx', // 产品密码[Secret]
    'demo', // 适配板型，自由定义
    'flutter', // 适配平台
    '0.1.0.1', // 当前固件版本号
  );

  // 在开发阶段，请打开下面的链接免费获取设备接入激活码
  // https://www.thingboot.com/developer/center/access/
  device.setActiveCode('xxxxxxxxxxxxx');

  // 设备配置
  device.config.addConfig('relay', 0, 1);
  device.config.addConfig('btn_action', 1, 3);

  // 设置命令回调函数（首参为消息 ID mid，应答时原样传回）
  device.order.onOrder((mid, data) {
    if (data is Map && data.containsKey('power')) {
      relayState = cn(data['power']) > 0;
      device.order.replyMessage(mid, '{"power":"${relayState ? 1 : 0}"}');
    }
  });

  // 设备每次上线后，SDK 通过该回调获取全量属性并上报
  device.state.onFetch(() => {'power': relayState});

  // 系统状态变化（上线/离线）
  device.onSystemStateChange((current, previous) {
    print('system state: $previous -> $current');
  });

  // 异步初始化：激活 → 注册 → 连 MQTT → 订阅
  await device.setup();

  // 上报一个事件示例
  device.event.reportEvent('btn', {'power': relayState});
}
