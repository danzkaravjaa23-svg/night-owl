#!/usr/bin/env python3
"""Run synthetic authorization checks in a new disposable local PG cluster.

No service file, password, source database or production network is used. The
cluster accepts Unix-socket connections in its private temporary directory only.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pg-bin", required=True, type=Path)
    args = parser.parse_args()
    binaries = {name: args.pg_bin.resolve() / name
                for name in ("initdb", "pg_ctl", "psql")}
    for name, path in binaries.items():
        if not path.is_file():
            parser.error(f"Missing {name} in supplied PostgreSQL binary folder")
    root = Path(__file__).resolve().parents[3]
    tests = Path(__file__).resolve().parent
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith("PG")}

    def run(command, *, succeeds=True):
        result = subprocess.run(command, env=environment, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if succeeds and result.returncode:
            raise RuntimeError(result.stderr or result.stdout)
        return result

    with tempfile.TemporaryDirectory(prefix="nightowl-featured-fixture-") as folder:
        base = Path(folder)
        data = base / "data"
        run([str(binaries["initdb"]), "-D", str(data), "--auth=trust", "--no-sync"])
        run([str(binaries["pg_ctl"]), "-D", str(data), "-l", str(base / "server.log"),
             "-o", f"-h '' -k {base} -p 55439", "-w", "start"])
        command = [str(binaries["psql"]), "-X", "--no-password", "-v", "ON_ERROR_STOP=1",
                   "-h", str(base), "-p", "55439", "-d", "postgres"]
        try:
            run([*command, "-f", str(tests / "featured_events_fixture.sql")])
            migration = [*command, "-f", str(root / "supabase_featured_events.sql")]
            refused = run(migration, succeeds=False)
            if refused.returncode == 0 or "protect_profile_flags" not in refused.stderr:
                raise RuntimeError("Migration did not reject missing profile flag protection")
            run([*command, "-c", "SELECT public.fixture_assert(to_regclass('public.event_features') IS NULL, 'migration rolled back');"])
            protection = (root / "supabase_protect_profile_flags.sql").read_text()
            migration_body = (root / "supabase_featured_events.sql").read_text()
            migration_body = re.sub(r"^(?:begin|commit);$", "", migration_body, flags=re.MULTILINE)
            combined = base / "atomic-rollout.sql"
            combined.write_text(f"BEGIN;\n{protection}\n{migration_body}\nCOMMIT;")
            run([*command, "-f", str(combined)])
            run(migration)
            run([*command, "-f", str(tests / "featured_events_security.sql")])
            print(json.dumps({"scope": "synthetic disposable PostgreSQL",
                              "missing_security_prerequisite_refused": True,
                              "companion_and_migration_applied_atomically": True,
                              "migration_atomic_and_repeatable": True,
                              "ordinary_and_banned_user_mutations_refused": True,
                              "anonymous_reads_and_expiry_verified": True,
                              "admin_select_reorder_remove_verified": True}))
        finally:
            run([str(binaries["pg_ctl"]), "-D", str(data), "-m", "immediate", "-w", "stop"])


if __name__ == "__main__":
    main()
