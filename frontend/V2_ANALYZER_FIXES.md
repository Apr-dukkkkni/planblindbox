# PlanBlindBox V2 analyzer fixes

Apply this overlay to the Flutter `frontend/` root. It addresses the 3 warnings and 29 infos reported by `flutter analyze`: async exception handling, redundant null assertion, disabled legacy upload handler, sqflite public imports, deprecated dropdown initialValue API, and curly-brace style lints. It preserves the previous V2 test-fix changes to `local_plan_repository.dart` and `mod_registry.dart`.

After applying, run `flutter analyze` and `flutter test`. This environment does not include Flutter/Dart, so runtime validation must be performed in the project environment.
