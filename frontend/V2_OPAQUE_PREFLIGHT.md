# PlanBlindBox V2 OPAQUE preflight patch

This patch addresses a Web integration blocker and adds a protocol smoke test.

## 1. CORS fix

The previous `CorsConfig` only registered `/api/v1/**`. Flutter Web calls `/api/v2/auth/**` and `/api/v2/me/sync/**`, so browser preflight requests would fail even though the Java service compiles and its existing tests pass.

The patch changes the mapping to `/api/**` and adds integration tests for:
- OPAQUE login-start preflight (`POST`, `Content-Type`)
- authenticated sync preflight (`PUT`, `Authorization`, `Content-Type`)

The allowed origins remain controlled by `MOD_ALLOWED_ORIGINS`.

## 2. OPAQUE smoke test

From `frontend/opaque-service`:

```powershell
npm install
npm run smoke
```

This verifies the pinned `@serenity-kit/opaque@1.1.0` API for:
- registration
- login
- stable exportKey across registration and login
- client/server session-key agreement
- wrong-password rejection

It uses an ephemeral in-memory server setup and does not touch your real OPAQUE server setup or database.

## 3. Apply and verify

Extract this ZIP into `frontend/`, overwriting the two listed source files and adding the new test/script. Then run:

```powershell
cd .\mod-server
mvn test
cd ..\opaque-service
npm install
npm run smoke
```

Do not treat the Java Maven suite alone as proof that OPAQUE login works; the sidecar smoke test and later HTTP end-to-end test are separate checks.
