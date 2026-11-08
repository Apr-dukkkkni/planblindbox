import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Wraps the random account master key with the OPAQUE export key.
/// The resulting envelope is safe to store on the application server: the
/// server never receives the OPAQUE export key or the unwrapped AMK.
class AccountMasterKeyEnvelope {
  static const version = 2;
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static List<int> _random(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static List<int> _decodeKey(String encoded) {
    try {
      final normalized = base64.normalize(encoded.replaceAll('-', '+').replaceAll('_', '/'));
      return base64Decode(normalized);
    } catch (_) {
      throw const FormatException('OPAQUE export key 编码无效');
    }
  }

  static String _context(String accountIdentifier) =>
      'PlanBlindBox:account-master-key:v2:${accountIdentifier.trim().toLowerCase()}';

  static Future<Map<String, dynamic>> wrap({
    required String exportKey,
    required List<int> masterKey,
    required String accountIdentifier,
  }) async {
    if (masterKey.length != 32) throw ArgumentError('AMK 必须为 256 bit');
    final exportBytes = _decodeKey(exportKey);
    if (exportBytes.length < 32) throw const FormatException('OPAQUE export key 长度无效');
    final salt = _random(16);
    final wrappingKey = await _hkdf.deriveKey(
      secretKey: SecretKey(exportBytes),
      nonce: salt,
      info: utf8.encode('${_context(accountIdentifier)}:wrap'),
    );
    final box = await _aes.encrypt(
      masterKey,
      secretKey: wrappingKey,
      nonce: _random(12),
      aad: utf8.encode(_context(accountIdentifier)),
    );
    return {
      'version': version,
      'kdf': 'hkdf-sha256',
      'alg': 'aes-256-gcm',
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    };
  }

  static Future<List<int>> unwrap({
    required String exportKey,
    required Map<String, dynamic> envelope,
    required String accountIdentifier,
  }) async {
    const fields = {'version', 'kdf', 'alg', 'salt', 'nonce', 'ciphertext', 'tag'};
    if (envelope.keys.toSet().length != fields.length ||
        !envelope.keys.toSet().containsAll(fields) ||
        envelope['version'] != version ||
        envelope['kdf'] != 'hkdf-sha256' ||
        envelope['alg'] != 'aes-256-gcm') {
      throw const FormatException('账号主密钥包装格式或版本不受支持');
    }
    final exportBytes = _decodeKey(exportKey);
    final salt = base64Decode(envelope['salt'] as String);
    final nonce = base64Decode(envelope['nonce'] as String);
    final cipher = base64Decode(envelope['ciphertext'] as String);
    final tag = base64Decode(envelope['tag'] as String);
    if (exportBytes.length < 32 || salt.length != 16 || nonce.length != 12 ||
        cipher.length != 32 || tag.length != 16) {
      throw const FormatException('账号主密钥包装参数无效');
    }
    final wrappingKey = await _hkdf.deriveKey(
      secretKey: SecretKey(exportBytes),
      nonce: salt,
      info: utf8.encode('${_context(accountIdentifier)}:wrap'),
    );
    final plaintext = await _aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(tag)),
      secretKey: wrappingKey,
      aad: utf8.encode(_context(accountIdentifier)),
    );
    if (plaintext.length != 32) throw const FormatException('解包后的 AMK 长度错误');
    return plaintext;
  }
}
