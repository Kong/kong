-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
    postgres = { -- TODO: Breaking Error. Reference route_id, service_id, or consumer_id
        up = [[
            CREATE TABLE IF NOT EXISTS "graphql_ratelimiting_advanced_cost_decoration" (
                "id"                         UUID                       PRIMARY KEY,
                "service_id"                 UUID                       REFERENCES "services" ("id") ON DELETE CASCADE,
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
              CREATE INDEX IF NOT EXISTS "graphql_ratelimiting_advanced_cost_decoration_fkey_service" ON
                                         "graphql_ratelimiting_advanced_cost_decoration" ("service_id");
            EXCEPTION WHEN UNDEFINED_COLUMN THEN
              -- Do nothing
            END $$;
        ]]
    },
}
