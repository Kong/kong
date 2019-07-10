return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS service_maps (
        id UUID NOT NULL PRIMARY KEY,
        created_at TIMESTAMP WITHOUT TIME ZONE,
        service_map TEXT,
        singleton TEXT UNIQUE
      );
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS service_maps (
        id uuid PRIMARY KEY,
        created_at timestamp,
        service_map text,
        singleton text,
      );
    ]],
  },
}
