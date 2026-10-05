#!/bin/sh
set -eu
: "${PGDATABASE:?Set a new isolated *_rpc_backend_test database}"
case "$PGDATABASE" in
  *_rpc_backend_test) ;;
  *) printf '%s\n' 'Refusing RPC fixtures outside an isolated *_rpc_backend_test database' >&2; exit 1 ;;
esac
PSQL_BIN=${PSQL_BIN:-psql}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$PSQL_BIN" --no-psqlrc --set=ON_ERROR_STOP=1 --file="$SCRIPT_DIR/sql_rpc_fixture_setup.sql"
"$PSQL_BIN" --no-psqlrc --set=ON_ERROR_STOP=1 --file="$SCRIPT_DIR/sql_rpc_behavior.sql"
python3 "$SCRIPT_DIR/test_rpc_concurrency.py"
