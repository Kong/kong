return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "clustering_rpc_requests" (
        "id"         BIGSERIAL                  PRIMARY KEY,
        "node_id"    UUID                       NOT NULL,
        "reply_to"   UUID                       NOT NULL,
        "ttl"        TIMESTAMP WITH TIME ZONE   NOT NULL,
        "payload"    JSON                       NOT NULL
      );

      CREATE INDEX IF NOT EXISTS "clustering_rpc_requests_node_id_idx" ON "clustering_rpc_requests" ("node_id");

      DO $$
      BEGIN
      ALTER TABLE IF EXISTS ONLY "clustering_data_planes" ADD "rpc_capabilities" TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]]
  }
}
