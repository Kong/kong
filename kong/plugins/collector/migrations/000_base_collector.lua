return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS service_maps (
        workspace_id uuid PRIMARY KEY,
        created_at TIMESTAMP WITHOUT TIME ZONE,
        service_map TEXT
      );
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS service_maps (
        workspace_id uuid PRIMARY KEY,
        created_at timestamp,
        service_map text,
      );
    ]],
  },
}
