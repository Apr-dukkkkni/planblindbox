import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'api_exception.dart';
import 'local/local_database.dart';

/// 自定义商品与仓库：全部存储在本机 SQLite，与原有盲盒独立。
class CustomShopApi {
  CustomShopApi({required this.userId, LocalDatabase? database})
      : _database = database ?? LocalDatabase.instance;

  final int userId;
  final LocalDatabase _database;
  Future<Database> get _db => _database.database;

  String get _now => DateTime.now().toIso8601String();

  void _validate({
    required String name,
    required String description,
    required String? imageBase64,
    required int priceCoin,
    required int stock,
    required String kind,
  }) {
    if (name.trim().isEmpty || name.trim().length > 50) {
      throw ApiException('商品名称需为 1～50 字', statusCode: 400);
    }
    if (description.length > 500) {
      throw ApiException('商品描述不能超过 500 字', statusCode: 400);
    }
    if (priceCoin < 0 || priceCoin > 100000000 || stock < 0 || stock > 1000000) {
      throw ApiException('价格或库存超过允许范围', statusCode: 400);
    }
    if (kind != 'CONSUMABLE' && kind != 'COLLECTIBLE') {
      throw ApiException('商品类型不正确', statusCode: 400);
    }
    if (imageBase64 != null && imageBase64.length > 1400000) {
      throw ApiException('图片太大，请选择不超过 1 MB 的图片', statusCode: 400);
    }
    if (imageBase64 != null) {
      try {
        base64Decode(imageBase64);
      } catch (_) {
        throw ApiException('图片数据格式错误', statusCode: 400);
      }
    }
  }

  Future<List<String>> getCategories() async {
    final db = await _db;
    final rows = await db.query('custom_product_categories',
      columns: ['name'], where: 'user_id = ?', whereArgs: [userId], orderBy: 'category_id ASC');
    return rows.map((row) => row['name']!.toString()).toList();
  }

