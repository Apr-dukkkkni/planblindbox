import 'local/local_database.dart';
import 'local/local_plan_repository.dart';

/// 本地图鉴读取门面，不再请求 /collection 接口。
class CollectionApi {
  CollectionApi({
    required this.baseUrl,
    required this.userId,
    LocalPlanRepository? repository,
  }) : _repository = repository ?? LocalPlanRepository(
          userId: userId,
          localDatabase: LocalDatabase.instance,
        );

  final String baseUrl;
  final int userId;
  final LocalPlanRepository _repository;

  Future<List<CollectionPack>> getPacks() async =>
      (await _repository.getCollectionPacks()).map(CollectionPack.fromJson).toList();

  Future<List<CollectionItem>> getItems(int packId) async =>
      (await _repository.getCollectionItems(packId)).map(CollectionItem.fromJson).toList();

  void dispose() {}
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
