/// Limits for the first PlanBlindBox declarative package format.
/// ZIP-level limits must also be enforced while streaming/decompressing entries.
class ModPackageLimits {
  ModPackageLimits._();

  static const int maxArchiveBytes = 50 * 1024 * 1024;
  static const int maxExpandedBytes = 100 * 1024 * 1024;
  static const int maxFileBytes = 20 * 1024 * 1024;
  static const int maxFiles = 256;
  static const int maxManifestBytes = 64 * 1024;
  static const int maxIntegrityBytes = 64 * 1024;
  static const int maxTaskTemplates = 20;
}

class ModTaskTemplateDocument {
  ModTaskTemplateDocument({required List<Map<String, dynamic>> templates})
      : templates = List<Map<String, dynamic>>.unmodifiable(
          templates.map((item) => Map<String, dynamic>.unmodifiable(item)),
        );

  final List<Map<String, dynamic>> templates;
}

class ModValidatedPackage {
  const ModValidatedPackage({
    required this.manifest,
    required this.taskTemplates,
    required this.fileDigests,
  });

  final Map<String, dynamic> manifest;
  final ModTaskTemplateDocument taskTemplates;
  final Map<String, String> fileDigests;
}

/// Platform-neutral result returned after a validated package is committed.
class ModPackageInstallResult {
  const ModPackageInstallResult({
    required this.modId,
    required this.version,
    required this.installDirectoryPath,
    required this.archiveSha256,
    required this.package,
  });

  final String modId;
  final String version;
  final String installDirectoryPath;
  final String archiveSha256;
  final ModValidatedPackage package;
}

/// Preview plus deferred commit used by the platform-specific import adapter.
class ModPackageImportSession {
  const ModPackageImportSession({required this.preview, required this.install});

  final ModValidatedPackage preview;
  final Future<ModPackageInstallResult> Function() install;
}
