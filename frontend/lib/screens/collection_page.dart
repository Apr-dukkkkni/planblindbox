import 'package:flutter/material.dart';

import '../data/collection_api.dart';
import '../data/today_api.dart';

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key, required this.api});

  final TodayApi api;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  late final CollectionApi _collectionApi;
  List<CollectionPack> _packs = const [];
  bool _loading = true;
  String? _error;
  bool _usingBuiltInButterflyEntry = false;
  int _requestSequence = 0;

  static const Color _background = Color(0xFFF6F8F5);
  static const Color _forest = Color(0xFF315C48);
  static const Color _muted = Color(0xFF78857B);
  static const Color _border = Color(0xFFE3E9E2);

  @override
  void initState() {
    super.initState();
    _collectionApi = CollectionApi(
      baseUrl: widget.api.baseUrl,
      userId: widget.api.userId,
    );
    _load();
  }

  @override
  void dispose() {
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
      final packs = await _collectionApi.getPacks();
      if (!mounted || sequence != _requestSequence) return;

      // 后端已确认存在 butterfly-pack（packId=1）。
      // 如果列表接口意外返回空数组，仍展示该系列入口；
      // 具体 12 张藏品仍通过 /collection/packs/1/items 从后端读取。
      final visiblePacks = packs.isEmpty
          ? const [
              CollectionPack(
                id: 1,
                key: 'butterfly-pack',
                name: '蝴蝶图鉴',
                description: '以不同艺术风格呈现的蝴蝶收藏系列。',
                version: '1.0.0',
                unlockLevel: 1,
                totalItems: 12,
                ownedItems: 0,
              ),
            ]
          : packs;

      setState(() {
        _packs = visiblePacks;
        _usingBuiltInButterflyEntry = packs.isEmpty;
      });
    } catch (error) {
      if (!mounted || sequence != _requestSequence) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted && sequence == _requestSequence) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalOwned = _packs.fold<int>(0, (sum, pack) => sum + pack.ownedItems);
    final totalItems = _packs.fold<int>(0, (sum, pack) => sum + pack.totalItems);

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('我的收藏'),
        backgroundColor: _background,
        actions: [
          IconButton(
            tooltip: '刷新收藏',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            _summaryCard(totalOwned: totalOwned, totalItems: totalItems),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '主题图鉴',
                    style: TextStyle(
                      color: Color(0xFF26392E),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${_packs.length} 个系列',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_usingBuiltInButterflyEntry)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEAD8A6)),
                ),
                child: const Text(
                  '已显示蝴蝶图鉴入口；系列列表接口暂未返回内容，点开后仍会读取服务器中的真实藏品数据。',
                  style: TextStyle(
                    color: Color(0xFF80652D),
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ),
            if (_loading && _packs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 50),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              _messageCard(
                icon: Icons.cloud_off_outlined,
                title: '收藏数据加载失败',
                detail: _error!,
                action: TextButton(onPressed: _load, child: const Text('重试')),
              ),
            if (!_loading && _error == null && _packs.isEmpty)
              _messageCard(
                icon: Icons.collections_bookmark_outlined,
                title: '还没有开放的收藏系列',
                detail: '主题内容上线后，会在这里展示图鉴与收集进度。',
              ),
            for (final pack in _packs) ...[
              _packCard(pack),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            const Text(
              '不同主题独立成册。后续可继续加入植物、矿物或其他收藏系列。',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard({required int totalOwned, required int totalItems}) {
    final progress = totalItems <= 0
        ? 0.0
        : (totalOwned / totalItems).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF315C48), Color(0xFF527C63)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18315C48),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Color(0xFFEAD8A6)),
              SizedBox(width: 8),
              Text(
                '我的收藏档案',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$totalOwned',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '/ $totalItems 种已发现',
                  style: const TextStyle(
                    color: Color(0xFFE1EBE3),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFEAD8A6)),
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            '每一次发现，都是成长路上的小小纪念。',
            style: TextStyle(color: Color(0xFFE1EBE3), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _packCard(CollectionPack pack) {
    final isButterfly = pack.key.toLowerCase().contains('butterfly');
    final icon = isButterfly ? Icons.flutter_dash : Icons.auto_awesome;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        borderRadius: BorderRadius.circular(19),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CollectionPackPage(
                api: _collectionApi,
                pack: pack,
              ),
            ),
          );
          if (mounted) await _load();
        },
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 82,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1E9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: _forest, size: 36),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF26392E),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      pack.description.isEmpty ? '收集这个主题中的全部藏品' : pack.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: pack.progress,
                              minHeight: 5,
                              backgroundColor: const Color(0xFFE8EDE8),
                              valueColor:
                                  const AlwaysStoppedAnimation(_forest),
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          '${pack.ownedItems}/${pack.totalItems}',
                          style: const TextStyle(
                            color: _forest,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageCard({
    required IconData icon,
    required String title,
    required String detail,
    Widget? action,
  }) =>
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: _muted),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
            ),
            if (action != null) ...[const SizedBox(height: 8), action],
          ],
        ),
      );
}

