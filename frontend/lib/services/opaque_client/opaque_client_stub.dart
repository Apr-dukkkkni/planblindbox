import 'package:flutter/widgets.dart';

Future<Map<String, dynamic>> opaqueInvoke(
    String method, Map<String, dynamic> payload) async {
  throw StateError('当前平台尚未集成 OPAQUE 客户端');
}

Widget buildOpaqueRuntimeHost() => const SizedBox.shrink();
