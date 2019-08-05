return {
    postgres = { -- TODO: Breaking Error. Reference route_id, service_id, or consumer_id
        up = [[
            CREATE TABLE IF NOT EXISTS "gql_ratelimiting_cost_decoration" (
                "id"                         UUID                           PRIMARY KEY,
                "type_path"                  TEXT                           UNIQUE,
                "add_arguments"              TEXT[],
                "add_constant"               FLOAT,
                "mul_arguments"              TEXT[],
                "mul_constant"               FLOAT,
                "created_at"                 TIMESTAMP WITH TIME ZONE
            );
        ]]
    },

    -- TODO: Add schema for Cassandra
    cassandra = {
        up = [[]]
    }
}
