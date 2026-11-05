import 'dart:convert';

/// Passwords are never trimmed. All email entry points use this normalization.
String normalizedEmail(String value) => value.trim().toLowerCase();
String normalizedUsername(String value) => value.trim();

String? usernameError(String? raw) {
  final value = normalizedUsername(raw ?? '');
  final len = value.runes.length;
  if (len < 1 || len > 50) return '名称需为 1～50 个字符';
  return null;
}

String? emailError(String? raw) {
  final value = normalizedEmail(raw ?? '');
  if (value.isEmpty || value.length > 100 || value.contains(' ') ||
      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
    return '请输入有效邮箱（最多 100 字符）';
  }
  return null;
}

String? passwordError(String? value) {
  final password = value ?? '';
  if (password.runes.length < 8 || password.runes.length > 64) {
    return '密码需为 8～64 个字符';
  }
  if (utf8.encode(password).length > 72) {
    return '密码 UTF-8 编码不能超过 72 字节';
  }
  return null;
}

const genderOptions = <String, String>{
  'MALE': '男', 'FEMALE': '女', 'UNDISCLOSED': '保密',
};
