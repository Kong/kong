return {
  postgres = {
    up = [[
      DO $$
      BEGIN
      DROP TABLE IF EXISTS clustering_sync_delta;
      DROP INDEX IF EXISTS clustering_sync_delta_version_idx;
      END;
      $$;
    ]]
  }
}
