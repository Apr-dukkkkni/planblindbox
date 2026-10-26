import 'package:flutter/material.dart';

import '../data/shop_api.dart';
import '../data/collection_api.dart';
import '../data/today_api.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_cards.dart';

/// 商店是 AppShell 的一级页面，与「今日」「任务库」平级。
class StorePage extends StatefulWidget {
  const StorePage({
    super.key,
    required this.api,
    this.refreshToken = 0,
  });

  final TodayApi api;
  final int refreshToken;

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  late ShopApi _shopApi;
  late CollectionApi _collectionApi;
  List<ShopBox> _boxes = [];
  List<ShopOpen> _history = [];
  ShopBalance? _balance;
  String? _error;
  bool _loading = true;
  bool _opening = false;
  int? _openingBoxId;

  // 网络错误可能发生在服务器提交事务之后。
  // 因此必须保留 requestId，绝不能在不确定结果时立即生成新的购买请求。
  String? _pendingRequestId;
  int? _pendingBoxId;
  int _requestSequence = 0;

  @override
  void initState() {
    super.initState();
    _shopApi = ShopApi(baseUrl: widget.api.baseUrl, userId: widget.api.userId);
    _collectionApi =
        CollectionApi(baseUrl: widget.api.baseUrl, userId: widget.api.userId);
    _load();
  }

