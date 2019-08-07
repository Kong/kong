return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS service_maps (
        id TEXT NOT NULL PRIMARY KEY,
        created_at TIMESTAMP WITHOUT TIME ZONE,
        service_map TEXT
      );
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS service_maps (
        id text PRIMARY KEY,
        created_at timestamp,
        service_map text,
      );
    ]],
  },
}
