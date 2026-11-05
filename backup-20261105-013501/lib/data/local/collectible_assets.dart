/// 数据库存储的 image_path 仍沿用后端路径格式；本地 UI 映射到 Flutter assets。
String collectibleAssetPath(String? imagePath) {
  if (imagePath == null || imagePath.trim().isEmpty) return '';
  final fileName = imagePath.split('/').where((part) => part.isNotEmpty).last;
  return 'assets/collectibles/butterfly/$fileName';
}
