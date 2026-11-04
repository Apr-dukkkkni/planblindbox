import 'package:flutter/material.dart';

import '../data/shop_api.dart';
import '../data/collection_api.dart';
import '../data/today_api.dart';
import '../data/custom_shop_api.dart';
import '../data/api_exception.dart';
import 'custom_shop_pages.dart';
import '../data/local/collectible_assets.dart';
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
  late CustomShopApi _customShopApi;
  List<CustomProduct> _customProducts = [];
  String _customFilter = '全部';
  List<String> _categories = [];
  bool _loadingCustom = true;
  bool _buyingCustom = false;
  int? _buyingCustomProductId;
  String? _pendingCustomRequestId;
  int? _pendingCustomProductId;
  String? _customError;
  List<ShopBox> _boxes = [];
  List<ShopOpen> _history = [];
  ShopBalance? _balance;
  String? _error;
  bool _loading = true;
  bool _opening = false;
  int? _openingBoxId;

  // 保留请求编号，避免用户连续点击时重复扣款。
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
    _customShopApi = CustomShopApi(userId: widget.api.userId);
    _load();
    _loadCustom();
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
      _customShopApi = CustomShopApi(userId: widget.api.userId);
      _customProducts = [];
      _pendingCustomRequestId = null;
      _pendingCustomProductId = null;
      _loadCustom();
      _pendingRequestId = null;
      _pendingBoxId = null;
      _load();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
      _loadCustom();
    }
  }

  @override
  void dispose() {
    _shopApi.dispose();
    _collectionApi.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait<void>([_load(), _loadCustom()]);
  }

  Future<void> _loadCustom() async {
    if (!mounted) return;
    setState(() { _loadingCustom = true; _customError = null; });
    try {
      final results = await Future.wait<dynamic>([
        _customShopApi.getProducts(), _customShopApi.getCategories(),
      ]);
      if (mounted) setState(() {
        _customProducts = results[0] as List<CustomProduct>;
        _categories = results[1] as List<String>;
        if (_customFilter != '全部' && _customFilter != '默认' &&
            !_categories.contains(_customFilter)) _customFilter = '全部';
      });
    } catch (error) {
      if (mounted) setState(() => _customError = '$error');
    } finally {
      if (mounted) setState(() => _loadingCustom = false);
    }
  }

  Future<void> _openCustomEditor([CustomProduct? product]) async {
    final changed = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => CustomProductEditorSheet(api: _customShopApi, product: product));
    if (changed == true && mounted) {
      _showMessage(product == null ? '商品创建成功' : '商品已更新');
      await _loadCustom();
    }
  }

  Future<void> _openWarehouse() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => CustomWarehousePage(api: _customShopApi)));
    if (mounted) await _loadCustom();
  }

  void _openHistory() {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('开盒记录')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (_history.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 72),
              child: Center(child: Text('暂无开盒记录'))),
          for (final item in _history)
            Card(child: ListTile(
              leading: const Icon(Icons.redeem_rounded, color: AppColors.forest),
              title: Text(item.boxName),
              subtitle: Text(item.rewardType == 'COLLECTIBLE' && item.itemName != null
                ? '收藏品：${item.itemName} · ${_rarityLabel(item.itemRarity ?? '')}'
                : '获得 +${item.rewardAmount} ${_assetLabel(item.rewardType)}'),
              trailing: Text('-${item.priceCoin} 金币'),
            )),
        ]),
      ),
    ));
  }

  Future<void> _archiveCustom(CustomProduct product) async {
    final confirm = await showDialog<bool>(context: context,
      builder: (context) => AlertDialog(
        title: const Text('下架商品？'),
        content: Text('「${product.name}」将从商店隐藏。已购买的物品继续保留在仓库。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('确认下架')),
        ]));
    if (confirm != true || !mounted) return;
    try {
      await _customShopApi.archive(product.id);
      if (!mounted) return;
      _showMessage('商品已下架');
      await _loadCustom();
    } catch (error) {
      _showMessage('下架失败：$error');
    }
  }

  Future<void> _purchaseCustom(CustomProduct product) async {
    if (_buyingCustom || _loadingCustom) return;
    if (_pendingCustomRequestId != null && _pendingCustomProductId != product.id) {
      _showMessage('还有一笔购买结果未确认，请先重试原商品');
      return;
    }
    final confirm = await showDialog<bool>(context: context,
      builder: (context) => AlertDialog(
        title: Text('购买「${product.name}」？'),
        content: Text('花费 ${product.priceCoin} 金币购买 1 个。'
          '${_pendingCustomRequestId != null ? '（重试使用原购买编号，不会重复扣款）' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('确认购买')),
        ]));
    if (confirm != true || !mounted) return;
    final requestId = _pendingCustomRequestId ?? newShopRequestId();
    setState(() {
      _buyingCustom = true;
      _buyingCustomProductId = product.id;
      _pendingCustomRequestId = requestId;
      _pendingCustomProductId = product.id;
    });
    try {
      final result = await _customShopApi.purchase(
        productId: product.id, requestId: requestId);
      if (!mounted) return;
      setState(() {
        _pendingCustomRequestId = null;
        _pendingCustomProductId = null;
      });
      _showMessage(result.alreadyProcessed ? '这笔订单已经完成，未重复扣款' : '购买成功，已放入仓库');
      await _refreshAll();
    } on ApiException catch (error) {
      // 确定性业务错误（扣款事务已回滚）可安全清除 pending 状态。
      if (mounted && (error.statusCode == 409 || error.statusCode == 404 ||
          error.statusCode == 400)) {
        setState(() { _pendingCustomRequestId = null; _pendingCustomProductId = null; });
      }
      _showMessage('购买失败：$error');
    } catch (error) {
      _showMessage('购买结果尚未确认：$error。重试该商品时会复用请求编号');
    } finally {
      if (mounted) setState(() { _buyingCustom = false; _buyingCustomProductId = null; });
    }
  }

  Future<void> _manageCategories() async {
    await showDialog<void>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (context, updateDialog) => AlertDialog(
        title: const Text('管理商品种类'),
        content: SizedBox(width: 320, child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            if (_categories.isEmpty) const Text('暂无自定义种类，使用「默认」'),
            for (final category in _categories)
              ListTile(dense: true, title: Text(category),
                trailing: IconButton(icon: const Icon(Icons.delete_outline),
                  tooltip: '删除种类并归入默认', onPressed: () async {
                    try {
                      await _customShopApi.deleteCategory(category);
                      await _loadCustom();
                      if (dialogContext.mounted) updateDialog(() {});
                    } catch (error) {
                      _showMessage('删除种类失败：$error');
                    }
                  })),
            TextButton.icon(
              icon: const Icon(Icons.add_rounded), label: const Text('新建种类'),
              onPressed: () async {
                final controller = TextEditingController();
                final name = await showDialog<String>(context: dialogContext,
                  builder: (context) => AlertDialog(
                    title: const Text('新建商品种类'),
                    content: TextField(controller: controller, maxLength: 20,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: '例如：文具、零食')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                      FilledButton(onPressed: () => Navigator.pop(context, controller.text),
                        child: const Text('保存')),
                    ],
                  ),
                );
                controller.dispose();
                if (name == null) return;
                try {
                  await _customShopApi.createCategory(name);
                  await _loadCustom();
                  if (dialogContext.mounted) updateDialog(() {});
                } catch (error) {
                  _showMessage('新增种类失败：$error');
                }
              },
            ),
          ])),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
          child: const Text('完成'))],
      )),
    );
  }

  Widget _customTile(CustomProduct product) => SurfaceCard(
    child: Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CustomProductPicture(product: product, size: 64),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(product.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(product.description.isEmpty ? '暂无描述' : product.description,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 4),
          Text('${product.priceCoin} 金币 · 库存 ${product.stock} · '
               '${product.categoryName} · ${product.kind == 'CONSUMABLE' ? '可使用' : '收藏品'}',
            style: const TextStyle(fontSize: 12, color: AppColors.forest)),
        ])),
        PopupMenuButton<String>(tooltip: '管理商品',
          onSelected: (choice) {
            if (choice == 'edit') _openCustomEditor(product);
            if (choice == 'archive') _archiveCustom(product);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑商品')),
            PopupMenuItem(value: 'archive', child: Text('下架商品')),
          ]),
      ]),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: FilledButton.tonalIcon(
        onPressed: product.stock > 0 && !_buyingCustom
          ? () => _purchaseCustom(product) : null,
        icon: const Icon(Icons.shopping_bag_outlined, size: 18),
        label: Text(_buyingCustom && _buyingCustomProductId == product.id
          ? '购买中…' : product.stock <= 0 ? '已售罄' : '购买'),
      )),
    ]),
  );

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
      // 查询失败时保留原 requestId。
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
            : '本次需要消耗 ${box.priceCoin} 金币，奖励由本地奖励池随机决定。'),
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
      // 如果本地提交结果未返回，先核对本地开盒历史。
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
      // 查询本地库存，用于区分首次解锁和重复获得。
      // 查询失败不影响已成功的开盒，只降级显示通用收藏提示。
      final ownedCount = await _getOwnedCountAfter(result)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (!mounted) return;

      final isDuplicate =
          ownedCount != null && ownedCount > result.rewardAmount;
      final imagePath = result.itemImagePath;
      final imageAsset = collectibleAssetPath(imagePath);

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
                  if (imageAsset.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        width: 190,
                        height: 190,
                        child: Image.asset(
                          imageAsset,
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
                        color: _rarityColor(result.itemRarity!).withValues(alpha: 0.12),
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
            onPressed: _openHistory,
            tooltip: '开盒记录',
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            onPressed: _loading || _opening ? null : _refreshAll,
            tooltip: '刷新商店',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.small(
          heroTag: 'custom-shop-warehouse', tooltip: '仓库',
          onPressed: _openWarehouse,
          child: const Icon(Icons.inventory_2_outlined),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'custom-shop-create', tooltip: '新建商品',
          onPressed: () => _openCustomEditor(),
          child: const Icon(Icons.add_rounded),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 125),
          children: [
            Row(children: [
              const Expanded(child: Text('商品', style: TextStyle(
                fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.ink))),
              const Icon(Icons.monetization_on_rounded, color: AppColors.amber, size: 22),
              const SizedBox(width: 5),
              Text('${_balance?.coin ?? '—'}', style: const TextStyle(
                color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 9),
            Row(children: [
              const Expanded(child: Text('商品种类',
                style: TextStyle(fontSize: 12, color: AppColors.muted))),
              TextButton.icon(onPressed: _manageCategories,
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const Text('管理种类')),
            ]),
            SingleChildScrollView(scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final category in ['全部', '默认', ..._categories])
                  Padding(padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(showCheckmark: false, label: Text(category),
                      selected: _customFilter == category,
                      onSelected: (_) => setState(() => _customFilter = category))),
              ])),
            if (_loading && _balance == null)
              const LinearProgressIndicator(),
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
            const SizedBox(height: 14),
            if (_loadingCustom) const LinearProgressIndicator(),
            if (_customError != null)
              Text('商品加载失败：$_customError',
                style: const TextStyle(color: AppColors.rose)),
            if (_boxes.isEmpty && _customProducts.isEmpty && !_loading && !_loadingCustom)
              const SurfaceCard(child: Text('暂无商品，点击右下角 + 创建')),
            // 盲盒与自定义商品共用「商品」分区；种类是用户自定义筛选，
            // 消耗品/收藏品仅表示购买后能否使用，不作为种类。
            if (_customFilter == '全部' || _customFilter == '默认')
              for (final box in _boxes) ...[
                _boxTile(box),
                const SizedBox(height: 11),
              ],
            for (final product in _customProducts)
              if (_customFilter == '全部' || product.categoryName == _customFilter) ...[
                _customTile(product),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
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
