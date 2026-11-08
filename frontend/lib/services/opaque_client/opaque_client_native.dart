import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class _OpaqueNativeRuntime {
  _OpaqueNativeRuntime._();
  static final instance = _OpaqueNativeRuntime._();

  WebViewController? _controller;
  Future<void>? _initializing;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  int _sequence = 0;

  Future<void> ensureInitialized() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    final controller = WebViewController();
    _controller = controller;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel('PbbOpaqueChannel',
      onMessageReceived: (message) {
        try {
          final data = jsonDecode(message.message) as Map<String, dynamic>;
          final id = data['callId']?.toString();
          final completer = id == null ? null : _pending.remove(id);
          if (completer == null || completer.isCompleted) return;
          if (data['ok'] == true) {
            final result = jsonDecode(data['result'] as String);
            if (result is Map) {
              completer.complete(Map<String, dynamic>.from(result));
            } else {
              completer.completeError(const FormatException('OPAQUE 响应格式无效'));
            }
          } else {
            completer.completeError(StateError(data['error']?.toString() ?? 'OPAQUE 操作失败'));
          }
        } catch (error) {
          // Malformed bridge messages never complete a different request.
        }
      });
    await controller.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (request) {
        final uri = Uri.tryParse(request.url);
        if (uri == null) return NavigationDecision.prevent;
        if (uri.scheme == 'file' || uri.scheme == 'about') return NavigationDecision.navigate;
        return NavigationDecision.prevent;
      },
    ));
    await controller.loadFlutterAsset('assets/opaque/index.html');
  }

  Future<Map<String, dynamic>> invoke(
      String method, Map<String, dynamic> payload) async {
    await ensureInitialized();
    final controller = _controller;
    if (controller == null) throw StateError('OPAQUE WebView 尚未初始化');
    final id = 'pbb-call-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final methodJson = jsonEncode(method);
    final payloadJson = jsonEncode(jsonEncode(payload));
    final idJson = jsonEncode(id);
    try {
      await controller.runJavaScript(
        'window.pbbOpaqueInvoke($methodJson,$payloadJson,$idJson);');
      return await completer.future.timeout(const Duration(seconds: 45));
    } catch (_) {
      _pending.remove(id);
      rethrow;
    }
  }

  WebViewController? get controller => _controller;
}

Future<Map<String, dynamic>> opaqueInvoke(
        String method, Map<String, dynamic> payload) =>
    _OpaqueNativeRuntime.instance.invoke(method, payload);

class _OpaqueRuntimeHost extends StatefulWidget {
  const _OpaqueRuntimeHost();
  @override
  State<_OpaqueRuntimeHost> createState() => _OpaqueRuntimeHostState();
}

class _OpaqueRuntimeHostState extends State<_OpaqueRuntimeHost> {
  @override
  void initState() {
    super.initState();
    _OpaqueNativeRuntime.instance.ensureInitialized().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _OpaqueNativeRuntime.instance.controller;
    if (controller == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Opacity(
        opacity: 0,
        child: SizedBox(width: 1, height: 1,
          child: WebViewWidget(controller: controller)),
      ),
    );
  }
}

Widget buildOpaqueRuntimeHost() => const _OpaqueRuntimeHost();
