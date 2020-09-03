return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "cluster_status" (
        id             UUID PRIMARY KEY,
        hostname       TEXT NOT NULL,
        ip             TEXT NOT NULL,
        last_seen      TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        config_hash    TEXT NOT NULL
      );
    ]],
  },
  cassandra = {
    up = [[]],
  }
}
