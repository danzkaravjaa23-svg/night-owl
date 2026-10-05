#!/usr/bin/env python3
"""Explicit local SQL integration driver; never discovered as a live unittest."""

from __future__ import annotations

import os
from pathlib import Path
import selectors
import subprocess
import time


PATCH = Path(__file__).resolve().parents[1] / "patches/20261005_missing_client_rpcs.sql"
PSQL = os.environ.get("PSQL_BIN", "psql")
CLAIMS = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}'
VENUE_ONE = "10000000-0000-4000-8000-000000000001"
VENUE_TWO = "10000000-0000-4000-8000-000000000002"


def arguments():
    return [PSQL, "--no-psqlrc", "-qAt", "--set=ON_ERROR_STOP=1"]


def sql(text: str, *, success=True):
    result = subprocess.run(arguments(), input=text, text=True, capture_output=True, timeout=15, check=False)
    if bool(result.returncode == 0) != success:
        raise AssertionError("RPC integration command returned an unexpected status; inspect only disposable fixtures locally.")
    return result


def reject_patch_after(setup: str):
    # Use argv file handling because repository paths may contain spaces.
    result = subprocess.run(arguments() + ["--command", setup, "--file", str(PATCH)],
                            text=True, capture_output=True, timeout=15, check=False)
    if result.returncode == 0:
        raise AssertionError("An unsafe or duplicate target migration unexpectedly succeeded.")
    return result


