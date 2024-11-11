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
      CREATE INDEX IF NOT EXISTS clustering_sync_delta_version_idx ON clustering_sync_delta (version);
      END;
      $$;
    ]]
  }
}
