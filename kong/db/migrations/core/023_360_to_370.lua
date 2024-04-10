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
    ]]
  }
}