def worker(text: str):
    process = subprocess.Popen(arguments(), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    process.stdin.write(text.encode())
    process.stdin.close()
    process.stdin = None
    return process


def wait_for_lock_marker(process):
    output = b""
    deadline = time.monotonic() + 10
    with selectors.DefaultSelector() as ready:
        ready.register(process.stdout, selectors.EVENT_READ)
        while b"LOCK_HELD\n" not in output:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not ready.select(remaining):
                raise AssertionError("Concurrent fixture did not hold its expected lock.")
            chunk = os.read(process.stdout.fileno(), 4096)
            if not chunk:
                raise AssertionError("Concurrent fixture exited before its lock marker.")
            output += chunk


def finish(process):
    process.communicate(timeout=10)
    if process.returncode:
        raise AssertionError("Concurrent fixture transaction failed.")


def close_worker(process):
    if process.poll() is None:
        process.kill()
        process.communicate(timeout=5)


def failed_patch_preconditions():
    # Real migration execution must refuse each unsafe state; not a reimplementation
    # of the SQL checks. Connection close rolls back any error transaction.
    checks = (
        ("set role nightowl_rpc_fixture_owner; set nightowl.target_rpc_patch='';", "Independent-target approval marker required"),
        ("set nightowl.target_rpc_patch='approved-independent-target';", "RPC owner must be a reviewed role"),
        ("begin; alter table public.messages force row level security; set role nightowl_rpc_fixture_owner; set nightowl.target_rpc_patch='approved-independent-target';", "Expected owned table"),
        ("begin; alter table public.messages owner to nightowl_owner; set role nightowl_rpc_fixture_owner; set nightowl.target_rpc_patch='approved-independent-target';", "Expected owned table"),
    )
    for setup, expected in checks:
        result = reject_patch_after(setup)
        if expected not in result.stderr:
            raise AssertionError("Migration did not fail at its expected security precondition.")
    # A rerun must refuse existing functions, with the entire transaction aborted.
    result = reject_patch_after("set role nightowl_rpc_fixture_owner; set nightowl.target_rpc_patch='approved-independent-target';")
    if "already exists" not in result.stderr:
        raise AssertionError("Additive migration silently overwrote an existing RPC.")


def simultaneous_checkins():
    first_sql = (
        "begin; set local role authenticated; set local request.jwt.claims='" + CLAIMS + "';\n"
        "select * from public.check_in_venue('" + VENUE_ONE + "');\n"
        "select 'LOCK_HELD'; select pg_sleep(1.2); commit;\n"
    )
    first = worker(first_sql)
    try:
        wait_for_lock_marker(first)
        started = time.monotonic()
        sql("begin; set local role authenticated; set local request.jwt.claims='" + CLAIMS + "'; select * from public.check_in_venue('" + VENUE_TWO + "'); commit;")
        if time.monotonic() - started < 0.6:
            raise AssertionError("Simultaneous check-in did not wait for the caller lock.")
        finish(first)
        verified = sql("""
select
  (select count(*)=1 and bool_and(venue_id='10000000-0000-4000-8000-000000000002'::uuid) from public.checkins where user_id='00000000-0000-4000-8000-000000000001')
  and (select count(*)=1 from public.checkins where user_id='00000000-0000-4000-8000-000000000002' and venue_id='10000000-0000-4000-8000-000000000001')
  and not exists(select 1 from public.venues v where v.checkin_count<>(select count(*) from public.checkins c where c.venue_id=v.id));
""").stdout.strip()
        if verified != "t":
            raise AssertionError("Concurrent check-ins left duplicate state, changed another user or diverged counters.")
    finally:
        close_worker(first)


def opposite_user_swaps():
    claims_bob = CLAIMS.replace("000000000001", "000000000002")
    workers = []
    try:
        started = time.monotonic()
        for claims, venue in ((CLAIMS, VENUE_ONE), (claims_bob, VENUE_TWO)):
            text = (
                "begin; set local role authenticated; set local request.jwt.claims='" + claims + "';"
                "set local nightowl.fixture_swap_pause='enabled';"
                "select * from public.check_in_venue('" + venue + "'); commit;"
            )
            process = worker(text)
            workers.append(process)
        for process in workers:
            process.communicate(timeout=12)
            if process.returncode:
                raise AssertionError("Opposite-user venue swaps deadlocked or failed.")
        if time.monotonic() - started < 0.9:
            raise AssertionError("Swap fixture did not exercise both forced counter-trigger pauses.")
        verified = sql("""
select
  (select count(*)=1 and bool_and(venue_id='10000000-0000-4000-8000-000000000001'::uuid) from public.checkins where user_id='00000000-0000-4000-8000-000000000001')
  and (select count(*)=1 and bool_and(venue_id='10000000-0000-4000-8000-000000000002'::uuid) from public.checkins where user_id='00000000-0000-4000-8000-000000000002')
  and not exists(select 1 from public.venues v where v.checkin_count<>(select count(*) from public.checkins c where c.venue_id=v.id));
""").stdout.strip()
        if verified != "t":
            raise AssertionError("Opposite-user swaps left wrong venues, duplicates or divergent counters.")
    finally:
        for process in workers:
            close_worker(process)


def isolation_guards():
    before = sql("select count(*) from public.group_chats; select count(*) from public.checkins;").stdout
    for isolation in ("repeatable read", "serializable"):
        for operation in (
            "select public.create_group('Fixture refused isolation',array['00000000-0000-4000-8000-000000000002']::uuid[]);",
            "select * from public.check_in_venue('" + VENUE_ONE + "');",
        ):
            result = sql("begin isolation level " + isolation + "; set local role authenticated; set local request.jwt.claims='" + CLAIMS + "'; " + operation + " commit;", success=False)
            if "requires READ COMMITTED isolation" not in result.stderr:
                raise AssertionError("Mutation did not fail closed for unsupported snapshot isolation.")
    if sql("select count(*) from public.group_chats; select count(*) from public.checkins;").stdout != before:
        raise AssertionError("Refused isolation invocation mutated application rows.")


def group_and_block_orderings():
    alice = "00000000-0000-4000-8000-000000000001"
    bob = "00000000-0000-4000-8000-000000000002"
    bob_claims = CLAIMS.replace("000000000001", "000000000002")
    group = "select public.create_group('Fixture concurrency group-first',array['" + bob + "']::uuid[]);"
    block = "insert into public.blocks(blocker_id,blocked_id) values('" + bob + "','" + alice + "');"
    first = worker("begin; set local role authenticated; set local request.jwt.claims='" + CLAIMS + "'; " + group + " select 'LOCK_HELD'; select pg_sleep(0.9); commit;")
    try:
        wait_for_lock_marker(first)
        started = time.monotonic()
        sql("begin; set local role authenticated; set local request.jwt.claims='" + bob_claims + "'; " + block + " commit;")
        if time.monotonic() - started < 0.5:
            raise AssertionError("Block insertion bypassed the pending group table barrier.")
        finish(first)
        if sql("select count(*)=1 from public.group_chats where name='Fixture concurrency group-first'; select count(*)=1 from public.blocks;").stdout.strip() != "t\nt":
            raise AssertionError("Group-first transaction ordering did not preserve both committed outcomes.")
    finally:
        close_worker(first)
    sql("delete from public.blocks;")

    first = worker("begin; set local role authenticated; set local request.jwt.claims='" + bob_claims + "'; " + block + " select 'LOCK_HELD'; select pg_sleep(0.9); commit;")
    try:
        wait_for_lock_marker(first)
        started = time.monotonic()
        group = group.replace("Fixture concurrency group-first", "Fixture concurrency block-first")
        result = sql("begin; set local role authenticated; set local request.jwt.claims='" + CLAIMS + "'; " + group + " commit;", success=False)
        if time.monotonic() - started < 0.5 or "One or more members unavailable" not in result.stderr:
            raise AssertionError("Group did not wait for and reject the just-committed block.")
        finish(first)
        if sql("select count(*)=0 from public.group_chats where name='Fixture concurrency block-first'; select count(*)=1 from public.blocks;").stdout.strip() != "t\nt":
            raise AssertionError("Block-first ordering leaked group rows or lost the committed block.")
    finally:
        close_worker(first)
    sql("delete from public.blocks;")


def main():
    if not os.environ.get("PGDATABASE", "").endswith("_rpc_backend_test"):
        raise SystemExit("Refusing integration queries outside an isolated *_rpc_backend_test database.")
    failed_patch_preconditions()
    isolation_guards()
    simultaneous_checkins()
    opposite_user_swaps()
    group_and_block_orderings()
    print("PASS: target-only ownership/marker/RLS gates, isolation rejection, same-user check-ins, opposite-user swaps, group/block commit orderings and preserved counters")


if __name__ == "__main__":
    main()