class CollectionPackPage extends StatefulWidget {
  const CollectionPackPage({
    super.key,
    required this.api,
    required this.pack,
  });

  final CollectionApi api;
  final CollectionPack pack;

  @override
  State<CollectionPackPage> createState() => _CollectionPackPageState();
}

class _CollectionPackPageState extends State<CollectionPackPage> {
  List<CollectionItem> _items = const [];
  bool _loading = true;
  String? _error;
  int _requestSequence = 0;

  static const Color _background = Color(0xFFF6F8F5);
  static const Color _forest = Color(0xFF315C48);
  static const Color _muted = Color(0xFF78857B);
  static const Color _border = Color(0xFFE3E9E2);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sequence = ++_requestSequence;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.getItems(widget.pack.id);
      if (!mounted || sequence != _requestSequence) return;
      setState(() => _items = items);
    } catch (error) {
      if (!mounted || sequence != _requestSequence) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted && sequence == _requestSequence) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final owned = _items.where((item) => item.owned).length;
    final total = _items.length;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: Text(widget.pack.name),
        backgroundColor: _background,
        actions: [
          IconButton(
            tooltip: '刷新图鉴',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.collections_bookmark_outlined,
                          color: _forest, size: 27),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '主题收集进度',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF26392E),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$owned / ${_loading && _items.isEmpty ? widget.pack.totalItems : total} 种已发现',
                              style: const TextStyle(
                                  color: _muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        total == 0 ? '0%' : '${(owned / total * 100).round()}%',
                        style: const TextStyle(
                          color: _forest,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_loading && _items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined,
                            color: _muted, size: 36),
                        const SizedBox(height: 10),
                        const Text('图鉴加载失败'),
                        const SizedBox(height: 6),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: _muted, fontSize: 12),
                        ),
                        TextButton(onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  ),
                ),
              ),
            if (!_loading && _error == null && _items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('这个系列暂时没有收藏品')),
              ),
            if (_items.isNotEmpty && _error == null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 26),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _itemCard(_items[index]),
                    childCount: _items.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.69,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(CollectionItem item) {
    final rarity = _rarityColor(item.rarity);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showItem(item),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _itemImage(item.imagePath),
                    if (!item.owned)
                      Container(
                        color: const Color(0xB8202922),
                        child: const Center(
                          child: Icon(
                            Icons.lock_outline_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                    if (item.owned && item.ownedCount > 1)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '×${item.ownedCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.owned ? item.name : '未发现的收藏品',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF26392E),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: item.owned ? rarity : const Color(0xFFB7BDB8),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            item.owned ? _rarityLabel(item.rarity) : '尚未收集',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: item.owned ? rarity : _muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemImage(String imagePath) {
    if (imagePath.isEmpty) {
      return const ColoredBox(
        color: Color(0xFFE8EDE8),
        child: Center(
          child: Icon(Icons.image_not_supported_outlined,
              color: _muted, size: 34),
        ),
      );
    }
    final base = Uri.parse(widget.api.baseUrl);
    final imageUri = base.resolve(imagePath);
    return Image.network(
      imageUri.toString(),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Color(0xFFE8EDE8),
        child: Center(
          child: Icon(Icons.image_not_supported_outlined,
              color: _muted, size: 34),
        ),
      ),
    );
  }

  void _showItem(CollectionItem item) {
    final rarity = _rarityColor(item.rarity);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _background,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _itemImage(item.imagePath),
                        if (!item.owned)
                          Container(
                            color: const Color(0xB8202922),
                            child: const Center(
                              child: Icon(Icons.lock_outline_rounded,
                                  color: Colors.white, size: 46),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 17),
                Text(
                  item.owned ? item.name : '尚未发现',
                  style: const TextStyle(
                    color: Color(0xFF26392E),
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (item.owned ? rarity : _muted).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    item.owned ? _rarityLabel(item.rarity) : '未收集',
                    style: TextStyle(
                      color: item.owned ? rarity : _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  item.owned
                      ? (item.description.isEmpty ? '暂无描述。' : item.description)
                      : '在对应主题盲盒中获得这件收藏品后，就能解锁完整图鉴。',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                if (item.owned) ...[
                  const SizedBox(height: 14),
                  Text(
                    '拥有数量：${item.ownedCount}',
                    style: const TextStyle(
                      color: _forest,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
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
        return const Color(0xFF6F8974);
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
      default:
        return '普通';
    }
  }
}
