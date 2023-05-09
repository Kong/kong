return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "acme_storage" (
        "id"          UUID   PRIMARY KEY,
        "key"         TEXT   UNIQUE,
        "value"       TEXT,
        "created_at"  TIMESTAMP WITH TIME ZONE,
        "ttl"         TIMESTAMP WITH TIME ZONE
      );
    ]],
  },
}
