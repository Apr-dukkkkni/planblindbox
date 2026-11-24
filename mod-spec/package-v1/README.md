# PlanBlindBox Declarative Package V1 — task_template

This first package profile supports only `contentKind: task_template`.

## Archive layout

```text
package.zip
├── manifest.json
├── integrity.json
├── content/
│   └── task-templates.json
└── assets/                 # optional; only files declared by manifest may be referenced
    └── icon.png
```

The ZIP root is the package root. Do not wrap these files in an extra directory.

## Entry point

`manifest.json` must pass `ModManifestV1Validator` and declare:

- `manifestVersion: 1`
- `type: content`
- `contentKind: task_template`
- `runtime.type: declarative`
- `runtime.apiVersion: "1"`
- `runtime.entrypoint: "content/task-templates.json"`
- `host.tasks.create` in `permissions`

All other required Manifest V1 fields remain mandatory. The validator is the source of truth for their shape and constraints.

## Task template document

`content/task-templates.json`:

```json
{
  "schemaVersion": 1,
  "templates": [
    {
      "title": "每天阅读",
      "note": "阅读一本书",
      "targetCount": 30,
      "importance": 4,
      "difficulty": 3
    }
  ]
}
```

The template fields and ranges intentionally match the existing legacy task-template contract: title (1–100 characters), note (0–500 characters), targetCount (1–999), importance (1–5), difficulty (1–5). `note`, `targetCount`, `importance`, and `difficulty` may be omitted and default to `""`, `1`, `3`, and `3` respectively. At most 20 templates are allowed.

## Integrity inventory

`integrity.json`:

```json
{
  "algorithm": "SHA-256",
  "files": {
    "manifest.json": "<64 lowercase hex characters>",
    "content/task-templates.json": "<64 lowercase hex characters>"
  }
}
```

Hashes are SHA-256 over each file's exact uncompressed bytes. The `files` object must list every archive file except `integrity.json`, and no missing or extra entries are accepted. `integrity.json` does not hash itself.

**Security limitation:** because this inventory is inside the same unsigned archive, it detects accidental corruption and inconsistent files but does not establish publisher authenticity or prevent an attacker from replacing both a file and its hash. Publisher signatures/trust verification are a separate future gate.

## Limits

- ZIP archive: 50 MiB
- Expanded total: 100 MiB
- Individual file: 20 MiB
- File count: 256 (including `manifest.json` and `integrity.json`)
- Manifest and integrity JSON: 64 KiB each
- Task templates: 20

The current validator enforces decoded-file count and expanded/file sizes. The future ZIP installer must enforce archive byte size and stream decompression limits before fully allocating entries. It must also reject duplicate ZIP entry names and symlinks before building the file map.

See [INSTALLER-V1.md](INSTALLER-V1.md) for ZIP-level limits, preflight checks,
CRC validation and the staging/backup installation transaction.
