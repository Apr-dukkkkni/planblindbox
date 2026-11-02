#!/usr/bin/env python3
"""Generate standalone, isolated PlanBlindBox MySQL benchmark seed SQL.

Only writes a local .sql file. It never connects to a database.
Derived from the actual PlanBlindBox V2.1-V2.5 Flyway V1/V2 table schema.
"""
import argparse
import json
import re
import uuid
from pathlib import Path

SCHEMA = """CREATE TABLE mod_packages (
  mod_id VARCHAR(100) PRIMARY KEY,
  name VARCHAR(60) NOT NULL,
  description VARCHAR(300) NOT NULL,
  latest_version VARCHAR(32) NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE mod_versions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  mod_id VARCHAR(100) NOT NULL,
  version VARCHAR(32) NOT NULL,
  manifest_json TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_mod_versions_mod FOREIGN KEY (mod_id) REFERENCES mod_packages(mod_id),
  CONSTRAINT uk_mod_version UNIQUE (mod_id, version)
);
CREATE TABLE mod_download_events (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  request_id VARCHAR(36) NOT NULL,
  mod_id VARCHAR(100) NOT NULL,
  version VARCHAR(32) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uk_download_request UNIQUE (request_id),
  CONSTRAINT fk_download_version FOREIGN KEY (mod_id, version) REFERENCES mod_versions(mod_id, version)
);
CREATE INDEX idx_mod_enabled_name ON mod_packages(enabled, name);
CREATE INDEX idx_download_mod_time ON mod_download_events(mod_id, created_at);
CREATE TABLE mod_download_outbox (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  download_event_id BIGINT NOT NULL,
  mod_id VARCHAR(100) NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  published_at TIMESTAMP NULL,
  CONSTRAINT uk_outbox_download_event UNIQUE (download_event_id),
  CONSTRAINT fk_outbox_download_event FOREIGN KEY (download_event_id) REFERENCES mod_download_events(id)
);
CREATE INDEX idx_mod_outbox_status ON mod_download_outbox(status, id);
"""


def quote(value: str) -> str:
    # Input is fully generator-controlled, but quote SQL strings defensively.
    return "'" + value.replace("'", "''") + "'"


def append_insert(file, table: str, cols: str, values):
    if not values:
        return
    file.write(f"INSERT INTO {table} ({cols}) VALUES\n")
    file.write(",\n".join(values))
    file.write(";\n")


