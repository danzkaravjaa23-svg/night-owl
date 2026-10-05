#!/bin/sh
set -eu
# Docker's entrypoint sources this script during fresh initialization.
# Quoted psql variables avoid SQL/shell interpolation of password contents.
AUTHENTICATOR_PASSWORD=$(cat "$AUTHENTICATOR_PASSWORD_FILE")
READINESS_PASSWORD=$(cat "$READINESS_PASSWORD_FILE")
test -n "$AUTHENTICATOR_PASSWORD"
test -n "$READINESS_PASSWORD"
export AUTHENTICATOR_PASSWORD READINESS_PASSWORD
psql --no-psqlrc --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set=ON_ERROR_STOP=1 <<'SQL'
\getenv authenticator_password AUTHENTICATOR_PASSWORD
\getenv readiness_password READINESS_PASSWORD
select format('alter role authenticator password %L', :'authenticator_password') \gexec
select format('alter role nightowl_readiness password %L', :'readiness_password') \gexec
SQL
unset AUTHENTICATOR_PASSWORD READINESS_PASSWORD
