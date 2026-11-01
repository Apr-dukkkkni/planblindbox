import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';

class LocalAssetBalance {
  const LocalAssetBalance({required this.coin, required this.exp, required this.water});
  final int coin;
  final int exp;
  final int water;

  factory LocalAssetBalance.fromRow(Map<String, Object?> row) => LocalAssetBalance(
        coin: (row['coin'] as num?)?.toInt() ?? 0,
        exp: (row['exp'] as num?)?.toInt() ?? 0,
        water: (row['water'] as num?)?.toInt() ?? 0,
      );
}

class LocalSignInResult {
  const LocalSignInResult({
    required this.granted,
    required this.businessDate,
    required this.streakDay,
    required this.baseWater,
    required this.bonusWater,
    required this.totalWater,
    required this.balance,
  });

  final bool granted;
  final DateTime businessDate;
  final int streakDay;
  final int baseWater;
  final int bonusWater;
  final int totalWater;
  final LocalAssetBalance balance;
}

/// 本地成长资产服务。奖励记录、余额变更和业务记录必须处于同一 SQLite 事务。
class LocalGrowthService {
  LocalGrowthService({LocalDatabase? database})
      : _localDatabase = database ?? LocalDatabase.instance;

  final LocalDatabase _localDatabase;

  Future<LocalAssetBalance> getBalance() async {
    final db = await _localDatabase.database;
    final rows = await db.query('user_asset', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return const LocalAssetBalance(coin: 0, exp: 0, water: 0);
    return LocalAssetBalance.fromRow(rows.first);
  }

  /// 同一业务来源的同类奖励只能入账一次。调用方应在同一事务中先写业务记录。
  Future<bool> grant({
    required String action,
    required String source,
    required String sourceId,
    int coin = 0,
    int exp = 0,
    int water = 0,
  }) async {
    if (coin < 0 || exp < 0 || water < 0) {
      throw ArgumentError('奖励金额不能为负数');
    }
    if (coin == 0 && exp == 0 && water == 0) return false;

    return _localDatabase.transaction((txn) async {
      final previous = await txn.query(
        'asset_record',
        columns: ['record_id'],
        where: 'action = ? AND source = ? AND source_id = ?',
        whereArgs: [action, source, sourceId],
        limit: 1,
      );
      if (previous.isNotEmpty) return false;

      await _insertPositiveLedger(
        txn, action: action, source: source, sourceId: sourceId,
        assetType: 'COIN', amount: coin,
      );
      await _insertPositiveLedger(
        txn, action: action, source: source, sourceId: sourceId,
        assetType: 'EXP', amount: exp,
      );
      await _insertPositiveLedger(
        txn, action: action, source: source, sourceId: sourceId,
        assetType: 'WATER', amount: water,
      );
      await txn.rawUpdate(
        "UPDATE user_asset SET coin = coin + ?, exp = exp + ?, water = water + ?, update_time = ? WHERE id = 1",
        [coin, exp, water, DateTime.now().toIso8601String()],
      );
      return true;
    });
  }

  Future<int> _insertPositiveLedger(
    Transaction txn, {
    required String action,
    required String source,
    required String sourceId,
    required String assetType,
    required int amount,
  }) async {
    if (amount == 0) return 0;
    return txn.rawInsert(
      '''INSERT OR IGNORE INTO asset_record
         (action, asset_type, amount, source, source_id)
         VALUES (?, ?, ?, ?, ?)''',
      [action, assetType, amount, source, sourceId],
    );
  }

  /// 使用与原项目一致的 05:00 业务日；每月 1 日连续签到重新计数。
  Future<LocalSignInResult> signIn({DateTime? now}) async {
    final instant = now ?? DateTime.now();
    final businessDate = DateTime(
      instant.year, instant.month, instant.day - (instant.hour < 5 ? 1 : 0),
    );
    final dateText = _date(businessDate);

    return _localDatabase.transaction((txn) async {
      final existing = await txn.query(
        'daily_sign_in', where: 'business_date = ?', whereArgs: [dateText], limit: 1,
      );
      if (existing.isNotEmpty) {
        final row = existing.first;
        final balance = await _balanceIn(txn);
        return LocalSignInResult(
          granted: false,
          businessDate: businessDate,
          streakDay: (row['streak_day'] as num).toInt(),
          baseWater: (row['base_water'] as num).toInt(),
          bonusWater: (row['bonus_water'] as num).toInt(),
          totalWater: (row['total_water'] as num).toInt(),
          balance: balance,
        );
      }

      var streakDay = 1;
      if (businessDate.day != 1) {
        final previous = await txn.query(
          'daily_sign_in',
          where: 'business_date = ?',
          whereArgs: [_date(businessDate.subtract(const Duration(days: 1)))],
          limit: 1,
        );
        if (previous.isNotEmpty) {
          streakDay = (previous.first['streak_day'] as num).toInt() + 1;
        }
      }

      const baseWater = 5;
      final bonusWater = switch (streakDay) {
        7 => 10,
        14 => 15,
        21 => 30,
        _ => 0,
      };
      final totalWater = baseWater + bonusWater;
      final signInId = await txn.insert('daily_sign_in', {
        'business_date': dateText,
        'streak_day': streakDay,
        'base_water': baseWater,
        'bonus_water': bonusWater,
        'total_water': totalWater,
      });

      await txn.rawUpdate(
        'UPDATE user_asset SET water = water + ?, update_time = ? WHERE id = 1',
        [totalWater, DateTime.now().toIso8601String()],
      );
      await txn.insert('asset_record', {
        'action': 'DAILY_SIGN_IN',
        'asset_type': 'WATER',
        'amount': totalWater,
        'source': 'DAILY_SIGN_IN',
        'source_id': '$signInId',
      });
      return LocalSignInResult(
        granted: true,
        businessDate: businessDate,
        streakDay: streakDay,
        baseWater: baseWater,
        bonusWater: bonusWater,
        totalWater: totalWater,
        balance: await _balanceIn(txn),
      );
    });
  }

  Future<LocalAssetBalance> _balanceIn(Transaction txn) async {
    final rows = await txn.query('user_asset', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return const LocalAssetBalance(coin: 0, exp: 0, water: 0);
    return LocalAssetBalance.fromRow(rows.first);
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

