#!/usr/bin/env python3
"""Opt-in local PostgreSQL restore drill. Never connects to a remote host.

Creates two NEW databases with random fixture prefixes in the local test cluster.
No existing database is dropped, cleared or reused. Credentials stay in private
libpq files. The created fixture databases remain for private inspection.
"""
from __future__ import annotations

import argparse
import configparser
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import migrate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--admin-service", required=True,
                        help="Existing private service entry for a local disposable test cluster.")
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    if not args.execute:
        print("Offline fixture plan only. Add --execute to create two new local test databases.")
        return 0

    environment = migrate.db_env()
    alias = migrate.service_name(args.admin_service)
    config = configparser.ConfigParser(interpolation=None)
    config.read(environment["PGSERVICEFILE"])
    if not config.has_section(alias):
        raise migrate.MigrationError("Admin service entry does not exist.")
    service = dict(config[alias])
    if service.get("host") not in ("127.0.0.1", "::1", "localhost"):
        raise migrate.MigrationError("Fixture runner accepts only an explicit loopback host.")
    if service.get("hostaddr") and service["hostaddr"] not in ("127.0.0.1", "::1"):
        raise migrate.MigrationError("Fixture hostaddr must be loopback.")
    if any(key in service for key in ("service", "servicefile", "options", "password")):
        raise migrate.MigrationError("Use a direct simple local service with a private PGPASSFILE.")
    psql = migrate.binary("psql")
    suffix = uuid.uuid4().hex[:12]
    source_db, target_db = f"nightowl_migration_fixture_{suffix}", f"nightowl_migration_restore_{suffix}"
    folder = Path(tempfile.mkdtemp(prefix="nightowl-migration-drill-"))
    folder.chmod(0o700)

    for database in (source_db, target_db):
        migrate.command([psql, "--no-psqlrc", "--no-password", "--set=ON_ERROR_STOP=1",
                         f"--dbname=service={alias}", "--command",
                         f"CREATE DATABASE {migrate.identifier(database)};"],
                        migrate.db_env(read_only=False))
    config = configparser.ConfigParser(interpolation=None)
    for name, database in (("fixture_source", source_db), ("fixture_target", target_db)):
        config[name] = {**service, "dbname": database}
    services = folder / "services.conf"
    with services.open("x") as handle:
        os.chmod(services, 0o600)
        config.write(handle, space_around_delimiters=False)
    os.environ["PGSERVICEFILE"] = str(services)

    migrate.command([psql, "--no-psqlrc", "--no-password", "--set=ON_ERROR_STOP=1",
                     "--dbname=service=fixture_source", "--file",
                     str(Path(__file__).with_name("fixture.sql"))], migrate.db_env(read_only=False))
    export = folder / "export"
    migration = argparse.Namespace(source="fixture_source", target="fixture_target",
                                   target_database=target_db, output=str(export))
    migrate.export_database(migration)
    migrate.restore_database(migration)
    migrate.verify_database(migration)

    # A restore into the now-populated test target must fail without changing rows.
    try:
        migrate.restore_database(migration)
    except migrate.MigrationError:
        pass
    else:
        raise migrate.MigrationError("Populated-target safety guard did not refuse a second restore.")

    # A source read-only session must reject DML and leave the fixture source unchanged.
    try:
        migrate.command(migrate.psql_args("fixture_source"), migrate.db_env(),
                        migrate.transaction_sql(
                            "INSERT INTO public.empty_records VALUES ('33333333-3333-3333-3333-333333333333');"))
    except migrate.MigrationError:
        pass
    else:
        raise migrate.MigrationError("Read-only source guard did not refuse DML.")
    empty_count = migrate.query("fixture_source", "SELECT to_json(count(*))::text FROM public.empty_records;")
    if empty_count != 0:
        raise migrate.MigrationError("Source fixture changed during read-only guard test.")

    # Prove content verification catches a target-only changed private message, even
    # when table row counts are unchanged. This database contains synthetic data only.
    migrate.command([psql, "--no-psqlrc", "--no-password", "--set=ON_ERROR_STOP=1",
                     "--dbname=service=fixture_target", "--command",
                     "UPDATE public.private_messages SET body='synthetic corruption check' WHERE id=1;"],
                    migrate.db_env(read_only=False))
    try:
        migrate.verify_database(migration)
    except migrate.MigrationError:
        pass
    else:
        raise migrate.MigrationError("Row-digest verifier missed target-only corruption.")

    receipt = {
        "scope": "synthetic local PostgreSQL fixture, not actual Supabase data",
        "database_restore_verified": True, "populated_target_refused": True,
        "source_dml_refused": True, "source_empty_table_stayed_empty": True,
        "target_corruption_detected": True, "source_database": source_db,
        "target_database": target_db, "private_artifacts": str(folder),
        "storage_network_export": "not_exercised_by_this_database_drill",
    }
    migrate.write_json(folder / "receipt.json", receipt)
    print(json.dumps(receipt, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (migrate.MigrationError, OSError) as error:
        print(f"Local fixture drill refused: {error}", file=sys.stderr)
        raise SystemExit(2)
