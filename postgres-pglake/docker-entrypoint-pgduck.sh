#!/usr/bin/env bash
# Starts pgduck_server (the DuckDB engine pg_lake executes queries on) alongside
# PostgreSQL, then hands over to the official docker-entrypoint.sh.
#
# pgduck_server listens on a unix socket only, and the pg_lake extensions reach
# it over that socket (pg_lake_engine.host, default "host=/tmp port=5332"), so
# it must run in the same container/namespace as the Postgres server.
set -euo pipefail

PG_MAJOR=18
PGDUCK_SERVER="/usr/lib/postgresql/${PG_MAJOR}/bin/pgduck_server"
PGDUCK_CACHE_DIR="/tmp/pgduck_cache"
PGDUCK_INIT_FILE="/tmp/pgduck_init.sql"
PGDUCK_LOG="/tmp/pgduck_server.log"

GARAGE_ENV_FILE="/run/secrets/garage.env"  # shared Garage S3 creds (mounted ro)

# ---------------------------------------------------------------------------
# pgduck_server init file: Garage S3 secret (optional but needed for Iceberg)
# ---------------------------------------------------------------------------
# Generate the DuckDB `garage` secret from the shared Garage credentials file
# (single source of truth, mounted read-only — no secrets in this repo). If the
# file is not mounted, run "PART 2" of pg-iceberg-tables.sql once by hand:
#   psql -h /tmp -p 5332 -f pg-iceberg-tables.sql   # (second half only)
#
# pg_lake only runs on the compose network, so the S3 endpoint is Garage's
# plain-HTTP service name (garage:3900), not the Caddy TLS hostname used by
# host-side clients. Override with S3_ENDPOINT_INTERNAL if the topology changes.
RUN_INIT_ARGS=()
if [ -f "$GARAGE_ENV_FILE" ]; then
    # shellcheck source=/dev/null
    . "$GARAGE_ENV_FILE"
    if [ -n "${S3_ACCESS_KEY_ID:-}" ] && [ -n "${S3_SECRET_ACCESS_KEY:-}" ]; then
        endpoint="${S3_ENDPOINT_INTERNAL:-http://garage:3900}"
        host="${endpoint#*://}"
        {
            printf 'CREATE OR REPLACE SECRET garage (\n'
            printf '    TYPE S3,\n'
            printf "    KEY_ID '%s',\n" "$S3_ACCESS_KEY_ID"
            printf "    SECRET '%s',\n" "$S3_SECRET_ACCESS_KEY"
            printf "    REGION '%s',\n" "${S3_REGION:-air-home-1}"
            printf "    ENDPOINT '%s',\n" "$host"
            case "$endpoint" in
                https://*) printf '    USE_SSL true,\n' ;;
                *)         printf '    USE_SSL false,\n' ;;
            esac
            printf "    URL_STYLE 'path',\n"
            printf "    SCOPE 's3://%s'\n" "${S3_BUCKET:-air-iceberg}"
            printf ');\n'
        } > "$PGDUCK_INIT_FILE"
        RUN_INIT_ARGS=(--init_file_path "$PGDUCK_INIT_FILE")
    fi
fi

# ---------------------------------------------------------------------------
# Start pgduck_server (background) then the official entrypoint
# ---------------------------------------------------------------------------
mkdir -p "$PGDUCK_CACHE_DIR"
if [ "$(id -u)" = "0" ]; then
    chown postgres:postgres "$PGDUCK_CACHE_DIR"
    gosu postgres "$PGDUCK_SERVER" \
        --cache_dir "$PGDUCK_CACHE_DIR" \
        --unix_socket_directory /tmp \
        --unix_socket_group postgres \
        --port 5332 \
        "${RUN_INIT_ARGS[@]}" \
        >"$PGDUCK_LOG" 2>&1 &
else
    "$PGDUCK_SERVER" \
        --cache_dir "$PGDUCK_CACHE_DIR" \
        --unix_socket_directory /tmp \
        --unix_socket_group postgres \
        --port 5332 \
        "${RUN_INIT_ARGS[@]}" \
        >"$PGDUCK_LOG" 2>&1 &
fi
echo "pgduck_server started (pid $!) — log: $PGDUCK_LOG" >&2

exec /usr/local/bin/docker-entrypoint.sh "$@"
