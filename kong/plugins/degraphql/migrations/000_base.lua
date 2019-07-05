return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "degraphql_routes" (
        "id"                UUID                        PRIMARY KEY,
        "service_id"        UUID                        REFERENCES "services" ("id"),
        "method"            TEXT,
        "uri"               TEXT,
        "query"             TEXT,
        "created_at"        TIMESTAMP WITH TIME ZONE,
        "updated_at"        TIMESTAMP WITH TIME ZONE
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "degraphql_routes_fkey_service" ON
                                   "degraphql_routes" ("service_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing
      END $$;
    ]],
  },
  cassandra = {
    up = [[ ]],
  },
}

