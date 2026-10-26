import 'package:flutter/material.dart';

import '../data/today_api.dart';
import '../models/today_models.dart';

/// 「我的」一级页面。
/// 资产来自现有 /today 接口；等级与收藏系统在后续版本接入。
class MyPage extends StatefulWidget {
  const MyPage({
    super.key,
    required this.api,
    this.refreshToken = 0,
  });

  final TodayApi api;
  final int refreshToken;

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  TodayData? _data;
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

  @override
  void didUpdateWidget(covariant MyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _load() async {
    final sequence = ++_requestSequence;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.api.getToday();
      if (!mounted || sequence != _requestSequence) return;
      setState(() => _data = result);
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
    final assets = _data?.assets;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('我的'),
        backgroundColor: _background,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          children: [
            _profileCard(),
            const SizedBox(height: 20),
            _sectionTitle('我的资产', '当前账户余额'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _assetCard(
                    title: '金币',
                    value: assets == null ? '—' : '${assets.coin}',
                    icon: Icons.monetization_on_outlined,
                    color: const Color(0xFFC29442),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _assetCard(
                    title: '经验',
                    value: assets == null ? '—' : '${assets.exp}',
                    icon: Icons.bolt_rounded,
                    color: const Color(0xFF8974B5),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _assetCard(
                    title: '水滴',
                    value: assets == null ? '—' : '${assets.water}',
                    icon: Icons.water_drop_outlined,
                    color: const Color(0xFF528DB7),
                  ),
                ),
              ],
            ),
            if (_loading && _data != null) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_loading && _data == null) ...[
              const SizedBox(height: 18),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined, color: _muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '资产加载失败：$_error',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                    TextButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            _growthCard(assets?.exp),
            const SizedBox(height: 22),
            _sectionTitle('个人内容', '管理已经获得的内容与进度'),
            const SizedBox(height: 10),
            _menuCard(
              icon: Icons.collections_bookmark_outlined,
              iconColor: _forest,
              title: '我的收藏',
              subtitle: '蝴蝶图鉴与未来主题系列',
              trailingLabel: '即将开放',
              onTap: _openCollectionPreview,
            ),
            const SizedBox(height: 10),
            _menuCard(
              icon: Icons.emoji_events_outlined,
              iconColor: const Color(0xFFC29442),
              title: '成就与徽章',
              subtitle: '记录成长里程碑',
              trailingLabel: '后续接入',
              onTap: null,
            ),
            const SizedBox(height: 10),
            _menuCard(
              icon: Icons.settings_outlined,
              iconColor: _muted,
              title: '设置',
              subtitle: '应用偏好与个人设置',
              trailingLabel: '后续接入',
              onTap: null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCard() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
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
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: Colors.white.withOpacity(0.25)),
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                size: 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '我的成长档案',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    '认真完成每一天，积累自己的成长',
                    style: TextStyle(
                      color: Color(0xFFE1EBE3),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _sectionTitle(String title, String subtitle) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF26392E),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          Flexible(
            child: Text(
              subtitle,
              textAlign: TextAlign.right,
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ),
        ],
      );

  Widget _assetCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) => Container(
        padding: const EdgeInsets.fromLTRB(10, 13, 10, 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 9),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF26392E),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(title, style: const TextStyle(color: _muted, fontSize: 11)),
          ],
        ),
      );

  Widget _growthCard(int? exp) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0ECF8),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: const Color(0xFFE3DCF0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF8974B5).withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Color(0xFF8974B5)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '成长等级',
                    style: TextStyle(
                      color: Color(0xFF3D3158),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '当前累计经验：${exp ?? '—'} EXP',
                    style: const TextStyle(
                      color: Color(0xFF625579),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    '等级与盲盒解锁规则将在成长系统阶段接入，当前不显示虚构等级。',
                    style: TextStyle(
                      color: Color(0xFF756A89),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _menuCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String trailingLabel,
    required VoidCallback? onTap,
  }) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF26392E),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  trailingLabel,
                  style: TextStyle(
                    color: onTap == null ? _muted : _forest,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    color: onTap == null ? const Color(0xFFC4CBC5) : _muted),
              ],
            ),
          ),
        ),
      );

  void _openCollectionPreview() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _CollectionPreviewPage(),
      ),
    );
  }
}

class _CollectionPreviewPage extends StatelessWidget {
  const _CollectionPreviewPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF6F8F5),
        appBar: AppBar(
          title: const Text('我的收藏'),
          backgroundColor: const Color(0xFFF6F8F5),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6EEE7),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(
                    Icons.collections_bookmark_outlined,
                    size: 42,
                    color: Color(0xFF315C48),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '收藏图鉴即将开放',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  '下一阶段将接入蝴蝶盲盒与通用收藏系统。获得的收藏品会记录在用户库存中，并支持查看系列收集进度。当前版本尚未保存或展示真实收藏数据。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF78857B),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
