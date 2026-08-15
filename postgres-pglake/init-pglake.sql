-- Creates the pg_lake extensions. This only runs when the data directory is
-- first initialized (fresh volume). On an existing cluster, run manually:
--
--     CREATE EXTENSION IF NOT EXISTS pg_lake CASCADE;
--
-- CASCADE pulls in pg_lake_iceberg, pg_lake_table, pg_lake_copy, pg_lake_engine,
-- pg_extension_base, pg_map, pg_extension_updater and btree_gist.
CREATE EXTENSION IF NOT EXISTS pg_lake CASCADE;
