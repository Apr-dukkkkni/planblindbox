# P0-3 patch application notes

This is an incremental source patch. Do not apply it to the original project alone.

## Required order

1. Keep the original `1111.zip` as rollback backup.
2. Apply `PlanBlindBox_MOD_P0-1_Patch_Draft_0.1.zip`.
3. Apply `PlanBlindBox_MOD_P0-2_Patch_Draft_0.1.zip`.
4. Merge this patch's `1111/` tree at the project root.

P0-3 imports `ModManifestV1Validator` from P0-1 and uses the schema v8 MOD tables from P0-2.

## Important behavior

- The production approval provider defaults to `DenyAllModApprovalProvider`.
- Until P0-5 connects a signature-verified Store Attestation/admin approval source, task-template creation will be rejected. This is intentional fail-closed behavior.
- V1 package content is not yet mounted by a Declarative Runtime; P0-3 does not execute it.
- No new SQLite migration is introduced; database remains at schema version 8.
- No arbitrary third-party code is executed.

## Files

The patch updates auth/session lifecycle, the local repository's atomic MOD task-write boundary, MOD storage projection/audit, registry lifecycle, settings, and the two MOD UI surfaces. It adds `mod_capability_broker.dart`, `mod_permission_policy.dart`, `mod_runtime_session.dart`, and two test files.

## Verify in Flutter project

```bash
cd 1111/frontend
dart format lib/auth/auth_session.dart \
  lib/data/local/local_plan_repository.dart \
  lib/mod_platform/runtime/mod_capability_broker.dart \
  lib/mod_platform/runtime/mod_permission_policy.dart \
  lib/mod_platform/runtime/mod_runtime_session.dart \
  lib/mod_platform/storage/mod_platform_store.dart \
  lib/screens/mod_hub_drawer.dart \
  lib/screens/mod_management_page.dart \
  lib/screens/settings_page.dart \
  lib/services/mod_registry.dart \
  test/mod_platform/capability_broker_test.dart \
  test/mod_platform/mod_runtime_session_test.dart

flutter test test/mod_platform/capability_broker_test.dart
flutter test test/mod_platform/mod_runtime_session_test.dart
flutter test test/mod_registry_test.dart
flutter analyze
```

Do not treat the patch as build-verified until these commands pass in the project's Flutter toolchain.
