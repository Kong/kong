return {
  postgres = {
    up = [[
      DO $$
      BEGIN
      CREATE TABLE IF NOT EXISTS clustering_sync_version (
        "version" SERIAL PRIMARY KEY
      );
      CREATE TABLE IF NOT EXISTS clustering_sync_delta (
        "version" INT NOT NULL,
        "type" TEXT NOT NULL,
        "pk" JSON NOT NULL,
        "ws_id" UUID NOT NULL,
        "entity" JSON,
        FOREIGN KEY (version) REFERENCES clustering_sync_version(version) ON DELETE CASCADE
      );
      -- version starts at 1, as 0 indicates no sync has been performed
      INSERT INTO clustering_sync_version (version) VALUES (1) ON CONFLICT DO NOTHING;
      INSERT INTO clustering_sync_delta (version, type, pk, ws_id, entity) VALUES (1, 'init', '{}', '00000000-0000-0000-0000-000000000000', '{}') ON CONFLICT DO NOTHING;
      CREATE INDEX IF NOT EXISTS clustering_sync_delta_version_idx ON clustering_sync_delta (version);
      END;
      $$;
    ]]
  }
}