def generate(db: str, mods: int, events: int, batch: int, output: Path):
    ids = [f"com.perftest.mod{i:05d}" for i in range(1, mods + 1)]
    hot_count = max(1, mods // 10)
    with output.open("w", encoding="utf-8", newline="\n") as file:
        file.write("-- PlanBlindBox performance DATA ONLY: synthetic, not real downloads.\n")
        file.write("-- Safety: CREATE DATABASE without IF NOT EXISTS; abort if already present.\n")
        file.write("-- Do not import into plan_mod_market; this file uses only its own database.\n")
        file.write("SET NAMES utf8mb4;\n")
        file.write(f"CREATE DATABASE `{db}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\n")
        file.write(f"USE `{db}`;\n")
        file.write(SCHEMA)
        file.write("-- Grant only runtime DML access to the existing development MySQL account.\n")
        file.write(f"GRANT SELECT, INSERT, UPDATE, DELETE ON `{db}`.* TO 'mod_app'@'localhost';\n")
        file.write("START TRANSACTION;\n")
        for offset in range(0, mods, batch):
            rows = []
            for i in range(offset, min(offset + batch, mods)):
                rows.append("(" + ",".join([
                    quote(ids[i]), quote(f"压测Mod {i+1:05d}"),
                    quote(f"PlanBlindBox synthetic performance benchmark {i+1}"),
                    quote("1.0.0"), "TRUE"
                ]) + ")")
            append_insert(file, "mod_packages", "mod_id,name,description,latest_version,enabled", rows)
        for offset in range(0, mods, batch):
            rows = []
            for i in range(offset, min(offset + batch, mods)):
                manifest = json.dumps({
                    "schemaVersion": 1, "id": ids[i], "name": f"压测Mod {i+1:05d}",
                    "version": "1.0.0", "description": "Synthetic test fixture, not a real user Mod",
                    "permissions": ["tasks.create"], "dependencies": [],
                    "taskTemplates": [{"title": "压测示例任务", "targetCount": 1}]
                }, ensure_ascii=False, separators=(",", ":"))
                rows.append("(" + ",".join([quote(ids[i]), quote("1.0.0"), quote(manifest)]) + ")")
            append_insert(file, "mod_versions", "mod_id,version,manifest_json", rows)
        file.write("COMMIT;\n")
        for offset in range(0, events, batch):
            event_rows, outbox_rows = [], []
            for n in range(offset + 1, min(offset + batch, events) + 1):
                # Eight in ten events target hottest 10% mods; the rest spread over all mods.
                mod_index = ((n * 17) % hot_count) if n % 5 else ((n * 7919) % mods)
                mod_id = ids[mod_index]
                rid = str(uuid.uuid5(uuid.NAMESPACE_URL, f"planblindbox-perf/{db}/{n}"))
                event_rows.append(f"({n},{quote(rid)},{quote(mod_id)},'1.0.0')")
                # PUBLISHED is synthetic fixture state, not a RabbitMQ delivery assertion.
                outbox_rows.append(f"({n},{quote(mod_id)},'PUBLISHED',CURRENT_TIMESTAMP)")
            file.write("START TRANSACTION;\n")
            append_insert(file, "mod_download_events", "id,request_id,mod_id,version", event_rows)
            append_insert(file, "mod_download_outbox", "download_event_id,mod_id,status,published_at", outbox_rows)
            file.write("COMMIT;\n")
        file.write("-- Final counts should match the --mods and --events inputs.\n")
        file.write("SELECT COUNT(*) AS mod_count FROM mod_packages;\n")
        file.write("SELECT COUNT(*) AS download_count FROM mod_download_events;\n")
        file.write("SELECT COUNT(*) AS outbox_count FROM mod_download_outbox;\n")
        file.write("SELECT COUNT(*) AS missing_outbox FROM mod_download_events e ")
        file.write("LEFT JOIN mod_download_outbox o ON o.download_event_id=e.id WHERE o.id IS NULL;\n")
        file.write("SELECT mod_id, COUNT(*) AS downloads FROM mod_download_events GROUP BY mod_id ORDER BY downloads DESC LIMIT 10;\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mods", type=int, default=100)
    parser.add_argument("--events", type=int, default=10000)
    parser.add_argument("--db", default="plan_mod_perf_10k")
    parser.add_argument("--batch", type=int, default=250)
    parser.add_argument("--out", type=Path, default=Path("perf_seed.sql"))
    args = parser.parse_args()
    if not re.fullmatch(r"plan_mod_perf_[a-z0-9_]{1,36}", args.db):
        parser.error("--db must be a dedicated plan_mod_perf_* database name")
    if not 1 <= args.mods <= 10000:
        parser.error("--mods must be between 1 and 10000")
    if not 0 <= args.events <= 2000000:
        parser.error("--events must be between 0 and 2000000")
    if not 1 <= args.batch <= 500:
        parser.error("--batch must be between 1 and 500")
    if args.out.exists():
        parser.error(f"Output exists: {args.out}. Choose a new path; will not overwrite.")
    generate(args.db, args.mods, args.events, args.batch, args.out)
    print(f"Generated: {args.out.resolve()} ({args.out.stat().st_size:,} bytes)")
    print(f"Database: {args.db}; mods={args.mods}; events={args.events}; outbox={args.events}")
    print("No database was changed. Import is an explicit separate step.")


if __name__ == "__main__":
    main()
