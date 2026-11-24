import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/mod_platform/ui/mod_ui_surface.dart';

void main() {
  Future<void> showSurface(
    WidgetTester tester,
    ModUiPresentation mode, {
    required VoidCallback onClose,
    VoidCallback? onBackgroundTap,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 780));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              key: const Key('background'),
              behavior: HitTestBehavior.opaque,
              onTap: onBackgroundTap,
              child: const Center(child: Text('宿主页面')),
            ),
          ),
          Positioned.fill(
            child: ModUiSurface(
              presentation: mode,
              onClose: onClose,
              child: const Center(child: Text('经过验证的声明式 MOD 内容')),
            ),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('全屏 MOD 容器覆盖宿主并始终提供退出入口', (tester) async {
    var closed = 0;
    await showSurface(tester, ModUiPresentation.fullscreen,
        onClose: () => closed++);
    expect(find.text('经过验证的声明式 MOD 内容'), findsOneWidget);
    expect(find.byKey(const Key('mod-ui-close')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mod-ui-close')));
    expect(closed, 1);
  });

  testWidgets('弹窗的屏障阻挡对宿主内容的误触', (tester) async {
    var backgroundTaps = 0;
    await showSurface(tester, ModUiPresentation.dialog,
        onClose: () {}, onBackgroundTap: () => backgroundTaps++);
    expect(find.byType(ModalBarrier), findsWidgets);
    await tester.tapAt(const Offset(10, 340));
    await tester.pump();
    expect(backgroundTaps, 0);
  });

  testWidgets('悬浮 MOD 可拖动且关闭按钮仍可点击', (tester) async {
    var closed = 0;
    await showSurface(tester, ModUiPresentation.floating,
        onClose: () => closed++);
    final handle = find.byKey(const Key('mod-ui-drag-handle'));
    expect(handle, findsOneWidget);
    final before = tester.getTopLeft(handle);
    await tester.drag(handle, const Offset(-45, -35));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(handle);
    expect(after.dx, lessThan(before.dx));
    expect(after.dy, lessThan(before.dy));
    await tester.tap(find.byKey(const Key('mod-ui-close')));
    expect(closed, 1);
  });

  test('三种展示模式全部有明确标签', () {
    expect(ModUiPresentation.values.map((mode) => mode.label),
        ['全屏', '弹窗', '悬浮']);
  });
}