  @override
  void didUpdateWidget(covariant StorePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      _shopApi.dispose();
      _collectionApi.dispose();
      _shopApi = ShopApi(baseUrl: widget.api.baseUrl, userId: widget.api.userId);
      _collectionApi =
          CollectionApi(baseUrl: widget.api.baseUrl, userId: widget.api.userId);
      _pendingRequestId = null;
      _pendingBoxId = null;
      _load();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  @override
  void dispose() {
    _shopApi.dispose();
    _collectionApi.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sequence = ++_requestSequence;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boxes = await _shopApi.getBoxes();
      final balance = await _shopApi.getBalance();
      final history = await _shopApi.getHistory();
      if (!mounted || sequence != _requestSequence) return;
      setState(() {
        _boxes = boxes;
        _balance = balance;
        _history = history;
      });
      _clearPendingIfInHistory(history);
    } catch (error) {
      if (!mounted || sequence != _requestSequence) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted && sequence == _requestSequence) {
        setState(() => _loading = false);
      }
    }
  }

  void _clearPendingIfInHistory(List<ShopOpen> history) {
    final requestId = _pendingRequestId;
    if (requestId == null) return;
    for (final item in history) {
      if (item.requestId == requestId) {
        _pendingRequestId = null;
        _pendingBoxId = null;
        return;
      }
    }
  }

  Future<ShopOpen?> _findPendingResult() async {
    final requestId = _pendingRequestId;
    if (requestId == null) return null;
    try {
      final history = await _shopApi.getHistory(limit: 100);
      if (!mounted) return null;
      for (final item in history) {
        if (item.requestId == requestId) {
          setState(() {
            _pendingRequestId = null;
            _pendingBoxId = null;
          });
          return item;
        }
      }
    } catch (_) {
      // 网络仍不可用时保留原 requestId。
    }
    return null;
  }

  Future<void> _openBox(ShopBox box) async {
    if (_opening || _loading) return;
    if (_pendingRequestId != null && _pendingBoxId != box.id) {
      _showMessage('上次开盒结果尚未确认，请先在原商品上重试或核对历史。');
      return;
    }
    if (_pendingRequestId == null &&
        _balance != null &&
        _balance!.coin < box.priceCoin) {
      _showMessage('金币不足，当前余额 ${_balance!.coin}，需要 ${box.priceCoin}。');
      return;
    }

    final isRetry = _pendingRequestId != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isRetry ? '重试上次开盒' : '确认开启${box.name}'),
        content: Text(isRetry
            ? '将使用相同请求编号再次查询/提交，不会创建新的一笔购买。'
            : '本次需要消耗 ${box.priceCoin} 金币，奖励由服务器随机决定。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isRetry ? '重试原请求' : '确认开盒'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final requestId = _pendingRequestId ?? newShopRequestId();
    setState(() {
      _opening = true;
      _openingBoxId = box.id;
      _pendingRequestId = requestId;
      _pendingBoxId = box.id;
    });

    ShopOpen? result;
    String? failureMessage;
    try {
      result = await _shopApi.openBox(boxId: box.id, requestId: requestId);
      if (!mounted) return;
      setState(() {
        _pendingRequestId = null;
        _pendingBoxId = null;
        _balance = result!.balance;
      });
    } catch (error) {
      failureMessage = error.toString();
      // 即使 POST 返回异常，事务也可能已成功提交；先核对最近记录。
      result = await _findPendingResult();
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
          _openingBoxId = null;
        });
      }
    }
    if (!mounted) return;
    if (result != null) {
      await _load();
      if (!mounted) return;
      await _showReward(result);
    } else {
      _showMessage('开盒结果未确认：${failureMessage ?? '请求异常'}。'
          '再次点击同一商品会复用请求编号，请勿创建新的购买。');
    }
  }

  Future<void> _showReward(ShopOpen result) async {
    if (result.rewardType == 'COLLECTIBLE' && result.itemName != null) {
      // 查询发奖后的真实库存，用于区分首次解锁和重复获得。
      // 查询失败不影响已成功的开盒，只降级显示通用收藏提示。
      final ownedCount = await _getOwnedCountAfter(result)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (!mounted) return;

      final isDuplicate =
          ownedCount != null && ownedCount > result.rewardAmount;
      final imagePath = result.itemImagePath;
      final imageUrl = imagePath == null || imagePath.isEmpty
          ? null
          : Uri.parse(_shopApi.baseUrl).resolve(imagePath).toString();

      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      color: isDuplicate
                          ? const Color(0xFFFFF2D7)
                          : AppColors.paleGreen,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isDuplicate
                          ? Icons.collections_bookmark_rounded
                          : Icons.auto_awesome_rounded,
                      color: isDuplicate
                          ? const Color(0xFFB07B27)
                          : AppColors.forest,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    ownedCount == null
                        ? '收藏品获得成功！'
                        : isDuplicate
                            ? '重复获得！'
                            : '新收藏解锁！',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 15),
                  if (imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        width: 190,
                        height: 190,
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.paleGreen,
                            child: const Icon(
                              Icons.image_not_supported_outlined,
                              color: AppColors.forest,
                              size: 44,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        color: AppColors.paleGreen,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.collections_bookmark_outlined,
                        color: AppColors.forest,
                        size: 48,
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text(
                    result.itemName!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  if (result.itemRarity != null &&
                      result.itemRarity!.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: _rarityColor(result.itemRarity!).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _rarityLabel(result.itemRarity!),
                        style: TextStyle(
                          color: _rarityColor(result.itemRarity!),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  if (result.itemDescription != null &&
                      result.itemDescription!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      result.itemDescription!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 13),
                  if (ownedCount != null)
                    Text(
                      isDuplicate
                          ? '重复获得 · 当前拥有 $ownedCount 份'
                          : '已加入我的收藏 · 当前拥有 $ownedCount 份',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.forest,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    )
                  else
                    const Text(
                      '奖励已入库，可前往「我的收藏」查看。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.forest,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 11),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('本次消耗',
                          style: TextStyle(color: AppColors.muted)),
                      Text('${result.priceCoin} 金币',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('剩余金币',
                          style: TextStyle(color: AppColors.muted)),
                      Text('${result.balance.coin}',
                          style: const TextStyle(
                            color: AppColors.forest,
                            fontWeight: FontWeight.w900,
                          )),
                    ],
                  ),
                  const SizedBox(height: 17),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('收下奖励'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('开盒成功！'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.card_giftcard_rounded,
                size: 58, color: AppColors.forest),
            const SizedBox(height: 12),
            Text(result.boxName,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 9),
            Text('+${result.rewardAmount} ${_assetLabel(result.rewardType)}',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.forest)),
            const SizedBox(height: 8),
            Text('本次消耗 ${result.priceCoin} 金币'),
            Text('剩余金币 ${result.balance.coin}'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('收下奖励'),
          ),
        ],
      ),
    );
  }

  Future<int?> _getOwnedCountAfter(ShopOpen result) async {
    final itemId = result.itemId;
    if (itemId == null) return null;
    try {
      final packs = await _collectionApi.getPacks();
      for (final pack in packs) {
        final items = await _collectionApi.getItems(pack.id);
        for (final item in items) {
          if (item.id == itemId) return item.ownedCount;
        }
      }
    } catch (_) {
      // 开盒已经成功，库存查询失败不能把成功结果变成失败。
    }
    return null;
  }

  Color _rarityColor(String rarity) {
    switch (rarity.toUpperCase()) {
      case 'RARE':
        return const Color(0xFF4386C6);
      case 'EPIC':
        return const Color(0xFF8974B5);
      case 'LEGENDARY':
        return const Color(0xFFC29442);
      default:
        return AppColors.forest;
    }
  }

  String _rarityLabel(String rarity) {
    switch (rarity.toUpperCase()) {
      case 'RARE':
        return '稀有';
      case 'EPIC':
        return '史诗';
      case 'LEGENDARY':
        return '传说';
      case 'UNCOMMON':
        return '优秀';
      default:
        return '普通';
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('商店'),
        actions: [
          IconButton(
            onPressed: _loading || _opening ? null : _load,
            tooltip: '刷新商店',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            const Text('把今天的努力，兑换成一点惊喜。',
                style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            if (_loading && _balance == null)
              const Center(child: CircularProgressIndicator())
            else if (_balance != null)
              _balancePanel(_balance!),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text('刷新失败：$_error',
                  style: const TextStyle(color: AppColors.rose)),
            ],
            if (_pendingRequestId != null) ...[
              const SizedBox(height: 12),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('有一笔尚未确认的开盒请求',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('请先核对历史，或再次点击原商品重试。'
                        '不会为该次重试生成新的请求编号。'),
                    TextButton(
                      onPressed: _opening ? null : _load,
                      child: const Text('刷新历史并核对'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 27),
            const Text('盲盒',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
            const SizedBox(height: 12),
            if (_boxes.isEmpty && !_loading && _error == null)
              const SurfaceCard(child: Text('暂无上架商品')),
            for (final box in _boxes) ...[
              _boxTile(box),
              const SizedBox(height: 11),
            ],
            const SizedBox(height: 20),
            const Text('最近开盒记录',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
            const SizedBox(height: 10),
            if (_history.isEmpty && !_loading)
              const SurfaceCard(child: Text('还没有开盒记录')),
            for (final item in _history) ...[
              SurfaceCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Icon(Icons.redeem_outlined, color: AppColors.forest),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.boxName,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          item.rewardType == 'COLLECTIBLE' &&
                                  item.itemName != null
                              ? '收藏品：${item.itemName} · ${_rarityLabel(item.itemRarity ?? '')}'
                              : '获得 +${item.rewardAmount} ${_assetLabel(item.rewardType)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text('-${item.priceCoin} 金币',
                      style: const TextStyle(color: AppColors.muted)),
                ]),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _balancePanel(ShopBalance balance) {
    return SurfaceCard(
      child: Row(children: [
        Expanded(child: _assetItem(Icons.monetization_on_outlined,
            '金币', '${balance.coin}')),
        Expanded(child: _assetItem(Icons.bolt_outlined,
            '经验', '${balance.exp}')),
        Expanded(child: _assetItem(Icons.water_drop_outlined,
            '水滴', '${balance.water}')),
      ]),
    );
  }

  Widget _assetItem(IconData icon, String label, String value) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: AppColors.forest),
      const SizedBox(height: 7),
      Text(value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      Text(label,
          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
    ]);
  }

  Widget _boxTile(ShopBox box) {
    final blockedByAnotherPending =
        _pendingRequestId != null && _pendingBoxId != box.id;
    final canAfford = _balance != null && _balance!.coin >= box.priceCoin;
    final enabled = !_opening && !_loading && !blockedByAnotherPending &&
        (canAfford || _pendingBoxId == box.id);
    final isRetry = _pendingRequestId != null && _pendingBoxId == box.id;
    return SurfaceCard(
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.paleGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.inventory_2_outlined,
              color: AppColors.forest, size: 29),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(box.name,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(box.description,
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            Text('${box.priceCoin} 金币 / 次',
                style: const TextStyle(color: AppColors.forest, fontSize: 12)),
          ],
        )),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: enabled ? () => _openBox(box) : null,
          child: Text(_opening && _openingBoxId == box.id
              ? '开盒中'
              : isRetry
                  ? '重试'
                  : '开启'),
        ),
      ]),
    );
  }
}

String _assetLabel(String type) {
  switch (type) {
    case 'COIN':
      return '金币';
    case 'EXP':
      return '经验';
    case 'WATER':
      return '水滴';
    default:
      return type;
  }
}
