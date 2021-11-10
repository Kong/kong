-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "degraphql_routes" (
        "id"                UUID                        PRIMARY KEY,
        "service_id"        UUID                        REFERENCES "services" ("id") ON DELETE CASCADE,
        "methods"           TEXT[],
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
    up = [[
      CREATE TABLE IF NOT EXISTS "degraphql_routes" (
        "partition"         text,
        "id"                uuid,
        "service_id"        uuid,
        "methods"           list<text>,
        "uri"               text,
        "query"             text,
        "created_at"        timestamp,
        "updated_at"        timestamp,
        PRIMARY KEY         (partition, id)
      );

      CREATE INDEX IF NOT EXISTS degraphql_routes_service_id_idx ON degraphql_routes(service_id);
    ]],
  },
}

