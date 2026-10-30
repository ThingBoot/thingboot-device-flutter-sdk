/// 字符串与哈希工具，以 IDF ThingBootSDK/Utils.h 与 common/utils.h 为基准。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

import 'native_core.dart';

/// MD5 哈希并居中截取，对应 IDF ThingBootSDK/Utils.h 的 `md5(data, len)`。
String tbMd5(String data, [int len = 32]) {
  if (TbNativeCore.isSupported) return TbNativeCore.instance.md5(data, len);
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

/// 从 URL 参数中提取指定参数值。
///
/// 语义与 Arduino common/utils.h 的 `get_param()` 一致（整名匹配，避免
/// `sign` 误中 `mysign=`）。
///
/// 注意：IDF/Arduino SDK 同函数有差一缺陷（`start += key.length() - 1`），
/// 返回值会**多带一个 `=` 前缀**（如 `=gateway`）——前缀 `&` 与搜索串里
/// 的 `&` 抵消后，值起始 = 命中位置 + key.length()。本实现取正确值；
/// 与 IDF 侧修复方案（`+= key.length()`）等价。
String getParam(String params, String param) {
  final key = '$param=';
  final p = '&$params';
  final start = p.indexOf('&$key');
  if (start < 0) return '';
  // 值起始 = 命中位 + '&' 长度 + key 长度
  final valueStart = start + 1 + key.length;
  final end = p.indexOf('&', valueStart);
  return end < 0 ? p.substring(valueStart) : p.substring(valueStart, end);
}

/// 判断 URL 参数中是否包含指定参数，对应 common/utils.h 的 `has_param()`。
bool hasParam(String params, String param) => '&$params'.contains('&$param=');

/// URL 编码（percent-encode 非 unreserved 字符，RFC 3986），
/// 对应 ThingBootSDK/Utils.h 的 `url_encode()`。
///
/// 按 UTF-8 字节编码：非 ASCII 字符逐字节转 `%XX`（与 C 版逐字节语义一致）。
String urlEncode(String s) {
  if (TbNativeCore.isSupported) return TbNativeCore.instance.urlEncode(s);
  const unreserved =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final b = StringBuffer();
  for (final byte in utf8.encode(s)) {
    final ch = String.fromCharCode(byte);
    if (unreserved.contains(ch)) {
      b.write(ch);
    } else {
      b.write('%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}');
    }
  }
  return b.toString();
}

/// 构造 URL（键值对自动 URL 编码），对应 ThingBootSDK/Utils.h 的 `url_build()`。
///
/// [base] 为路径（可已含 `?`，决定首个分隔符是 `?` 还是 `&`）；
/// [params] 按键值对追加，值经 [urlEncode] 编码（Dart Map 保持插入序）。
/// 用法：`urlBuild('reg/v4/', {'bench': 12, 'key': 'abc'})`
/// → `reg/v4/?bench=12&key=abc`
String urlBuild(String base, Map<String, Object?> params) {
  var sep = base.contains('?') ? '&' : '?';
  final b = StringBuffer(base);
  params.forEach((key, value) {
    b.write('$sep$key=${urlEncode(cs(value))}');
    sep = '&';
  });
  return b.toString();
}

/// 生成指定范围内的随机数，对应 ThingBootSDK/Utils.h 的 `rand_num()`。
int randNum(int begin, int end) {
  return begin + Random().nextInt(end - begin + 1);
}
