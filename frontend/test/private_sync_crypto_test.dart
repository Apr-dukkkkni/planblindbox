import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/services/private_sync_vault.dart';

void main() {
  const password = 'correct-horse-backup-2026';
  test('encrypted WebDAV archive roundtrip preserves Unicode private fields', () async {
    const raw = '{"diary":"私密日记","period":1,"mood":"开心"}';
    final data = await WebDavArchiveCipher.encrypt(raw, password, -1000001);
    expect(data.toString().contains('私密日记'), false);
    final restored = await WebDavArchiveCipher.decrypt(data, password, -1000001);
    expect(jsonDecode(restored), jsonDecode(raw));
  });

  test('wrong password and wrong owner must not decrypt', () async {
    final data = await WebDavArchiveCipher.encrypt('private', password, -1000001);
    await expectLater(
      WebDavArchiveCipher.decrypt(data, 'incorrect-password-123', -1000001),
      throwsA(isA<StateError>()));
    await expectLater(
      WebDavArchiveCipher.decrypt(data, password, -1000002),
      throwsA(isA<StateError>()));
  });

  test('ciphertext manipulation is rejected by AES-GCM', () async {
    final data = await WebDavArchiveCipher.encrypt('secret', password, -1000001);
    final modified = Map<String, dynamic>.from(data);
    final bytes = base64Decode(modified['ciphertext'] as String);
    bytes[0] ^= 1;
    modified['ciphertext'] = base64Encode(bytes);
    await expectLater(
      WebDavArchiveCipher.decrypt(modified, password, -1000001),
      throwsA(isA<StateError>()));
  });
}
