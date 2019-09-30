return {
    postgres = { -- TODO: Breaking Error. Reference route_id, service_id, or consumer_id
        up = [[
            CREATE TABLE IF NOT EXISTS "gql_ratelimiting_cost_decoration" (
                "id"                         UUID                           PRIMARY KEY,
                "service_id"                 UUID                           REFERENCES "services" ("id") ON DELETE CASCADE,
                "type_path"                  TEXT,
                "add_arguments"              TEXT[],
                "add_constant"               FLOAT,
                "mul_arguments"              TEXT[],
                "mul_constant"               FLOAT,
                "created_at"                 TIMESTAMP WITH TIME ZONE,
                "updated_at"                 TIMESTAMP WITH TIME ZONE
            );

            DO $$
            BEGIN
              CREATE INDEX IF NOT EXISTS "gql_ratelimiting_cost_decoration_fkey_service" ON
                                         "gql_ratelimiting_cost_decoration" ("service_id");
            EXCEPTION WHEN UNDEFINED_COLUMN THEN
              -- Do nothing
            END $$;
        ]]
    },

    cassandra = {
        up = [[
            CREATE TABLE IF NOT EXISTS "gql_ratelimiting_cost_decoration" (
              "partition"         text,
              "id"                uuid,
              "service_id"        uuid,
              "type_path"         text,
              "add_arguments"     list<text>,
              "add_constant"      float,
              "mul_arguments"     list<text>,
              "mul_constant"      float,
              "created_at"        timestamp,
              "updated_at"        timestamp,
              PRIMARY KEY         (partition, id)
            );

            CREATE INDEX IF NOT EXISTS gql_ratelimiting_cost_decoration_service_id_idx ON
                                       gql_ratelimiting_cost_decoration(service_id);
        ]]
    }
}
