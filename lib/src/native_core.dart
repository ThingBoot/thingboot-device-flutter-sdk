library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class TbNativeCore {
  static final bool isSupported = Platform.isWindows ||
      Platform.isAndroid ||
      Platform.isMacOS ||
      Platform.isIOS;
  static final TbNativeCore instance = TbNativeCore._();

  TbNativeCore._() {
    if (_abiVersion() != 1) {
      throw StateError('ThingBoot native core ABI mismatch');
    }
  }

  late final DynamicLibrary _library = _openLibrary();
  late final int Function() _abiVersion = _library
      .lookup<NativeFunction<Int32 Function()>>('tb_native_abi_version')
      .asFunction();
  late final int Function(Pointer<Utf8>, int, int, Pointer<Utf8>, int) _md5 =
      _library
          .lookup<
              NativeFunction<
                  Int32 Function(Pointer<Utf8>, IntPtr, Int32, Pointer<Utf8>,
                      IntPtr)>>('tb_md5')
          .asFunction();
  late final int Function(Pointer<Utf8>, int, Pointer<Utf8>, int) _urlEncode =
      _library
          .lookup<
              NativeFunction<
                  Int32 Function(Pointer<Utf8>, IntPtr, Pointer<Utf8>,
                      IntPtr)>>('tb_url_encode')
          .asFunction();
  late final int Function(Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Utf8>,
          Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Utf8>, int)
      _mqttTopic = _library
          .lookup<
              NativeFunction<
                  Int32 Function(
                      Pointer<Utf8>,
                      Pointer<Utf8>,
                      Int32,
                      Pointer<Utf8>,
                      Pointer<Utf8>,
                      Pointer<Utf8>,
                      Pointer<Utf8>,
                      Int32,
                      Pointer<Utf8>,
                      IntPtr)>>('tb_mqtt_topic')
          .asFunction();
  late final int Function(
          Pointer<Utf8>, Pointer<Utf8>, int, int, Pointer<Utf8>, int)
      _sysMessage = _library
          .lookup<
              NativeFunction<
                  Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Uint32, Int64,
                      Pointer<Utf8>, IntPtr)>>('tb_sys_message')
          .asFunction();

  static DynamicLibrary _openLibrary() {
    final override = Platform.environment['THINGBOOT_NATIVE_LIBRARY'];
    if (override != null && override.isNotEmpty) {
      return DynamicLibrary.open(override);
    }
    if (Platform.isWindows) {
      final testLibrary = File('build/native/windows/thingboot_device.dll');
      if (testLibrary.existsSync()) {
        return DynamicLibrary.open(testLibrary.absolute.path);
      }
      return DynamicLibrary.open('thingboot_device.dll');
    }
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libthingboot_device.so');
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open('thingboot_device.framework/thingboot_device');
    }
    if (Platform.isIOS) return DynamicLibrary.process();
    throw UnsupportedError(
        'ThingBoot native core requires Windows, Android, macOS or iOS');
  }

  String md5(String data, int outputLength) {
    if (outputLength <= 0 || outputLength > 32) {
      throw ArgumentError.value(outputLength, 'outputLength');
    }
    return _withInput(data, (input, length) {
      return _stringResult(
          (output, size) => _md5(input, length, outputLength, output, size));
    });
  }

  String urlEncode(String data) {
    return _withInput(data, (input, length) {
      return _stringResult(
          (output, size) => _urlEncode(input, length, output, size));
    });
  }

  String mqttTopic(
    String productKey,
    String deviceKey,
    int topic,
    String side, {
    String pvtTopic = '',
    String pvtClient = '',
    String pvtKey = '',
    bool azure = false,
  }) {
    return _withInputs(
        [productKey, deviceKey, side, pvtTopic, pvtClient, pvtKey], (inputs) {
      return _stringResult((output, size) => _mqttTopic(
          inputs[0],
          inputs[1],
          topic,
          inputs[2],
          inputs[3],
          inputs[4],
          inputs[5],
          azure ? 1 : 0,
          output,
          size));
    });
  }

  String sysMessage(String mid, String data, int device, int ts) {
    return _withInputs([mid, data], (inputs) {
      return _stringResult((output, size) =>
          _sysMessage(inputs[0], inputs[1], device, ts, output, size));
    });
  }

  static String _withInput(
      String value, String Function(Pointer<Utf8>, int) call) {
    final bytes = utf8.encode(value);
    final input = malloc<Uint8>(bytes.length + 1);
    for (var i = 0; i < bytes.length; i++) {
      input[i] = bytes[i];
    }
    input[bytes.length] = 0;
    try {
      return call(input.cast<Utf8>(), bytes.length);
    } finally {
      malloc.free(input);
    }
  }

  static String _withInputs(
      List<String> values, String Function(List<Pointer<Utf8>>) call) {
    final allocations = <Pointer<Uint8>>[];
    final inputs = <Pointer<Utf8>>[];
    try {
      for (final value in values) {
        final bytes = utf8.encode(value);
        final input = malloc<Uint8>(bytes.length + 1);
        allocations.add(input);
        for (var i = 0; i < bytes.length; i++) {
          input[i] = bytes[i];
        }
        input[bytes.length] = 0;
        inputs.add(input.cast<Utf8>());
      }
      return call(inputs);
    } finally {
      for (final allocation in allocations) {
        malloc.free(allocation);
      }
    }
  }

  static String _stringResult(int Function(Pointer<Utf8>, int) call) {
    final needed = call(nullptr, 0);
    if (needed < 0) throw StateError('ThingBoot native call failed: $needed');
    final allocation = malloc<Uint8>(needed + 1);
    final output = allocation.cast<Utf8>();
    try {
      final written = call(output, needed + 1);
      if (written != needed) {
        throw StateError('ThingBoot native write failed: $written');
      }
      return output.toDartString(length: written);
    } finally {
      malloc.free(allocation);
    }
  }
}
