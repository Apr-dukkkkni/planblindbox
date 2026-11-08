# PlanBlindBox V2 patch

This patch upgrades the Flutter client and Java server source for the V2 private vault and OPAQUE login flow. It is intended to be merged over the existing project root; keep project assets that were not included in the source upload (especially `assets/collectibles/butterfly/`).

1. Merge `lib/`, `mod-server/`, `web/`, `assets/opaque/`, `opaque-client/`, `../opaque-service`, `test/`, `scripts/`, `pubspec.yaml`, and the V2 documentation into the existing project.
2. Run `flutter pub get` (the `pubspec.lock` supplied with the source upload predates the new `webview_flutter` dependency and must be regenerated).
3. Run `./scripts/build_opaque.sh` to generate the actual OPAQUE WASM bundle. The checked-in `opaque_client.js` files are deliberate placeholders and will fail closed until this command succeeds.
4. Generate and securely store `OPAQUE_SERVER_SETUP`, start `opaque-service`, and configure `OPAQUE_INTERNAL_SECRET` for both the sidecar and Java server.
5. Start the Java server so Flyway applies V8 and V9. Use new V2 test accounts; V1 accounts do not have OPAQUE credentials.
6. Run `flutter test`, then build Web and Android. The iOS project was not supplied and is not included in this patch.

See `V2_UPGRADE.md` for protocol details, environment variables, migration behavior, and known limitations.

## Verification status

- `node --check opaque-service/server.js`: passed.
- `node --check opaque-client/src/bridge.js`: passed.
- The editing container does not include Flutter/Dart or Maven, so Flutter tests and Java compilation were not run here.
- npm registry access was unavailable in the editing container, so the actual `@serenity-kit/opaque` WASM bundle was not generated here. Run `./scripts/build_opaque.sh` in a network-enabled development environment before testing registration/login.
- This is a development preview, not a production security certification. Complete the trusted-device/recovery-code flow and the optional diary lock before calling the whole privacy feature set finished.
