import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/services/private_sync_vault.dart';

void main() {
  final vault = PrivateSyncVault.instance;
  const userId = -1000042;
  final key = List<int>.generate(32, (i) => (i * 11 + 7) & 0xff);

  setUp(() async {
    await vault.activate(userId, key, persist: false);
  });

  tearDown(() => vault.lock());

  test('V2 local private record is an opaque AES-GCM envelope', () async {
    const uuid = 'e91d6a11-8aef-5f11-9c3d-9f0b9b2e8a77';
    final envelope = await vault.encryptRecord(userId, uuid, {
      'business_date': '2026-11-05',
      'diary': 'private test text',
      'period': 1,
    }, type: 'diary');
    expect(envelope.keys.toSet(), {'alg', 'keyVersion', 'nonce', 'ciphertext', 'tag'});
    expect(envelope['keyVersion'], 2);
    expect(envelope.toString().contains('private test text'), isFalse);
    expect(envelope.toString().contains('2026-11-05'), isFalse);

    final restored = await vault.decryptRecord(userId, uuid, envelope, type: 'diary');
    expect(restored['diary'], 'private test text');
    expect(restored['business_date'], '2026-11-05');
    expect(restored.containsKey('_vaultType'), isFalse);
  });

  test('V2 server wire type does not expose diary or custom mood type', () async {
    const uuid = 'a4e4f9b8-1a42-4b50-9d91-8bca04d8a271';
    final envelope = await vault.encryptRecord(userId, uuid, {
      'moods': [{'name': '紧张', 'emoji': '😰'}],
    }, type: 'mood_custom');
    final decoded = await vault.decryptRecord(userId, uuid, envelope,
      type: 'private_blob', includeVaultType: true);
    expect(decoded['_vaultType'], 'mood_custom');
    expect(decoded['moods'], isA<List>());
  });

  test('tampering with V2 ciphertext or record identifier fails authentication', () async {
    const uuid = '4a9b0b21-1c3d-4e5f-8a7b-9c0d1e2f3a4b';
    final envelope = await vault.encryptRecord(userId, uuid, {'diary': 'secret'}, type: 'diary');
    final tampered = Map<String, dynamic>.from(envelope);
    tampered['ciphertext'] = '${tampered['ciphertext']}AA';
    await expectLater(vault.decryptRecord(userId, uuid, tampered, type: 'diary'), throwsA(anything));
    await expectLater(vault.decryptRecord(userId, '$uuid-x', envelope, type: 'diary'), throwsA(anything));
  });
}
