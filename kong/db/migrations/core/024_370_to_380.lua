return {
  postgres = {
    up = [[
      DO $$
      BEGIN
      CREATE TABLE clustering_sync_version (
        "version" SERIAL PRIMARY KEY
      );
      CREATE TABLE clustering_sync_delta (
        "version" INT NOT NULL,
        "type" TEXT NOT NULL,
        "id" UUID NOT NULL,
        "ws_id" UUID NOT NULL,
        "row" JSON,
        FOREIGN KEY (version) REFERENCES clustering_sync_version(version) ON DELETE CASCADE
      );
      CREATE INDEX clustering_sync_delta_version_idx ON clustering_sync_delta (version);
      END;
      $$;
    ]]
  }
}
