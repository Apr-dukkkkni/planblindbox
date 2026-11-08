import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';

@JS('window.pbbOpaqueInvoke')
external JSPromise<JSString> _pbbOpaqueInvoke(JSString method, JSString payloadJson);

Future<Map<String, dynamic>> opaqueInvoke(
    String method, Map<String, dynamic> payload) async {
  try {
    final result = await _pbbOpaqueInvoke(
      method.toJS, jsonEncode(payload).toJS).toDart.timeout(const Duration(seconds: 45));
    final decoded = jsonDecode(result.toDart);
    if (decoded is! Map) throw const FormatException('OPAQUE 客户端响应无效');
    return Map<String, dynamic>.from(decoded);
  } catch (error) {
    throw StateError('OPAQUE 客户端操作失败：$error');
  }
}

Widget buildOpaqueRuntimeHost() => const SizedBox.shrink();
