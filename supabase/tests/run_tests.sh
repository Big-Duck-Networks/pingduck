#!/bin/sh
# Applies the migrations to a throwaway Postgres 15 container and runs the
# schema tests. Needs Docker. Usage: supabase/tests/run_tests.sh
set -eu
cd "$(dirname "$0")/.."

name=pingduck-schema-test
docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --name "$name" -e POSTGRES_PASSWORD=test postgres:15 >/dev/null
trap 'docker rm -f "$name" >/dev/null' EXIT
until docker exec "$name" pg_isready -U postgres -q; do sleep 1; done
sleep 1

psql() { docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }
psql < tests/supabase_stub.sql
for f in migrations/*.sql; do
    echo "applying $f"
    psql < "$f"
done
psql < tests/schema_test.sql
