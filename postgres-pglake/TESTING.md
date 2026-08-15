# Testing the pglake image

The image is published as `ghcr.io/jaredchurch/postgres-pglake:dev` on feature branches
and `ghcr.io/jaredchurch/postgres-pglake:latest` once merged to main.

It is a standard PostgreSQL image, so test it like any Postgres container.

## 1. Run it

> Do **not** use `--rm` for the first run. If the container exits, `--rm`
> deletes the container along with all of its logs, leaving nothing to debug.

```bash
docker pull ghcr.io/jaredchurch/postgres-pglake:dev   # login first if repo is private
docker rm -f pglake-test
docker run -d --name pglake-test -e POSTGRES_PASSWORD=test ghcr.io/jaredchurch/postgres-pglake:dev
```

## 2. Confirm the container is alive

```bash
docker ps -a | grep pglake-test    # pglake-test should be Up - note the exit code if not
echo $?
```

## 3. Confirm pgduck_server started

The entrypoint auto-starts pgduck_server (the DuckDB engine pg_lake queries
through) alongside Postgres.

```bash
docker exec pglake-test cat /tmp/pgduck_server.log
```

A healthy log ends with something like:

```
LOG pgduck_server is listening on unix_socket_directory: /tmp with port 5332, max_clients allowed 10000
LOG using DuckDB version: v1.4.4
```

## 4. Verify pg_lake loads

`CREATE EXTENSION` runs automatically on a fresh volume; run it manually on
existing clusters.

```bash
docker exec pglake-test psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS pg_lake CASCADE;"
docker exec pglake-test psql -U postgres -c "\dx pg_lake*"
```

## 5. Exercise DuckDB (pgduck_server)

pg_lake does **not** provide a `duckdb_execute()` SQL function — that was a
`pg_duckdb` API and errors with `function duckdb_execute(unknown) does not exist`.
pg_lake sends queries to `pgduck_server` over its unix socket instead, so run
DuckDB SQL directly against that server (the exact socket the extensions use):

```bash
docker exec pglake-test psql -U postgres -h /tmp -p 5332 -c "SELECT version();"
```

Quick sanity check:

```bash
docker exec pglake-test psql -U postgres -h /tmp -p 5332 -c "SELECT 1+1 AS x;"
# -> x
# -> 2
```

The end-to-end pg_lake check through Postgres is an Iceberg table round-trip.
This needs the S3 endpoint and `pg_lake_iceberg.default_location_prefix`
configured (see `docker-entrypoint-pgduck.sh`); otherwise `CREATE TABLE`
fails with `"location" option is required for pg_lake_iceberg tables`:

```sql
CREATE TABLE t(a int) USING iceberg;
INSERT INTO t VALUES (1),(2);
SELECT sum(a) FROM t;
DROP TABLE t;
```

## Troubleshooting: container exits immediately

If `docker ps -a` shows the container exited, grab the logs before anything
else (this is why we skipped `--rm`):

```bash
docker logs pglake-test
```

Common causes:

- **`pgduck_server` holds something postgres needs** — pgduck_server writes to
  `/tmp` and `/var/lib/postgresql/.pglake`. Check the init scripts in
  `/docker-entrypoint-initdb.d` and the pgduck_server log in step 3.
- **`initdb` or the init scripts failed** — the init script runs
  `CREATE EXTENSION pg_lake CASCADE`; a failure there aborts startup and the
  entrypoint exits the container.

- **`pg_extension_base can only be loaded via shared_preload_libraries`** —
  `CREATE EXTENSION pg_lake CASCADE` fails unless
  `shared_preload_libraries = 'pg_extension_base'` is set in `postgresql.conf`
  before the server starts. The image injects this via
  `postgresql.conf.sample`; existing clusters must add it manually and
  restart (see the section above to test without a rebuild).

Reproduce interactively to see the full output:

```bash
docker run --rm -it --name pglake-test   -e POSTGRES_PASSWORD=test   ghcr.io/jaredchurch/postgres-pglake:dev
```

## Testing config changes without a full rebuild

A full image rebuild takes ~90 minutes, but a config-only change can be tested
in a couple of minutes on the already-published image by overriding
`postgresql.conf.sample` with a bind mount. `initdb` derives `postgresql.conf`
from that sample on first init, so this exercises the exact same path as the
Dockerfile.

```bash
# 1. Extract the stock sample config from the image
docker run --rm --entrypoint cat \
  ghcr.io/jaredchurch/postgres-pglake:dev \
  /usr/share/postgresql/18/postgresql.conf.sample \
  > /tmp/pglake.conf.sample

# 2. Append the line the Dockerfile now adds
echo "shared_preload_libraries = 'pg_extension_base'" >> /tmp/pglake.conf.sample
tail -3 /tmp/pglake.conf.sample

# 3. Run with the modified sample mounted over the image's copy
docker rm -f pglake-test 2>/dev/null
docker run -d --name pglake-test \
  -e POSTGRES_PASSWORD=test \
  -v /tmp/pglake.conf.sample:/usr/share/postgresql/18/postgresql.conf.sample:ro \
  ghcr.io/jaredchurch/postgres-pglake:dev

# 4. Watch it start: should reach "database system is ready" and then run
#    10-pglake.sql WITHOUT the pg_extension_base error
docker logs -f pglake-test

# 5. Verify once it is up
docker exec pglake-test psql -U postgres -c "SHOW shared_preload_libraries;"
docker exec pglake-test psql -U postgres -c "SELECT extname FROM pg_extension ORDER BY 1;"
docker exec pglake-test psql -U postgres -h /tmp -p 5332 -c "SELECT version() AS duckdb_version;"
```

Note: the CI workflow uses `cache-from/cache-to: type=gha`, so the next build
reuses the expensive builder-stage layers and only rebuilds the runtime stage.

## Tear down

```bash
docker stop pglake-test
docker rm pglake-test
```
