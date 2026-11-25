import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_runtime_session.dart';

void main() {
  test('Session 到期后自动失效', () {
    var now = DateTime.utc(2026, 11, 10, 12);
    final manager = ModRuntimeSessionManager(
      clock: () => now,
      sessionLifetime: const Duration(minutes: 15),
    );
    final session = manager.open(
      ownerId: -1,
      installationId: 'install-1',
      modId: 'com.example.study',
    );

    expect(manager.isActive(session), isTrue);
    now = now.add(const Duration(minutes: 14, seconds: 59));
    expect(manager.isActive(session), isTrue);
    now = now.add(const Duration(seconds: 1));
    expect(manager.isActive(session), isFalse);
  });

  test('终止安装实例后旧 Session 不可恢复', () {
    final manager = ModRuntimeSessionManager();
    final session = manager.open(
      ownerId: 8,
      installationId: 'install-2',
      modId: 'com.example.farm',
    );
    manager.terminateInstallation('install-2');
    expect(manager.isActive(session), isFalse);

    final next = manager.open(
      ownerId: 8,
      installationId: 'install-2',
      modId: 'com.example.farm',
    );
    expect(manager.isActive(next), isTrue);
    expect(manager.isActive(session), isFalse);
  });

  test('按账号终止和全局终止都只影响对应 Session', () {
    final manager = ModRuntimeSessionManager();
    final accountOne = manager.open(
      ownerId: 1,
      installationId: 'install-a',
      modId: 'com.example.a',
    );
    final accountTwo = manager.open(
      ownerId: 2,
      installationId: 'install-b',
      modId: 'com.example.b',
    );

    manager.terminateOwner(1);
    expect(manager.isActive(accountOne), isFalse);
    expect(manager.isActive(accountTwo), isTrue);

    manager.terminateAll();
    expect(manager.isActive(accountTwo), isFalse);
  });
  test('只有 Host Declarative Runtime 创建的 Session 才带有 verifiedRuntime 标记', () {
    final manager = ModRuntimeSessionManager();
    final unverified = manager.open(
      ownerId: 1,
      installationId: 'install-v1',
      modId: 'com.example.v1',
    );
    expect(unverified.verifiedRuntime, isFalse);

    final verified = manager.open(
      ownerId: 1,
      installationId: 'install-v1',
      modId: 'com.example.v1',
      verifiedRuntime: true,
    );
    expect(verified.verifiedRuntime, isTrue);
  });

}
