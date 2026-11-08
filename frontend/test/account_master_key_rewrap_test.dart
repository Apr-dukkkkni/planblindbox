import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/services/account_master_key_envelope.dart';

void main() {
  group('AccountMasterKeyEnvelope password rotation', () {
    test('rewraps the same AMK with a new OPAQUE export key', () async {
      final oldExportKey = base64Encode(List<int>.generate(64, (i) => i + 1));
      final newExportKey = base64Encode(List<int>.generate(64, (i) => 255 - i));
      final masterKey = List<int>.generate(32, (i) => (i * 7) & 0xff);
      const accountIdentifier = '0123456789abcdef0123456789abcdef';

      final oldEnvelope = await AccountMasterKeyEnvelope.wrap(
        exportKey: oldExportKey,
        masterKey: masterKey,
        accountIdentifier: accountIdentifier,
      );

      final recoveredMasterKey = await AccountMasterKeyEnvelope.unwrap(
        exportKey: oldExportKey,
        envelope: oldEnvelope,
        accountIdentifier: accountIdentifier,
      );
      expect(recoveredMasterKey, masterKey);

      final newEnvelope = await AccountMasterKeyEnvelope.wrap(
        exportKey: newExportKey,
        masterKey: recoveredMasterKey,
        accountIdentifier: accountIdentifier,
      );

      final recoveredWithNewPassword = await AccountMasterKeyEnvelope.unwrap(
        exportKey: newExportKey,
        envelope: newEnvelope,
        accountIdentifier: accountIdentifier,
      );
      expect(recoveredWithNewPassword, masterKey);

      await expectLater(
        AccountMasterKeyEnvelope.unwrap(
          exportKey: oldExportKey,
          envelope: newEnvelope,
          accountIdentifier: accountIdentifier,
        ),
        throwsA(anything),
      );
    });

    test('rejects a changed account identifier', () async {
      final exportKey = base64Encode(List<int>.generate(64, (i) => i + 3));
      final masterKey = List<int>.generate(32, (i) => i);
      final envelope = await AccountMasterKeyEnvelope.wrap(
        exportKey: exportKey,
        masterKey: masterKey,
        accountIdentifier: 'account-a',
      );

      await expectLater(
        AccountMasterKeyEnvelope.unwrap(
          exportKey: exportKey,
          envelope: envelope,
          accountIdentifier: 'account-b',
        ),
        throwsA(anything),
      );
    });
  });
}
