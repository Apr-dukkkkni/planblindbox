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

void main() {
  late LocalDatabase database;
  late LocalPlanRepository repository;
  late ModRegistry registry;
  late ModRuntimeManager runtime;
  late ModCapabilityBroker broker;
  late ModRuntimeSessionManager sessions;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
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
    await registry.install(jsonEncode({
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
    }), grantedPermissions: {'tasks.create'});
  });
  tearDown(() async {
    runtime.shutdown();
    await database.close();
  });

  testWidgets('界面中的创建任务仍必须经过管理员审批，没有证明时不写库',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 780));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final instance = await runtime.start('com.example.study');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModUiPanel(instance: instance, runtime: runtime, broker: broker),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('今日阅读十页'), findsOneWidget);
    await tester.tap(find.text('今日阅读十页'));
    await tester.pumpAndSettle();
    expect(find.text('创建宿主任务？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mod-ui-confirm-create')));
    await tester.pumpAndSettle();
    expect(find.textContaining('操作已拒绝'), findsOneWidget);
    expect(await repository.getAllTasks(), isEmpty);
  });

  testWidgets('撤销权限后 UI 不再允许触发创建任务', (tester) async {
    final instance = await runtime.start('com.example.study');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModUiPanel(instance: instance, runtime: runtime, broker: broker),
      ),
    ));
    await tester.pumpAndSettle();
    await registry.revokePermission('com.example.study', 'tasks.create');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModUiPanel(instance: instance, runtime: runtime, broker: broker),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('MOD 会话已失效'), findsOneWidget);
    expect(await repository.getAllTasks(), isEmpty);
  });
}
