import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/custom_shop_api.dart';
import '../theme/app_theme.dart';

/// 商品图片保存在本机 SQLite 中，使本地备份/恢复仍能包含图片。
class CustomProductPicture extends StatelessWidget {
  const CustomProductPicture({super.key, required this.product, this.size = 64});
  final CustomProduct product;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = product.imageBase64;
    Widget child = const Icon(Icons.card_giftcard_rounded,
      color: AppColors.forest, size: 29);
    if (image != null && image.isNotEmpty) {
      try {
        child = Image.memory(base64Decode(image), fit: BoxFit.cover,
          width: size, height: size,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined));
      } catch (_) {
        child = const Icon(Icons.broken_image_outlined);
      }
    }
    return ClipRRect(borderRadius: BorderRadius.circular(12),
      child: Container(color: AppColors.paleGreen,
        width: size, height: size, alignment: Alignment.center, child: child));
  }
}

class CustomProductEditorSheet extends StatefulWidget {
  const CustomProductEditorSheet({super.key, required this.api, this.product});
  final CustomShopApi api;
  final CustomProduct? product;

  @override
  State<CustomProductEditorSheet> createState() => _CustomProductEditorSheetState();
}

class _CustomProductEditorSheetState extends State<CustomProductEditorSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController(text: '100');
  final _stock = TextEditingController(text: '1');
  String _kind = 'CONSUMABLE';
  String _category = '默认';
  List<String> _categories = [];
  String? _imageBase64;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    final product = widget.product;
    if (product == null) return;
    _name.text = product.name;
    _description.text = product.description;
    _price.text = '${product.priceCoin}';
    _stock.text = '${product.stock}';
    _kind = product.kind;
    _category = product.categoryName;
    _imageBase64 = product.imageBase64;
  }

  Future<void> _loadCategories() async {
    try {
      final result = await widget.api.getCategories();
      if (mounted) setState(() => _categories = result);
    } catch (error) {
      if (mounted) setState(() => _error = '加载种类失败：$error');
    }
  }

  Future<void> _newCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('添加商品种类'),
      content: TextField(controller: controller, maxLength: 20,
        autofocus: true, decoration: const InputDecoration(hintText: '例如：文具、运动、零食')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('添加')),
      ],
    ));
    controller.dispose();
    if (name == null || !mounted) return;
    try {
      await widget.api.createCategory(name);
      await _loadCategories();
      if (mounted) setState(() { _category = name; _error = null; });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _name.dispose(); _description.dispose(); _price.dispose(); _stock.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 600, maxHeight: 600, imageQuality: 75,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 1024 * 1024) {
        if (mounted) setState(() => _error = '图片超过 1 MB，请选择更小的图片');
        return;
      }
      if (mounted) setState(() {
        _imageBase64 = base64Encode(bytes);
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '选择图片失败：$error');
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = int.tryParse(_price.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    if (name.isEmpty || name.length > 50 || price == null || stock == null ||
        price < 0 || stock < 0) {
      setState(() => _error = '名称必填（最多50字）；售价、库存需为非负整数');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.api.saveProduct(
        productId: widget.product?.id,
        name: name, description: _description.text.trim(),
        imageBase64: _imageBase64, priceCoin: price, stock: stock,
        kind: _kind, categoryName: _category);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.product != null;
    return SafeArea(child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(editing ? '编辑商品' : '新建商品',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(children: [
            if (_imageBase64 != null)
              ClipRRect(borderRadius: BorderRadius.circular(12),
                child: Image.memory(base64Decode(_imageBase64!),
                  width: 78, height: 78, fit: BoxFit.cover)),
            if (_imageBase64 == null)
              const SizedBox(width: 78, height: 78,
                child: Icon(Icons.image_outlined, size: 50, color: AppColors.muted)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickImage,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('选择图片')),
              if (_imageBase64 != null)
                TextButton(onPressed: _saving ? null : () => setState(() => _imageBase64 = null),
                  child: const Text('移除图片')),
            ])),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _name, maxLength: 50,
            decoration: const InputDecoration(labelText: '商品名称 *')),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '售价（金币） *'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _stock,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '库存 *'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _description, maxLength: 500, maxLines: 3,
            decoration: const InputDecoration(labelText: '商品描述')),
          const SizedBox(height: 8),
          Row(children: [
            const Text('商品种类', style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton.icon(onPressed: _saving ? null : _newCategory,
              icon: const Icon(Icons.add_rounded, size: 18), label: const Text('新增种类')),
          ]),
          Wrap(spacing: 7, children: [
            for (final category in ['默认', ..._categories])
              ChoiceChip(label: Text(category), showCheckmark: false,
                selected: _category == category,
                onSelected: (_) => setState(() => _category = category)),
          ]),
          const SizedBox(height: 12),
          const Text('使用属性', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Wrap(spacing: 8, children: [
            ChoiceChip(showCheckmark: false, label: const Text('消耗品'),
              selected: _kind == 'CONSUMABLE',
              onSelected: (_) => setState(() => _kind = 'CONSUMABLE')),
            ChoiceChip(showCheckmark: false, label: const Text('收藏品'),
              selected: _kind == 'COLLECTIBLE',
              onSelected: (_) => setState(() => _kind = 'COLLECTIBLE')),
          ]),
          const Text('消耗品购买后可以在仓库使用；收藏品永久保留。',
            style: TextStyle(fontSize: 11, color: AppColors.muted)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: AppColors.rose))),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : (editing ? '保存商品' : '创建商品')))),
        ]),
    ));
  }
}

class CustomWarehousePage extends StatefulWidget {
  const CustomWarehousePage({super.key, required this.api});
  final CustomShopApi api;

  @override
  State<CustomWarehousePage> createState() => _CustomWarehousePageState();
}

class _CustomWarehousePageState extends State<CustomWarehousePage> {
  bool _loading = true;
  String? _error;
  List<WarehouseItem> _items = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.api.getWarehouse();
      if (mounted) setState(() => _items = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _use(WarehouseItem item) async {
    final approved = await showDialog<bool>(context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用消耗品？'),
        content: Text('使用「${item.product.name}」将消耗仓库中的 1 个。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('确认使用')),
        ]));
    if (approved != true || !mounted) return;
    try {
      await widget.api.consume(item.product.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已使用「${item.product.name}」')));
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('使用失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的仓库'), actions: [
      IconButton(onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh_rounded), tooltip: '刷新仓库'),
    ]),
    body: RefreshIndicator(onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(), children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text('加载失败：$_error',
            style: const TextStyle(color: AppColors.rose)),
          if (_items.isEmpty && !_loading)
            const Padding(padding: EdgeInsets.only(top: 60),
              child: Center(child: Text('仓库还是空的，去商店看看吧'))),
          for (final item in _items)
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
              CustomProductPicture(product: item.product),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.product.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('持有 ${item.quantity} · ${item.product.kind == 'CONSUMABLE' ? '消耗品' : '收藏品'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ])),
              if (item.product.kind == 'CONSUMABLE')
                FilledButton.tonal(onPressed: () => _use(item),
                  child: const Text('使用')),
            ]))),
        ])),
  );
}
