import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'mod_package_installer.dart';
import 'mod_package_models.dart';

bool get supportsV1ZipInstall => true;

Future<ModPackageImportSession> prepareV1PackageImport({
  required List<int> bytes,
  required int ownerId,
}) async {
  final databasePath = await getDatabasesPath();
  final installer = ModPackageInstaller(
    installationRoot: Directory(
      p.join(databasePath, 'mod_packages', 'owner_$ownerId'),
    ),
  );
  final preview = installer.validateBytes(bytes);
  return ModPackageImportSession(
    preview: preview,
    install: () => installer.installBytes(bytes),
  );
}

/// Deletes only the exact owner-scoped package directory created by this adapter.
Future<void> deleteV1PackageDirectory({
  required int ownerId,
  required String modId,
  required String packageDirectory,
}) async {
  if (!RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$').hasMatch(modId)) {
    throw const FormatException('MOD ID 无效，拒绝删除安装目录');
  }
  final databasePath = await getDatabasesPath();
  final root = Directory(p.join(databasePath, 'mod_packages', 'owner_$ownerId'));
  if (!await root.exists()) return;
  final canonicalRoot = await root.resolveSymbolicLinks();
  final expected = p.normalize(p.join(canonicalRoot, modId));
  final actual = p.normalize(packageDirectory);
  if (actual != expected) {
    throw const FormatException('安装目录与 MOD 身份不匹配，拒绝删除');
  }
  final type = await FileSystemEntity.type(actual, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (type != FileSystemEntityType.directory) {
    throw const FormatException('安装目录不是普通目录，拒绝删除');
  }
  await Directory(actual).delete(recursive: true);
}
