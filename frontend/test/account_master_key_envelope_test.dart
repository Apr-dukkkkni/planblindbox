import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/services/account_master_key_envelope.dart';

void main() {
  const account = 'opaque-test@example.com';
  final exportKey = base64Url.encode(List<int>.generate(32, (i) => i + 1));
  final otherExportKey = base64Url.encode(List<int>.generate(32, (i) => 255 - i));
  final amk = List<int>.generate(32, (i) => (i * 7 + 3) & 0xff);

  test('OPAQUE export key wraps and unwraps the account master key', () async {
    final envelope = await AccountMasterKeyEnvelope.wrap(
      exportKey: exportKey,
      masterKey: amk,
      accountIdentifier: account,
    );
    expect(envelope['version'], 2);
    expect(envelope['alg'], 'aes-256-gcm');
    expect(jsonEncode(envelope).contains(base64Encode(amk)), isFalse);
    final restored = await AccountMasterKeyEnvelope.unwrap(
      exportKey: exportKey,
      envelope: envelope,
      accountIdentifier: account,
    );
    expect(restored, amk);
  });

  test('wrong export key or account identifier cannot unwrap AMK', () async {
    final envelope = await AccountMasterKeyEnvelope.wrap(
      exportKey: exportKey,
      masterKey: amk,
      accountIdentifier: account,
    );
    await expectLater(
      AccountMasterKeyEnvelope.unwrap(
        exportKey: otherExportKey,
        envelope: envelope,
        accountIdentifier: account,
      ),
      throwsA(anything),
    );
    await expectLater(
      AccountMasterKeyEnvelope.unwrap(
        exportKey: exportKey,
        envelope: envelope,
        accountIdentifier: 'other@example.com',
      ),
      throwsA(anything),
    );
  });

  test('unsupported envelope versions are rejected before decryption', () async {
    final envelope = await AccountMasterKeyEnvelope.wrap(
      exportKey: exportKey,
      masterKey: amk,
      accountIdentifier: account,
    );
    envelope['version'] = 1;
    await expectLater(
      AccountMasterKeyEnvelope.unwrap(
        exportKey: exportKey,
        envelope: envelope,
        accountIdentifier: account,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
