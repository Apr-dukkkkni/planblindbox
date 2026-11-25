import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'mod_package_models.dart';
import 'mod_package_validator.dart';
import 'mod_package_zip_preflight.dart';

/// Installs declarative task-template ZIP packages into a caller-owned root.
/// The ZIP is validated fully before the current installation is replaced.
/// No permissions are granted and no MOD code is executed by this class.
class ModPackageInstaller {
  ModPackageInstaller({
    required Directory installationRoot,
    ModPackageValidator? validator,
    ModPackageZipPreflight? preflight,
    Random? random,
  }) : _requestedRoot = installationRoot,
       _validator = validator ?? ModPackageValidator(),
       _preflight = preflight ?? const ModPackageZipPreflight(),
       _random = random ?? Random.secure();

  final Directory _requestedRoot;
  final ModPackageValidator _validator;
  final ModPackageZipPreflight _preflight;
  final Random _random;

  /// Validates a ZIP without writing anything. Import flows use this to show
  /// package metadata and check registry policy before replacing installed files.
  ModValidatedPackage validateBytes(List<int> archiveBytes) =>
      _decodeAndValidate(archiveBytes).package;

  ({Map<String, List<int>> files, ModValidatedPackage package})
      _decodeAndValidate(List<int> archiveBytes) {
    if (archiveBytes.isEmpty || archiveBytes.length > ModPackageLimits.maxArchiveBytes) {
      throw const FormatException('ZIP 文件为空或超过 50 MiB');
    }
    final bytes = archiveBytes is Uint8List
        ? archiveBytes
        : Uint8List.fromList(archiveBytes);

    // Inspect the central directory first. This bounds declared expansion
    // before the ZIP decoder is allowed to inflate any entry.
    final metadata = _preflight.inspect(bytes);
    final decodedArchive = ZipDecoder().decodeBytes(bytes, verify: true);
    final files = <String, List<int>>{};
    final decodedNames = <String>{};
    for (final entry in decodedArchive.files) {
      if (entry.isSymbolicLink || entry.symbolicLink != null) {
        throw FormatException('不允许符号链接：${entry.name}');
      }
      if (entry.isDirectory) continue;
      final name = entry.name;
      if (!decodedNames.add(name.toLowerCase())) {
        throw FormatException('ZIP 存在重复文件名：$name');
      }
      final declared = metadata.where((item) => !item.isDirectory &&
          item.name == name).toList(growable: false);
      if (declared.length != 1) {
        throw FormatException('ZIP 解码条目与中央目录不一致：$name');
      }
      final content = entry.readBytes();
      if (content == null || content.length != declared.single.uncompressedSize ||
          content.length > ModPackageLimits.maxFileBytes) {
        throw FormatException('ZIP 文件长度不一致：$name');
      }
      files[name] = content;
    }
    final expectedFileNames = metadata.where((item) => !item.isDirectory)
        .map((item) => item.name.toLowerCase()).toSet();
    if (files.length != expectedFileNames.length ||
        !files.keys.map((name) => name.toLowerCase()).toSet()
            .containsAll(expectedFileNames)) {
      throw const FormatException('ZIP 解码结果与中央目录文件清单不一致');
    }
    return (files: files, package: _validator.validate(files));
  }

  Future<ModPackageInstallResult> installBytes(List<int> archiveBytes) async {
    final decoded = _decodeAndValidate(archiveBytes);
    final files = decoded.files;
    final validated = decoded.package;
    final bytes = archiveBytes is Uint8List
        ? archiveBytes
        : Uint8List.fromList(archiveBytes);
    final manifest = validated.manifest;
    final modId = manifest['id'] as String;
    final version = manifest['version'] as String;
    final archiveSha256 = sha256.convert(bytes).toString();

    final root = await _prepareRoot();
    final target = Directory(p.join(root.path, modId));
    final suffix = '${DateTime.now().microsecondsSinceEpoch}-'
        '${_random.nextInt(1 << 31).toRadixString(16)}';
    final staging = Directory(p.join(root.path, '.staging-$suffix'));
    final backup = Directory(p.join(root.path, '.backup-$suffix'));
    var backupMoved = false;
    var installed = false;

    try {
      await staging.create();
      for (final entry in files.entries) {
        final outputPath = p.joinAll([staging.path, ...entry.key.split('/')]);
        final output = File(outputPath);
        await output.parent.create(recursive: true);
        await output.writeAsBytes(entry.value, flush: true);
      }

      // Re-read the staged bytes before committing. This catches storage
      // failures and guarantees the on-disk package still matches validation.
      final stagedFiles = <String, List<int>>{};
      for (final entry in files.keys) {
        stagedFiles[entry] = await File(
          p.joinAll([staging.path, ...entry.split('/')]),
        ).readAsBytes();
      }
      _validator.validate(stagedFiles);

      final targetType = await FileSystemEntity.type(
        target.path,
        followLinks: false,
      );
      if (targetType == FileSystemEntityType.link ||
          (targetType != FileSystemEntityType.notFound &&
              targetType != FileSystemEntityType.directory)) {
        throw const FormatException('安装目标不是普通目录，拒绝覆盖');
      }
      if (targetType == FileSystemEntityType.directory) {
        await target.rename(backup.path);
        backupMoved = true;
      }
      try {
        await staging.rename(target.path);
        installed = true;
      } catch (_) {
        if (backupMoved) {
          await backup.rename(target.path);
          backupMoved = false;
        }
        rethrow;
      }
      if (backupMoved) {
        // The new package is committed. Failure to remove an obsolete backup
        // must not roll back a successful install; it can be cleaned later.
        try {
          await backup.delete(recursive: true);
          backupMoved = false;
        } on FileSystemException {
          // Leave the backup quarantined under its non-public name.
        }
      }
      return ModPackageInstallResult(
        modId: modId,
        version: version,
        installDirectoryPath: target.path,
        archiveSha256: archiveSha256,
        package: validated,
      );
    } catch (_) {
      if (!installed && await staging.exists()) {
        await staging.delete(recursive: true);
      }
      if (!installed && backupMoved && !await target.exists() &&
          await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }

  Future<ModPackageInstallResult> installFile(File archiveFile) async {
    final length = await archiveFile.length();
    if (length <= 0 || length > ModPackageLimits.maxArchiveBytes) {
      throw const FormatException('ZIP 文件大小无效或超过 50 MiB');
    }
    return installBytes(await archiveFile.readAsBytes());
  }

  Future<Directory> _prepareRoot() async {
    await _requestedRoot.create(recursive: true);
    final canonical = await _requestedRoot.resolveSymbolicLinks();
    return Directory(canonical);
  }
}
