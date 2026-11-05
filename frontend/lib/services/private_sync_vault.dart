import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core_sync_service.dart';

/// E2EE key is never sent to mod-server. The server stores only a random KDF
/// salt and an authenticated encrypted verifier. Recovery phrase is not stored.
/// On Android, an already-unlocked key is cached in platform secure storage;
/// browsers must explicitly unlock for every fresh session.
class PrivateSyncVault extends ChangeNotifier {
  PrivateSyncVault._();
  static final PrivateSyncVault instance = PrivateSyncVault._();
  static const kdfIterations = 210000;
  static const _storage = FlutterSecureStorage();
  static final _aes = AesGcm.with256bits();
  static final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(),
      iterations: kdfIterations, bits: 256);
  int? _user;
  List<int>? _key;
  String? _message;

  bool unlocked(int user) => _user == user && _key != null;
  bool get isUnlocked => _key != null;
  String? get message => _message;

  void lock() {
    _key = null;
    _user = null;
    _message = null;
    notifyListeners();
  }

  static List<int> _random(int count) {
    final rng = Random.secure();
    return List<int>.generate(count, (_) => rng.nextInt(256));
  }

  static List<int> _decode(String value) => base64Decode(value);

  static String _ownerScope(int localUserId) => '${-1000000 - localUserId}';
  String _aad(int user, String type, String uuid) =>
      'PlanBlindBox:e2ee:v1:${_ownerScope(user)}:$type:$uuid';

  Future<Map<String, dynamic>> _seal(List<int> key, String text,
      String aad) async {
    final box = await _aes.encrypt(utf8.encode(text),
        secretKey: SecretKey(key), nonce: _random(12), aad: utf8.encode(aad));
    return {
      'alg': 'aes-256-gcm',
      'keyVersion': 1,
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    };
  }

  Future<String> _open(List<int> key, Map<String, dynamic> payload,
      String aad) async {
    if (payload['alg'] != 'aes-256-gcm' || payload['keyVersion'] != 1) {
      throw const FormatException('不支持的私密数据加密版本');
    }
    final nonce = _decode(payload['nonce'] as String);
    final mac = _decode(payload['tag'] as String);
    if (nonce.length != 12 || mac.length != 16) {
      throw const FormatException('无效的加密数据');
    }
    final plaintext = await _aes.decrypt(
      SecretBox(_decode(payload['ciphertext'] as String),
          nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(key), aad: utf8.encode(aad));
    return utf8.decode(plaintext);
  }

  Future<List<int>> _derive(String password, String salt) async {
    if (password.length < 10) {
      throw ArgumentError('私密同步恢复口令至少需要10个字符');
    }
    final s = _decode(salt);
    if (s.length < 16 || s.length > 64) throw const FormatException('密钥盐值不合法');
    return (await _kdf.deriveKeyFromPassword(password: password, nonce: s))
        .extractBytes();
  }

  Future<void> _accept(int user, List<int> key,
      Map<String, dynamic> verifier) async {
    final value = await _open(key, verifier, _aad(user, 'verify', 'v1'));
    if (value != 'PlanBlindBox private sync key verification v1') {
      throw StateError('恢复口令不正确');
    }
    _user = user;
    _key = key;
    _message = '私密数据加密同步已解锁';
    // Web secure storage is origin-scoped; do not persist a reusable E2EE key there.
    if (!kIsWeb) {
      try {
        await _storage.write(key: 'pbb.private.key.${_ownerScope(user)}',
            value: base64Encode(key));
      } catch (_) { // Keystore may be unavailable in desktop unit tests.
        _message = '本次已解锁；设备安全存储不可用，下次需要重新输入口令';
      }
    }
    notifyListeners();
  }

  Future<bool> tryRestore(int user, String token, CoreSyncClient client) async {
    if (unlocked(user)) return true;
    if (kIsWeb) return false;
    final stored = await _storage.read(key: 'pbb.private.key.${_ownerScope(user)}');
    if (stored == null) return false;
    final config = await client.cryptoConfig(token);
    if (config['configured'] != true) return false;
    try {
      final key = _decode(stored);
      if (key.length != 32) return false;
      await _accept(user, key, Map<String, dynamic>.from(config['verifier'] as Map));
      return true;
    } catch (_) {
      await _storage.delete(key: 'pbb.private.key.${_ownerScope(user)}');
      return false;
    }
  }

  Future<void> unlock(int user, String token, CoreSyncClient client,
      String recoveryPhrase) async {
    if (user >= -1000000) throw StateError('请先登录账号');
    var config = await client.cryptoConfig(token);
    if (config['configured'] == true) {
      final key = await _derive(recoveryPhrase, config['salt'] as String);
      try {
        await _accept(user, key, Map<String, dynamic>.from(config['verifier'] as Map));
      } catch (_) {
        throw StateError('恢复口令错误或云端密钥参数损坏');
      }
      return;
    }
    final salt = base64Encode(_random(16));
    final key = await _derive(recoveryPhrase, salt);
    final verifier = await _seal(key,
        'PlanBlindBox private sync key verification v1',
        _aad(user, 'verify', 'v1'));
    try {
      config = await client.createCryptoConfig(token,
          salt: salt, iterations: kdfIterations, verifier: verifier);
    } on CoreSyncException catch (error) {
      if (error.status != 409) rethrow;
      // Another device provisioned the key first; NEVER replace its config.
      config = await client.cryptoConfig(token);
    }
    final established = await _derive(recoveryPhrase, config['salt'] as String);
    await _accept(user, established,
        Map<String, dynamic>.from(config['verifier'] as Map));
  }

  String idForDay(int user, String day) {
    if (!unlocked(user)) throw StateError('私密同步尚未解锁');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
      throw const FormatException('日期格式无效');
    }
    final digest = hashes.Hmac(hashes.sha256, _key!)
        .convert(utf8.encode('PlanBlindBox:private-day:v1:$day')).bytes;
    final bytes = digest.take(16).toList();
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-'
        '${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }

  Future<Map<String, dynamic>> encryptRecord(int user, String uuid,
      Map<String, dynamic> contents, {String type = 'diary'}) async {
    if (!unlocked(user)) throw StateError('先解锁私密同步');
    return _seal(_key!, jsonEncode(contents), _aad(user, type, uuid));
  }

  Future<Map<String, dynamic>> decryptRecord(int user, String uuid,
      Map<String, dynamic> envelope, {String type = 'diary'}) async {
    if (!unlocked(user)) throw StateError('先解锁私密同步');
    final text = await _open(_key!, envelope, _aad(user, type, uuid));
    return Map<String, dynamic>.from(jsonDecode(text) as Map);
  }
}

