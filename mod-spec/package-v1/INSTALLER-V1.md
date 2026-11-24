# PlanBlindBox Package V1 — ZIP Installer Contract

The V1 task-template installer accepts one ZIP file with the package files at
its root (`manifest.json`, `integrity.json`, and the declared content entry).
The installer does not execute package code and does not grant permissions.

## ZIP constraints

- Maximum compressed archive: 50 MiB.
- Maximum entries, including explicit directory entries: 256.
- Maximum uncompressed file: 20 MiB.
- Maximum total uncompressed files: 100 MiB.
- ZIP64, split/multi-disk archives, encrypted entries and compression methods
  other than Store (0) and Deflate (8) are rejected.
- Names must be UTF-8 (or ASCII when the UTF-8 flag is absent), use `/`, and
  contain only ASCII letters, digits, `.`, `_`, and `-` in each segment.
- Absolute paths, dot segments, Windows reserved names, duplicate names under
  case-insensitive comparison, symbolic links, special files, and overlapping
  local-entry data ranges are rejected.
- The ZIP decoder verifies entry CRC values. The package validator then checks
  the manifest, content schema and SHA-256 inventory.

## Installation transaction

1. Inspect the end record and central directory before inflating any payload.
2. Enforce entry count, declared per-file and aggregate expanded sizes.
3. Decode with CRC verification and compare decoded entries to central metadata.
4. Validate the complete in-memory package using `ModPackageValidator`.
5. Write to a unique staging directory beneath the installation root.
6. Re-read staged files and validate again.
7. Rename the existing installation to a private backup, then rename staging to
   the final MOD ID directory. If the commit rename fails, restore the backup.
8. Remove the backup after commit; a cleanup failure leaves it under a hidden
   backup name and does not roll back the committed installation.

The installation root is supplied by the caller. The final directory name is
`manifest.id`, which is validated by Manifest V1 before any filesystem write.
The caller remains responsible for associating the installed package with the
account-scoped `ModPlatformStore` installation record and the separate approval
and permission-grant workflow.

## Deliberate V1 limitations

- ZIP64 and multi-volume ZIPs are not accepted because all V1 limits fit in
  classic ZIP fields.
- The package is bounded in memory by the compressed and expanded limits.
  A later large-package format should use a streaming ZIP reader with explicit
  output quotas rather than increasing these limits casually.
- SHA-256 inventory verifies consistency, not publisher identity. Publisher
  signatures and trust-chain validation are separate work.
