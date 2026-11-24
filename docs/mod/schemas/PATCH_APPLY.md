# P0-2 patch application notes

This archive is a source patch, not a complete replacement project.

## Prerequisites

1.  Keep the original `1111.zip` as rollback backup.
2.  Apply the P0-1 patch first if it has not already been merged:
    `PlanBlindBox_MOD_P0-1_Patch_Draft_0.1.zip`.
3.  Extract this P0-2 archive at the project root and merge the `1111/`
    tree.

## Files changed

-   `frontend/lib/data/local/local_database.dart`
-   `frontend/lib/data/local/local_plan_repository.dart`
-   `frontend/lib/services/mod_registry.dart`
-   `frontend/lib/mod_platform/storage/mod_platform_store.dart` (new)
-   `frontend/test/mod_registry_test.dart`

## Important

-   SQLite schema advances from version 7 to 8.
-   The old global `mods.registry.*` setting is no longer authoritative
    and is removed during migration.
-   Permission grants and audit events are not backed up.
-   Restored installations are disabled, receive a new
    `installation_id`, and require reauthorization.
-   `host_integrated_offline` storage entries are deliberately excluded
    from user backups because they may contain host-derived data.
-   The current `ModRegistry` remains a transitional declaration-only
    adapter. It does not execute third-party code and is not the final
    Manifest V1 package installation flow.

## Verification

Run in the Flutter project:

``` bash
cd 1111/frontend
dart format lib/data/local/local_database.dart \
  lib/data/local/local_plan_repository.dart \
  lib/services/mod_registry.dart \
  lib/mod_platform/storage/mod_platform_store.dart \
  test/mod_registry_test.dart

flutter test test/mod_registry_test.dart
flutter analyze
```

The authoring environment used for this patch did not have Flutter/Dart
installed. Do not treat the patch as build-verified until the commands
above pass.