/// A reusable password-encrypted WebDAV container, separate from account E2EE.
/// The recovery password is never uploaded to Jianguoyun or kept in preferences.
class WebDavArchiveCipher {
  static const iterations = 210000;
  static final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(),
      iterations: iterations, bits: 256);
  static final _aes = AesGcm.with256bits();

  static Future<Map<String, dynamic>> encrypt(String raw, String password,
      int owner) async {
    if (password.length < 10) throw ArgumentError('备份密码至少10个字符');
    final rng = Random.secure();
    final salt = List<int>.generate(16, (_) => rng.nextInt(256));
    final nonce = List<int>.generate(12, (_) => rng.nextInt(256));
    final key = await _kdf.deriveKeyFromPassword(password: password, nonce: salt);
    final box = await _aes.encrypt(utf8.encode(raw), secretKey: key,
        nonce: nonce, aad: utf8.encode('PlanBlindBox:webdav:v2:$owner'));
    return {
      'alg': 'aes-256-gcm', 'kdf': 'pbkdf2-hmac-sha256',
      'iterations': iterations, 'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    };
  }

  static Future<String> decrypt(Map<String, dynamic> payload,
      String password, int owner) async {
    if (password.isEmpty) throw StateError('需要备份恢复密码');
    if (payload['alg'] != 'aes-256-gcm' ||
        payload['kdf'] != 'pbkdf2-hmac-sha256' ||
        payload['iterations'] != iterations) {
      throw const FormatException('未知的加密备份版本或 KDF 参数');
    }
    final salt = base64Decode(payload['salt'] as String);
    final nonce = base64Decode(payload['nonce'] as String);
    final tag = base64Decode(payload['tag'] as String);
    if (salt.length != 16 || nonce.length != 12 || tag.length != 16) {
      throw const FormatException('备份加密参数无效');
    }
    final key = await _kdf.deriveKeyFromPassword(password: password, nonce: salt);
    try {
      final plaintext = await _aes.decrypt(SecretBox(
          base64Decode(payload['ciphertext'] as String),
          nonce: nonce, mac: Mac(tag)), secretKey: key,
          aad: utf8.encode('PlanBlindBox:webdav:v2:$owner'));
      return utf8.decode(plaintext);
    } catch (_) {
      throw StateError('备份密码错误或存档被篡改，未恢复数据');
    }
  }
}
