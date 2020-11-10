return {
  postgres = {
    up = [[
      CREATE INDEX IF NOT EXISTS sessions_ttl_idx ON sessions (ttl);
    ]],
  },

  cassandra = {
    up = [[]],
  },
}
