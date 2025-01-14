return {
  postgres = {
    up = [[
      DO $$
      BEGIN
      DROP TABLE IF EXISTS clustering_sync_delta;
      DROP INDEX IF EXISTS clustering_sync_delta_version_idx;
      END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "keys" ADD "x5t" TEXT UNIQUE;
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
          -- Do nothing, accept existing state
          END;
      $$;
    ]]
  }
}
