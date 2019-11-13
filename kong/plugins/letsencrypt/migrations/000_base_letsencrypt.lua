return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "letsencrypt_storage" (
        "id"          UUID   PRIMARY KEY,
        "key"         TEXT   UNIQUE,
        "value"       TEXT,
        "created_at"  TIMESTAMP WITH TIME ZONE,
        "ttl"         TIMESTAMP WITH TIME ZONE
      );
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS letsencrypt_storage (
        id          uuid PRIMARY KEY,
        key         text,
        value       text,
        created_at  timestamp
      );
      CREATE INDEX IF NOT EXISTS letsencrypt_storage_key_idx ON letsencrypt_storage(key);
    ]],
  },
}
