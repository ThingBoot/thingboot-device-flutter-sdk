/// 字符串与哈希工具，对应 Arduino 版 ThingBootSDK/Utils.h 与 common/utils.h，
/// 以 Dart 风格重新组织。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

/// MD5 哈希并居中截取，对应 ThingBootSDK/Utils.h 的 `md5(data, len)`。
///
/// [len] 默认 32（完整 MD5 hex）；`md5(data, 8)` 即从第 12 位起截 8 位，
/// 与 Arduino 版 mid 生成规则一致。
String tbMd5(String data, [int len = 32]) {
  final hex = crypto.md5.convert(utf8.encode(data)).toString();
  final begin = (32 - len) ~/ 2;
  return hex.substring(begin, begin + len);
}

/// 任意值转字符串，对应 ThingBootSDK/Utils.h 的 `CS()`。
///
/// null → ""；bool → "1"/"0"；String 原样；其余 JSON 序列化。
String cs(dynamic value) {
  if (value == null) return '';
  if (value is bool) return value ? '1' : '0';
  if (value is String) return value;
  return jsonEncode(value);
}

/// 任意值转 int，对应 ThingBootSDK/Utils.h 的 `CN()`。
int cn(dynamic value) => int.tryParse(cs(value)) ?? 0;

/// 任意值转 long，对应 ThingBootSDK/Utils.h 的 `CL()`（Dart int 即 64 位）。
int cl(dynamic value) => int.tryParse(cs(value)) ?? 0;

/// 拼接多个值为字符串，对应 ThingBootSDK/Utils.h 的 `CAT()`。
String tbCat(List<dynamic> parts) => parts.map(cs).join();

/// 重复字符串 [times] 次，对应 ThingBootSDK/Utils.h 的 `str_repeat()`。
String strRepeat(String str, int times) {
  final b = StringBuffer();
  for (var i = 0; i < times; i++) {
    b.write(str);
  }
  return b.toString();
}

/// 按指定长度填充字符串，对应 ThingBootSDK/Utils.h 的 `str_pad()`。
///
/// [left] 为 true 时在左侧填充，默认在右侧填充。
String strPad(String str, int len, [String fill = ' ', bool left = false]) {
  if (str.length >= len || fill.isEmpty) return str;
  final need = len - str.length;
  final b = StringBuffer();
  while (b.length + fill.length <= need) {
    b.write(fill);
  }
  final remain = need - b.length;
  if (remain > 0) b.write(fill.substring(0, remain));
  final pad = b.toString();
  return left ? pad + str : str + pad;
}

/// 提取两个子串之间的内容，对应 ThingBootSDK/Utils.h 的 `str_find()`。
String strFind(String str, String begin, String end) {
  final p1 = str.indexOf(begin);
  if (p1 < 0) return '';
  final p2 = str.indexOf(end, p1 + begin.length);
  if (p2 < 0) return '';
  return str.substring(p1 + begin.length, p2);
}

/// 判断字符串是否以指定后缀结尾，对应 ThingBootSDK/Utils.h 的 `str_ends_with()`。
bool strEndsWith(String str, String suffix) => str.endsWith(suffix);

/// 按分隔符拆分字符串（最多 [maxCount] 段，余下部分保留在最后一段），
/// 对应 ThingBootSDK/Utils.h 的 `str_split()`。
List<String> strSplit(String str, String sep, int maxCount) {
  final out = <String>[];
  var start = 0;
  while (out.length < maxCount) {
    final idx = str.indexOf(sep, start);
    if (idx < 0 || out.length == maxCount - 1) {
      out.add(str.substring(start));
      break;
    }
    out.add(str.substring(start, idx));
    start = idx + sep.length;
  }
  return out;
}

/// 从 URL 参数中提取指定参数值，对应 common/utils.h 的 `get_param()`。
String getParam(String params, String param) {
  final key = '$param=';
  var start = '&$params'.indexOf('&$key');
  if (start < 0) return '';
  start += key.length - 1; // 转回原始 params 中的位置
  final end = params.indexOf('&', start);
  return end < 0 ? params.substring(start) : params.substring(start, end);
}

/// 判断 URL 参数中是否包含指定参数，对应 common/utils.h 的 `has_param()`。
bool hasParam(String params, String param) =>
    '&$params'.contains('&$param=');

/// 生成指定范围内的随机数，对应 ThingBootSDK/Utils.h 的 `rand_num()`。
int randNum(int begin, int end) {
  return begin + Random().nextInt(end - begin + 1);
}
