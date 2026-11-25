
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/data/local/local_database.dart';
import 'package:plan_blind_box/data/local/local_plan_repository.dart';
import 'package:plan_blind_box/services/mod_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets(
    'MOD 初始化分阶段诊断',
        (tester) async {
      Future<void> pumpProbe(String stage) async {
        print('[DIAG] before pump: $stage');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: Text(stage)),
            ),
          ),
        );

        print('[DIAG] after pump: $stage');
      }

      // 阶段 0：不初始化数据库
      await pumpProbe('stage-0');

      final database = LocalDatabase.forTesting(
        factory: databaseFactoryFfi,
      );

      var databaseOpened = false;

      try {
        // 阶段 1：只初始化数据库
        print('[DIAG] before database.initialize');

        await tester.runAsync(() async {
          await database.initialize();
        });

        databaseOpened = true;
        print('[DIAG] after database.initialize');

        await pumpProbe('stage-1');

        // 阶段 2：初始化仓储
        final repository = LocalPlanRepository(
          userId: 1,
          localDatabase: database,
        );

        await tester.runAsync(() async {
          await repository.ensureReady();
        });

        print('[DIAG] after repository.ensureReady');

        await pumpProbe('stage-2');

        // 阶段 3：安装声明式 MOD
        final registry = ModRegistry(repository);

        await tester.runAsync(() async {
          await registry.install(
            jsonEncode({
              'schemaVersion': 1,
              'id': 'com.example.study',
              'name': '阅读挑战',
              'version': '1.0.0',
              'description': '诊断测试',
              'permissions': ['tasks.create'],
              'dependencies': [],
              'taskTemplates': [
                {
                  'title': '今日阅读十页',
                  'note': '阅读复盘',
                  'targetCount': 10,
                  'importance': 3,
                  'difficulty': 2,
                },
              ],
            }),
            grantedPermissions: {'tasks.create'},
          );
        });

        print('[DIAG] after registry.install');

        await pumpProbe('stage-3');
      } finally {
        if (databaseOpened) {
          await tester.runAsync(() async {
            await database.close();
          });
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
