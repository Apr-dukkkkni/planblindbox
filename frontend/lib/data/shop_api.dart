import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'today_api.dart';

/// 与后端 ShopController 的 Result<T> 格式对应。
class ShopApi {
  ShopApi({required this.baseUrl, required this.userId, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final int userId;
  final http.Client _client;

  Uri _url(String path, [Map<String, String>? params]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: params);

  Future<dynamic> _request(String method, Uri uri, {Object? body}) async {
    try {
      final headers = <String, String>{'Accept': 'application/json'};
      if (body != null) {
        headers['Content-Type'] = 'application/json; charset=utf-8';
      }

      final http.Response response;
      switch (method) {
        case 'GET':
          response = await _client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 12));
        case 'POST':
          response = await _client
              .post(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 12));
        default:
          throw ApiException('不支持的请求方法：$method');
      }

      final dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw ApiException('服务器响应不是合法 JSON（HTTP ${response.statusCode}）',
            statusCode: response.statusCode);
      }
      if (decoded is! Map) {
        throw ApiException('服务器响应格式不正确', statusCode: response.statusCode);
      }
      final envelope = Map<String, dynamic>.from(decoded);
      final code = (envelope['code'] as num?)?.toInt();
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          code != 200) {
        final message = envelope['message']?.toString();
        throw ApiException(
          (message != null && message.isNotEmpty)
              ? message
              : '请求失败（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }
      return envelope['data'];
    } on ApiException {
      rethrow;
    } on Exception catch (error) {
      throw ApiException('网络请求失败，请核对后端状态：$error');
    }
  }

  Future<List<ShopBox>> getBoxes() async {
    final data = await _request('GET', _url('/shop/boxes'));
    if (data is! List) throw ApiException('商品列表格式错误');
    return data.map((e) => ShopBox.fromJson(_asMap(e))).toList();
  }

  Future<ShopBalance> getBalance() async {
    final data = await _request(
      'GET',
      _url('/shop/balance', {'userId': '$userId'}),
    );
    return ShopBalance.fromJson(_asMap(data));
  }

  Future<List<ShopOpen>> getHistory({int limit = 20}) async {
    final data = await _request('GET', _url('/shop/opens', {
      'userId': '$userId',
      'limit': '$limit',
    }));
    if (data is! List) throw ApiException('开盒历史格式错误');
    return data.map((e) => ShopOpen.fromJson(_asMap(e))).toList();
  }

  Future<ShopOpen> openBox({
    required int boxId,
    required String requestId,
  }) async {
    final data = await _request(
      'POST',
      _url('/shop/boxes/$boxId/open', {'userId': '$userId'}),
      body: {'requestId': requestId},
    );
    return ShopOpen.fromJson(_asMap(data));
  }

  void dispose() => _client.close();
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is! Map) throw ApiException('服务器返回的数据格式错误');
  return Map<String, dynamic>.from(value);
}

int _integer(dynamic value) {
  if (value is num) return value.toInt();
  throw ApiException('服务器返回的数字字段格式错误');
}

class ShopBox {
  const ShopBox({
    required this.id,
    required this.name,
    required this.description,
    required this.priceCoin,
  });

  final int id;
  final String name;
  final String description;
  final int priceCoin;

  factory ShopBox.fromJson(Map<String, dynamic> json) => ShopBox(
        id: _integer(json['boxId']),
        name: json['name']?.toString() ?? '盲盒',
        description: json['description']?.toString() ?? '',
        priceCoin: _integer(json['priceCoin']),
      );
}

class ShopBalance {
  const ShopBalance({
    required this.coin,
    required this.exp,
    required this.water,
  });

  final int coin;
  final int exp;
  final int water;

  factory ShopBalance.fromJson(Map<String, dynamic> json) => ShopBalance(
        coin: _integer(json['coin']),
        exp: _integer(json['exp']),
        water: _integer(json['water']),
      );
}

class ShopOpen {
  const ShopOpen({
    required this.openId,
    required this.requestId,
    required this.boxId,
    required this.boxName,
    required this.priceCoin,
    required this.rewardType,
    required this.rewardAmount,
    required this.balance,
  });

  final int openId;
  final String requestId;
  final int boxId;
  final String boxName;
  final int priceCoin;
  final String rewardType;
  final int rewardAmount;
  final ShopBalance balance;

  factory ShopOpen.fromJson(Map<String, dynamic> json) => ShopOpen(
        openId: _integer(json['openId']),
        requestId: json['requestId']?.toString() ?? '',
        boxId: _integer(json['boxId']),
        boxName: json['boxName']?.toString() ?? '盲盒',
        priceCoin: _integer(json['priceCoin']),
        rewardType: json['rewardType']?.toString() ?? '',
        rewardAmount: _integer(json['rewardAmount']),
        balance: ShopBalance(
          coin: _integer(json['coinBalance']),
          exp: _integer(json['expBalance']),
          water: _integer(json['waterBalance']),
        ),
      );
}

/// UUID v4：每次新的购买生成一次；重试同一购买必须复用已生成的值。
String newShopRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}
