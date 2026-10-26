import 'dart:convert';

import 'package:http/http.dart' as http;

import 'today_api.dart';

/// 只负责读取收藏系列和收藏品，不负责开盒或发放收藏品。
class CollectionApi {
  CollectionApi({
    required this.baseUrl,
    required this.userId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final int userId;
  final http.Client _client;

  Uri _url(String path, [Map<String, String>? params]) {
    final normalizedBase = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath')
        .replace(queryParameters: params);
  }

  Future<dynamic> _get(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));

      final dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw ApiException(
          '收藏接口返回了无法解析的数据（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }

      if (decoded is! Map) {
        throw ApiException(
          '收藏接口返回的数据格式不正确',
          statusCode: response.statusCode,
        );
      }

      final envelope = Map<String, dynamic>.from(decoded);
      final code = (envelope['code'] as num?)?.toInt();
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          code != 200) {
        final message = envelope['message']?.toString();
        throw ApiException(
          message != null && message.isNotEmpty
              ? message
              : '收藏请求失败（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }
      return envelope['data'];
    } on ApiException {
      rethrow;
    } on Exception catch (error) {
      throw ApiException('无法加载收藏数据，请检查后端连接：$error');
    }
  }

  List<dynamic> _extractList(dynamic data, String errorMessage) {
    if (data is List) return data;
    if (data is Map) {
      // 兼容常见分页包装；当前后端直接返回 List。
      for (final key in const ['records', 'list', 'items', 'content']) {
        final value = data[key];
        if (value is List) return value;
      }
    }
    throw ApiException(errorMessage);
  }

  Future<List<CollectionPack>> getPacks() async {
    final data = await _get(_url('/collection/packs', {
      'userId': '$userId',
    }));
    return _extractList(data, '收藏系列列表格式错误')
        .map((value) => CollectionPack.fromJson(_asMap(value)))
        .toList();
  }

  Future<List<CollectionItem>> getItems(int packId) async {
    final data = await _get(_url('/collection/packs/$packId/items', {
      'userId': '$userId',
    }));
    return _extractList(data, '收藏品列表格式错误')
        .map((value) => CollectionItem.fromJson(_asMap(value)))
        .toList();
  }

  void dispose() => _client.close();
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is! Map) {
    throw ApiException('服务器返回的收藏数据格式错误');
  }
  return Map<String, dynamic>.from(value);
}

int _intValue(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _boolValue(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return value?.toString().toLowerCase() == 'true' ||
      value?.toString() == '1';
}

class CollectionPack {
  const CollectionPack({
    required this.id,
    required this.key,
    required this.name,
    required this.description,
    required this.version,
    required this.unlockLevel,
    required this.totalItems,
    required this.ownedItems,
  });

  final int id;
  final String key;
  final String name;
  final String description;
  final String version;
  final int unlockLevel;
  final int totalItems;
  final int ownedItems;

  double get progress =>
      totalItems <= 0 ? 0 : (ownedItems / totalItems).clamp(0.0, 1.0);

  factory CollectionPack.fromJson(Map<String, dynamic> json) =>
      CollectionPack(
        id: _intValue(json['packId']),
        key: json['packKey']?.toString() ?? '',
        name: json['name']?.toString() ?? '未命名系列',
        description: json['description']?.toString() ?? '',
        version: json['version']?.toString() ?? '',
        unlockLevel: _intValue(json['unlockLevel']),
        totalItems: _intValue(json['totalItems']),
        ownedItems: _intValue(json['ownedItems']),
      );
}

class CollectionItem {
  const CollectionItem({
    required this.id,
    required this.packId,
    required this.key,
    required this.name,
    required this.rarity,
    required this.description,
    required this.imagePath,
    required this.sortOrder,
    required this.ownedCount,
    required this.owned,
  });

  final int id;
  final int packId;
  final String key;
  final String name;
  final String rarity;
  final String description;
  final String imagePath;
  final int sortOrder;
  final int ownedCount;
  final bool owned;

  factory CollectionItem.fromJson(Map<String, dynamic> json) =>
      CollectionItem(
        id: _intValue(json['itemId']),
        packId: _intValue(json['packId']),
        key: json['itemKey']?.toString() ?? '',
        name: json['name']?.toString() ?? '未知收藏品',
        rarity: json['rarity']?.toString() ?? 'COMMON',
        description: json['description']?.toString() ?? '',
        imagePath: json['imagePath']?.toString() ?? '',
        sortOrder: _intValue(json['sortOrder']),
        ownedCount: _intValue(json['ownedCount']),
        owned: _boolValue(json['owned']),
      );
}
