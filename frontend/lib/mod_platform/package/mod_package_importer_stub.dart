import 'mod_package_models.dart';

bool get supportsV1ZipInstall => false;

Future<ModPackageImportSession> prepareV1PackageImport({
  required List<int> bytes,
  required int ownerId,
}) =>
    Future<ModPackageImportSession>.error(
      UnsupportedError('当前平台暂不支持安装 ZIP 内容包'),
    );

Future<void> deleteV1PackageDirectory({
  required int ownerId,
  required String modId,
  required String packageDirectory,
}) async {}
