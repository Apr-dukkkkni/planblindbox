import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/data/local/local_database.dart';
import 'package:plan_blind_box/data/local/local_plan_repository.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_capability_broker.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_runtime_manager.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_runtime_session.dart';
import 'package:plan_blind_box/mod_platform/ui/mod_ui_panel.dart';
import 'package:plan_blind_box/services/mod_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _testManifest = {
  'schemaVersion': 1,
  'id': 'com.example.study',
  'name': '阅读挑战',
  'version': '1.0.0',
  'description': '声明式模板',
  'permissions': ['tasks.create'],
  'dependencies': <String>[],
  'taskTemplates': [
    {
      'title': '今日阅读十页',
      'note': '阅读复盘',
      'targetCount': 10,
      'importance': 3,
      'difficulty': 2,
    },
  ],
};

/// Wait for a visible UI state without waiting for all animations to settle.
/// ModUiPanel shows an indeterminate progress indicator during host operations.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 80,
  Duration frameStep = const Duration(milliseconds: 50),
}) async {
  for (var frame = 0; frame < maxFrames; frame++) {
    if (finder.evaluate().isNotEmpty) return;

    // The UI callback performs real SQLite work through taskPayload/Broker.
    // pump(frameStep) advances only FakeAsync time; it does not give real I/O
    // a chance to complete. Wait briefly outside FakeAsync, then pump once to
    // process the resulting state update.
    await tester.runAsync(() async {
      await Future<void>.delayed(frameStep);
    });
    await tester.pump();
  }
  fail(
    'Expected UI was not shown after '
    '${maxFrames * frameStep.inMilliseconds}ms: $finder',
  );
}

Future<void> _pumpUntilConfirmationOrResult(WidgetTester tester) async {
  final dialog = find.text('创建宿主任务？');
  final result = find.byKey(const Key('mod-ui-result'));

  for (var frame = 0; frame < 80; frame++) {
    if (dialog.evaluate().isNotEmpty) return;

    if (result.evaluate().isNotEmpty) {
      final message = tester.widget<Text>(result).data;
      fail(
        'MOD taskPayload failed before the confirmation dialog appeared: '
        '$message',
      );
    }

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  fail(
    'Neither the confirmation dialog nor a MOD UI result appeared '
    'within 4000ms.',
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('界面中的创建任务仍必须经过管理员审批，没有证明时不写库', (tester) async {
    late LocalDatabase database;
    late LocalPlanRepository repository;
    late ModRegistry registry;
    late ModRuntimeManager runtime;
    late ModCapabilityBroker broker;
    late ModRuntimeSessionManager sessions;
    late ModRuntimeInstance instance;

    // Real SQLite/Future work must not be performed in the WidgetTest
    // FakeAsync zone. Initialize the complete test harness in runAsync.
    await tester.runAsync(() async {
      database = LocalDatabase.forTesting(factory: databaseFactoryFfi);
      await database.initialize();

      repository = LocalPlanRepository(userId: 1, localDatabase: database);
      await repository.ensureReady();

      sessions = ModRuntimeSessionManager();
      registry = ModRegistry(repository, sessionManager: sessions);
      runtime = ModRuntimeManager.forRepository(
        repository,
        sessionManager: sessions,
      );
      broker = ModCapabilityBroker.forRepository(
        repository,
        sessionManager: sessions,
      );

      await registry.install(
        jsonEncode(_testManifest),
        grantedPermissions: {'tasks.create'},
      );
      instance = await runtime.start('com.example.study');
    });

    addTearDown(() async {
      runtime.shutdown();
      await tester.runAsync(() async {
        await database.close();
      });
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModUiPanel(
            instance: instance,
            runtime: runtime,
            broker: broker,
          ),
        ),
      ),
    );

    expect(find.text('今日阅读十页'), findsOneWidget);

    await tester.tap(find.text('今日阅读十页'));
    await _pumpUntilConfirmationOrResult(tester);
    expect(find.text('创建宿主任务？'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mod-ui-confirm-create')));
    await _pumpUntilFound(tester, find.textContaining('操作已拒绝'));
    expect(find.textContaining('操作已拒绝'), findsOneWidget);

    late List<Map<String, dynamic>> tasks;
    await tester.runAsync(() async {
      tasks = await repository.getAllTasks();
    });
    expect(tasks, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('撤销权限后 UI 不再允许触发创建任务', (tester) async {
    late LocalDatabase database;
    late LocalPlanRepository repository;
    late ModRegistry registry;
    late ModRuntimeManager runtime;
    late ModCapabilityBroker broker;
    late ModRuntimeSessionManager sessions;
    late ModRuntimeInstance instance;

    await tester.runAsync(() async {
      database = LocalDatabase.forTesting(factory: databaseFactoryFfi);
      await database.initialize();

      repository = LocalPlanRepository(userId: 1, localDatabase: database);
      await repository.ensureReady();

      sessions = ModRuntimeSessionManager();
      registry = ModRegistry(repository, sessionManager: sessions);
      runtime = ModRuntimeManager.forRepository(
        repository,
        sessionManager: sessions,
      );
      broker = ModCapabilityBroker.forRepository(
        repository,
        sessionManager: sessions,
      );

      await registry.install(
        jsonEncode(_testManifest),
        grantedPermissions: {'tasks.create'},
      );
      instance = await runtime.start('com.example.study');
    });

    addTearDown(() async {
      runtime.shutdown();
      await tester.runAsync(() async {
        await database.close();
      });
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModUiPanel(
            instance: instance,
            runtime: runtime,
            broker: broker,
          ),
        ),
      ),
    );
    expect(find.text('今日阅读十页'), findsOneWidget);

    await tester.runAsync(() async {
      await registry.revokePermission('com.example.study', 'tasks.create');
    });

    // Rebuild after the registry invalidates the installation's session.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModUiPanel(
            instance: instance,
            runtime: runtime,
            broker: broker,
          ),
        ),
      ),
    );

    expect(find.text('MOD 会话已失效'), findsOneWidget);

    late List<Map<String, dynamic>> tasks;
    await tester.runAsync(() async {
      tasks = await repository.getAllTasks();
    });
    expect(tasks, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
