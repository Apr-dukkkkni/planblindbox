import 'dart:math';

import 'api_exception.dart';
import 'local/local_database.dart';
import 'local/local_plan_repository.dart';

/// 商店本地数据门面：扣款、奖励、收藏品库存和开盒记录由 SQLite 事务保证一致。
class ShopApi {
  ShopApi({required this.baseUrl, required this.userId, LocalPlanRepository? repository})
      : _repository = repository ?? LocalPlanRepository(
          userId: userId,
          localDatabase: LocalDatabase.instance,
        );

  final String baseUrl;
  final int userId;
  final LocalPlanRepository _repository;

  Future<List<ShopBox>> getBoxes() async =>
      (await _repository.getShopBoxes()).map(ShopBox.fromJson).toList();

  Future<ShopBalance> getBalance() async =>
      ShopBalance.fromJson(await _repository.getShopBalance());

  Future<List<ShopOpen>> getHistory({int limit = 20}) async =>
      (await _repository.getShopHistory(limit: limit)).map(ShopOpen.fromJson).toList();

  Future<ShopOpen> openBox({required int boxId, required String requestId}) async =>
      ShopOpen.fromJson(await _repository.openBox(boxId: boxId, requestId: requestId));

  void dispose() {}
}

int _integer(dynamic value) {
  if (value is num) return value.toInt();
  throw ApiException('本地商店数据中的数字字段格式错误');
}

int? _nullableInteger(dynamic value) {
  if (value is num) return value.toInt();
  if (value == null) return null;
  return int.tryParse(value.toString());
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
    this.itemId,
    this.itemName,
    this.itemRarity,
    this.itemImagePath,
    this.itemDescription,
  });

  final int openId;
  final String requestId;
  final int boxId;
  final String boxName;
  final int priceCoin;
  final String rewardType;
  final int rewardAmount;
  final ShopBalance balance;

  // COLLECTIBLE 奖励由本地开盒记录附带收藏品详情；数值奖励时这些字段为空。
  final int? itemId;
  final String? itemName;
  final String? itemRarity;
  final String? itemImagePath;
  final String? itemDescription;

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
        itemId: _nullableInteger(json['itemId']),
        itemName: json['itemName']?.toString(),
        itemRarity: json['itemRarity']?.toString(),
        itemImagePath: json['itemImagePath']?.toString(),
        itemDescription: json['itemDescription']?.toString(),
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
