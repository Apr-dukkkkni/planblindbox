import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// V2 account private-data key holder.
///
/// The 256-bit AMK is generated on the client and is never uploaded in clear.
/// It is wrapped by the OPAQUE export key before it is stored on the server.
/// This class only keeps an in-memory copy while the current account session is
/// active and a device-protected copy in platform secure storage for seamless
/// refresh/reopen on a trusted device.
class PrivateSyncVault extends ChangeNotifier {
  PrivateSyncVault._();
  static final PrivateSyncVault instance = PrivateSyncVault._();

  static const int keyVersion = 2;
  static const _storage = FlutterSecureStorage();
  static final _aes = AesGcm.with256bits();
  int? _user;
  List<int>? _key;
  String? _message;

  bool unlocked(int user) => _user == user && _key != null;
  bool get isUnlocked => _key != null;
  String? get message => _message;

  static List<int> _random(int count) {
    final rng = Random.secure();
    return List<int>.generate(count, (_) => rng.nextInt(256));
  }

  static String _scope(int localUserId) =>
      localUserId <= -1000001 ? '${-1000000 - localUserId}' : 'guest-$localUserId';

  String _storageKey(int localUserId) => 'pbb.account_master_key.v2.${_scope(localUserId)}';

  String _aad(int user, String type, String uuid) =>
      'PlanBlindBox:private-vault:v2:${_scope(user)}:$type:$uuid';

  /// Activates a key obtained from a successful OPAQUE login/registration.
  /// A device-protected copy is stored so a normal refresh does not ask for a
  /// second password. On Web this relies on flutter_secure_storage's
  /// WebCrypto-backed origin storage and therefore requires HTTPS/localhost.
  Future<void> activate(int localUserId, List<int> masterKey,
      {bool persist = true}) async {
    if (masterKey.length != 32) {
      throw const FormatException('账号主密钥长度必须为 256 bit');
    }
    _user = localUserId;
    _key = List<int>.from(masterKey);
    _message = '私密数据仓库已解锁';
    if (persist) {
      try {
        await _storage.write(
          key: _storageKey(localUserId),
          value: base64Encode(masterKey),
        );
      } catch (_) {
        _message = '本次已解锁；设备安全存储不可用，重新打开时需要重新登录';
      }
    }
    notifyListeners();
  }

  /// Restore the AMK only from this device's secure storage. No server request
  /// or user-managed recovery phrase is involved in the normal path.
  Future<bool> tryRestore(int localUserId) async {
    if (unlocked(localUserId)) return true;
    try {
      final stored = await _storage.read(key: _storageKey(localUserId));
      if (stored == null) return false;
      final key = base64Decode(stored);
      if (key.length != 32) {
        await _storage.delete(key: _storageKey(localUserId));
        return false;
      }
      _user = localUserId;
      _key = key;
      _message = '已从本机安全存储恢复私密数据密钥';
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Guest data is still encrypted locally, but the guest key is device-only
  /// and is never eligible for cloud sync.
  Future<void> ensureGuestKey() async {
    if (unlocked(-1)) return;
    if (await tryRestore(-1)) return;
    await activate(-1, _random(32));
  }

  /// Locks the in-memory copy. The device-wrapped copy is retained so normal
  /// account re-entry can restore it without an extra sync password.
  void lock() {
    _key = null;
    _user = null;
    _message = null;
    notifyListeners();
  }

  Future<void> forgetDeviceKey(int localUserId) async {
    await _storage.delete(key: _storageKey(localUserId));
    if (_user == localUserId) lock();
  }

  List<int> _requireKey(int user) {
    if (!unlocked(user)) throw StateError('私密数据仓库尚未解锁');
    return _key!;
  }

  /// Deterministic, account-specific opaque ID. The date itself is never sent
  /// to the server or stored in the V2 private-vault index.
  String idForDay(int user, String day) {
    final key = _requireKey(user);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
      throw const FormatException('日期格式无效');
    }
    final digest = hashes.Hmac(hashes.sha256, key)
        .convert(utf8.encode('PlanBlindBox:private-day:v2:$day')).bytes;
    final bytes = digest.take(16).toList();
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-'
        '${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }

  Future<Map<String, dynamic>> encryptRecord(int user, String uuid,
      Map<String, dynamic> contents, {String type = 'diary'}) async {
    final key = _requireKey(user);
    if (type != 'diary' && type != 'mood_custom') {
      throw const FormatException('不支持的私密记录类型');
    }
    final privatePayload = <String, dynamic>{...contents, '_vaultType': type};
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(privatePayload)),
      secretKey: SecretKey(key),
      nonce: _random(12),
      // The server sees one generic private_blob type. The real record type
      // exists only inside ciphertext and is authenticated as payload data.
      aad: utf8.encode(_aad(user, 'private_blob', uuid)),
    );
    return {
      'alg': 'aes-256-gcm',
      'keyVersion': keyVersion,
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    };
  }

  Future<Map<String, dynamic>> decryptRecord(int user, String uuid,
      Map<String, dynamic> envelope, {String type = 'diary',
      bool includeVaultType = false}) async {
    final key = _requireKey(user);
    const expected = {'alg', 'keyVersion', 'nonce', 'ciphertext', 'tag'};
    if (envelope.keys.toSet().difference(expected).isNotEmpty ||
        envelope.keys.toSet().length != expected.length ||
        envelope['alg'] != 'aes-256-gcm' ||
        envelope['keyVersion'] != keyVersion) {
      throw const FormatException('不支持或不合法的 V2 私密数据加密信封');
    }
    final nonce = base64Decode(envelope['nonce'] as String);
    final cipher = base64Decode(envelope['ciphertext'] as String);
    final tag = base64Decode(envelope['tag'] as String);
    if (nonce.length != 12 || tag.length != 16 || cipher.isEmpty) {
      throw const FormatException('V2 私密数据加密参数无效');
    }
    final plaintext = await _aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(tag)),
      secretKey: SecretKey(key),
      aad: utf8.encode(_aad(user, 'private_blob', uuid)),
    );
    final decoded = jsonDecode(utf8.decode(plaintext));
    if (decoded is! Map) throw const FormatException('私密记录内容不是对象');
    final result = Map<String, dynamic>.from(decoded);
    final actualType = result['_vaultType'];
    if (actualType != 'diary' && actualType != 'mood_custom') {
      throw const FormatException('私密记录类型标记无效');
    }
    if (type != 'private_blob' && actualType != type) {
      throw const FormatException('私密记录类型与本地索引不匹配');
    }
    if (!includeVaultType) result.remove('_vaultType');
    return result;
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