  Future<void> createCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 20 || (trimmed == '默认' || trimmed == '全部')) {
      throw ApiException('种类名称需为 1～20 字，且不能为“默认”或“全部”', statusCode: 400);
    }
    final db = await _db;
    final exists = await db.query('custom_product_categories',
      where: 'user_id = ? AND name = ?', whereArgs: [userId, trimmed], limit: 1);
    if (exists.isNotEmpty) throw ApiException('该商品种类已存在', statusCode: 409);
    await db.insert('custom_product_categories', {'user_id': userId, 'name': trimmed});
  }

  Future<void> deleteCategory(String name) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('custom_products', {'category_name': '默认'},
        where: 'user_id = ? AND category_name = ?', whereArgs: [userId, name]);
      await txn.delete('custom_product_categories',
        where: 'user_id = ? AND name = ?', whereArgs: [userId, name]);
    });
  }

  Future<List<CustomProduct>> getProducts({bool includeArchived = false}) async {
    final db = await _db;
    final rows = await db.query('custom_products',
        where: includeArchived ? 'user_id = ?' : 'user_id = ? AND enabled = 1',
        whereArgs: [userId], orderBy: 'product_id DESC');
    return rows.map(CustomProduct.fromRow).toList();
  }

  Future<int> saveProduct({
    int? productId,
    required String name,
    required String description,
    required String? imageBase64,
    required int priceCoin,
    required int stock,
    required String kind,
    String categoryName = '默认',
  }) async {
    if (categoryName != '默认') {
      final categories = await getCategories();
      if (!categories.contains(categoryName)) {
        throw ApiException('商品种类不存在，请重新选择', statusCode: 400);
      }
    }
    _validate(name: name, description: description, imageBase64: imageBase64,
        priceCoin: priceCoin, stock: stock, kind: kind);
    final db = await _db;
    final now = _now;
    final values = <String, Object?>{
      'name': name.trim(), 'description': description.trim(),
      'image_base64': imageBase64, 'price_coin': priceCoin,
      'stock': stock, 'kind': kind, 'category_name': categoryName, 'update_time': now,
    };
    if (productId == null) {
      return db.insert('custom_products', {
        ...values, 'user_id': userId, 'enabled': 1, 'create_time': now,
      });
    }
    return db.transaction((txn) async {
      final rows = await txn.query('custom_products',
        where: 'product_id = ? AND user_id = ?', whereArgs: [productId, userId]);
      if (rows.isEmpty) throw ApiException('商品不存在', statusCode: 404);
      final owned = await txn.query('custom_inventory',
        columns: ['quantity'], where: 'product_id = ? AND user_id = ?',
        whereArgs: [productId, userId], limit: 1);
      if (owned.isNotEmpty && (owned.first['quantity'] as num).toInt() > 0 &&
          rows.first['kind'] != kind) {
        throw ApiException('仓库中已有该商品，不能修改消耗品/收藏品类型', statusCode: 409);
      }
      await txn.update('custom_products', values,
        where: 'product_id = ? AND user_id = ?', whereArgs: [productId, userId]);
      return productId;
    });
  }

  /// 下架而非物理删除：已购买的商品仍在仓库，可查看历史。
  Future<void> archive(int productId) async {
    final db = await _db;
    final count = await db.update('custom_products',
      {'enabled': 0, 'update_time': _now},
      where: 'product_id = ? AND user_id = ?', whereArgs: [productId, userId]);
    if (count != 1) throw ApiException('商品不存在', statusCode: 404);
  }

  /// 购买、扣款、减库存、入仓、写流水为一个事务。重试用同一个 requestId。
  Future<CustomPurchase> purchase({required int productId, required String requestId}) async {
    if (requestId.isEmpty || requestId.length > 80) {
      throw ApiException('购买请求编号无效', statusCode: 400);
    }
    final db = await _db;
    return db.transaction((txn) async {
      final existing = await txn.query('custom_purchase_records',
        where: 'user_id = ? AND request_id = ?',
        whereArgs: [userId, requestId], limit: 1);
      if (existing.isNotEmpty) {
        final prior = existing.first;
        if ((prior['product_id'] as num).toInt() != productId) {
          throw ApiException('同一请求编号不能购买不同商品', statusCode: 409);
        }
        return CustomPurchase(productId: productId,
          priceCoin: (prior['price_coin'] as num).toInt(), alreadyProcessed: true);
      }
      final products = await txn.query('custom_products',
        where: 'product_id = ? AND user_id = ? AND enabled = 1',
        whereArgs: [productId, userId], limit: 1);
      if (products.isEmpty) throw ApiException('商品不存在或已下架', statusCode: 404);
      final product = CustomProduct.fromRow(products.first);
      if (product.stock <= 0) throw ApiException('库存不足', statusCode: 409);
      final now = _now;
      await txn.insert('user_assets', {
        'user_id': userId, 'coin': 0, 'exp': 0, 'water': 0, 'update_time': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final paid = await txn.rawUpdate(
        'UPDATE user_assets SET coin = coin - ?, update_time = ? WHERE user_id = ? AND coin >= ?',
        [product.priceCoin, now, userId, product.priceCoin]);
      if (paid != 1) throw ApiException('金币不足', statusCode: 409);
      final deducted = await txn.rawUpdate(
        'UPDATE custom_products SET stock = stock - 1, update_time = ? '
        'WHERE product_id = ? AND user_id = ? AND enabled = 1 AND stock > 0',
        [now, productId, userId]);
      if (deducted != 1) throw ApiException('库存不足', statusCode: 409);
      await txn.insert('custom_purchase_records', {
        'user_id': userId, 'product_id': productId,
        'request_id': requestId, 'price_coin': product.priceCoin,
        'create_time': now,
      });
      final owned = await txn.query('custom_inventory',
        where: 'user_id = ? AND product_id = ?', whereArgs: [userId, productId]);
      if (owned.isEmpty) {
        await txn.insert('custom_inventory', {
          'user_id': userId, 'product_id': productId,
          'quantity': 1, 'update_time': now,
        });
      } else {
        await txn.rawUpdate(
          'UPDATE custom_inventory SET quantity = quantity + 1, update_time = ? '
          'WHERE user_id = ? AND product_id = ?', [now, userId, productId]);
      }
      if (product.priceCoin != 0) {
        await txn.insert('asset_records', {
          'user_id': userId, 'action': 'SPEND', 'asset_type': 'COIN',
          'amount': -product.priceCoin, 'source': 'CUSTOM_PRODUCT',
          'source_id': productId, 'create_time': now,
        });
      }
      return CustomPurchase(productId: productId,
        priceCoin: product.priceCoin, alreadyProcessed: false);
    });
  }

  Future<List<WarehouseItem>> getWarehouse() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT p.*, i.quantity FROM custom_inventory AS i
      JOIN custom_products AS p ON p.product_id = i.product_id
      WHERE i.user_id = ? AND p.user_id = ? AND i.quantity > 0
      ORDER BY i.update_time DESC, p.product_id DESC
    ''', [userId, userId]);
    return rows.map((row) => WarehouseItem(
      product: CustomProduct.fromRow(row), quantity: (row['quantity'] as num).toInt(),
    )).toList();
  }

  Future<void> consume(int productId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final products = await txn.query('custom_products',
        where: 'product_id = ? AND user_id = ?', whereArgs: [productId, userId]);
      if (products.isEmpty) throw ApiException('商品不存在', statusCode: 404);
      if (products.first['kind'] != 'CONSUMABLE') {
        throw ApiException('收藏品不能消耗', statusCode: 400);
      }
      final now = _now;
      final changed = await txn.rawUpdate(
        'UPDATE custom_inventory SET quantity = quantity - 1, update_time = ? '
        'WHERE user_id = ? AND product_id = ? AND quantity > 0',
        [now, userId, productId]);
      if (changed != 1) throw ApiException('仓库库存不足', statusCode: 409);
      await txn.insert('custom_use_records', {
        'user_id': userId, 'product_id': productId,
        'quantity': 1, 'create_time': now,
      });
    });
  }
}

class CustomProduct {
  const CustomProduct({required this.id, required this.name,
    required this.description, required this.imageBase64,
    required this.priceCoin, required this.stock,
    required this.kind, required this.enabled, this.categoryName = '默认'});
  final int id;
  final String name;
  final String description;
  final String? imageBase64;
  final int priceCoin;
  final int stock;
  final String kind;
  final bool enabled;
  final String categoryName;

  factory CustomProduct.fromRow(Map<String, Object?> row) => CustomProduct(
    id: (row['product_id'] as num).toInt(),
    name: row['name'] as String,
    description: row['description']?.toString() ?? '',
    imageBase64: row['image_base64']?.toString(),
    priceCoin: (row['price_coin'] as num).toInt(),
    stock: (row['stock'] as num).toInt(),
    kind: row['kind']?.toString() ?? 'CONSUMABLE',
    enabled: (row['enabled'] as num).toInt() == 1,
    categoryName: row['category_name']?.toString() ?? '默认',
  );
}

class WarehouseItem {
  const WarehouseItem({required this.product, required this.quantity});
  final CustomProduct product;
  final int quantity;
}

class CustomPurchase {
  const CustomPurchase({required this.productId, required this.priceCoin,
    required this.alreadyProcessed});
  final int productId;
  final int priceCoin;
  final bool alreadyProcessed;
}
