#!/bin/sh
set -eu
: "${PGDATABASE:?Set an isolated *_backend_test database}"
case "$PGDATABASE" in
  *_backend_test) ;;
  *) printf '%s\n' 'Refusing SQL integration tests outside an isolated *_backend_test database' >&2; exit 1 ;;
esac
PSQL_BIN=${PSQL_BIN:-psql}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$PSQL_BIN" --no-psqlrc --set=ON_ERROR_STOP=1 --file="$SCRIPT_DIR/sql_bootstrap_readiness.sql"
