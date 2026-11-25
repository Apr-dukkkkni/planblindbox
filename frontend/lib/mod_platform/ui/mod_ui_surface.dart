import 'dart:math' as math;

import 'package:flutter/material.dart';

/// P0-4B: host-owned UI containers, not a third-party widget/HTML sandbox.
/// The choice is made by the host's launch menu until signed V1 UI metadata
/// and its security review are implemented.
enum ModUiPresentation { fullscreen, dialog, floating }

extension ModUiPresentationLabel on ModUiPresentation {
  String get label => switch (this) {
    ModUiPresentation.fullscreen => '全屏',
    ModUiPresentation.dialog => '弹窗',
    ModUiPresentation.floating => '悬浮',
  };
}

/// Only the floating window has a drag handle. Other surfaces cover the host
/// body so that an untrusted MOD cannot draw over privileged host controls.
class ModUiSurface extends StatefulWidget {
  const ModUiSurface({
    super.key,
    required this.presentation,
    required this.child,
    required this.onClose,
  });

  final ModUiPresentation presentation;
  final Widget child;
  final VoidCallback onClose;

  @override
  State<ModUiSurface> createState() => _ModUiSurfaceState();
}

class _ModUiSurfaceState extends State<ModUiSurface> {
  double _right = 12;
  double _bottom = 12;

  void _drag(DragUpdateDetails details, Size bounds, double width, double height) {
    setState(() {
      _right = (_right - details.delta.dx)
          .clamp(0.0, math.max(0.0, bounds.width - width)).toDouble();
      _bottom = (_bottom - details.delta.dy)
          .clamp(0.0, math.max(0.0, bounds.height - height)).toDouble();
    });
  }

  Widget _panel({GestureDragUpdateCallback? drag}) {
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: widget.presentation == ModUiPresentation.fullscreen
          ? BorderRadius.zero
          : BorderRadius.circular(18),
      elevation: widget.presentation == ModUiPresentation.fullscreen ? 0 : 10,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Row(
            children: [
              if (widget.presentation == ModUiPresentation.floating)
                GestureDetector(
                  key: const Key('mod-ui-drag-handle'),
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: drag,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(12, 12, 8, 12),
                    child: Icon(Icons.drag_indicator),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Icon(Icons.extension_outlined),
                ),
              const Expanded(
                child: Text('MOD 扩展', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                key: const Key('mod-ui-close'),
                tooltip: '关闭 MOD 并返回首页',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Size(constraints.maxWidth, constraints.maxHeight);
        switch (widget.presentation) {
          case ModUiPresentation.fullscreen:
            return Stack(children: [
              Positioned.fill(
                child: SafeArea(child: _panel()),
              ),
            ]);
          case ModUiPresentation.dialog:
            return Stack(children: [
              const Positioned.fill(
                child: ModalBarrier(dismissible: false, color: Colors.black54),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(1.0, math.min(440.0, constraints.maxWidth - 32)),
                      maxHeight: math.max(1.0, math.min(540.0, constraints.maxHeight - 32)),
                    ),
                    child: _panel(),
                  ),
                ),
              ),
            ]);
          case ModUiPresentation.floating:
            final width = math.min(320.0, math.max(1.0, constraints.maxWidth - 24));
            final height = math.min(405.0, math.max(1.0, constraints.maxHeight - 24));
            final safeRight = _right
                .clamp(0.0, math.max(0.0, bounds.width - width))
                .toDouble();
            final safeBottom = _bottom
                .clamp(0.0, math.max(0.0, bounds.height - height))
                .toDouble();
            return Stack(children: [
              Positioned(
                right: safeRight,
                bottom: safeBottom,
                width: width,
                height: height,
                child: _panel(
                  drag: (details) => _drag(details, bounds, width, height),
                ),
              ),
            ]);
        }
      },
    );
  }
}
