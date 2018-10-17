return {
  postgres = {
    up = [[
      ALTER TABLE IF EXISTS ONLY "response_ratelimiting_metrics"
        ALTER "period_date" TYPE TIMESTAMP WITH TIME ZONE USING "period_date" AT TIME ZONE 'UTC';
    ]],
    teardown = function(connector)
      assert(connector:connect_migrations())
      assert(connector:query([[
        DROP FUNCTION IF EXISTS "increment_response_rate_limits" (UUID, UUID, TEXT, TEXT, TIMESTAMP WITH TIME ZONE, INTEGER) CASCADE;
        DROP FUNCTION IF EXISTS "increment_response_rate_limits" (UUID, UUID, TEXT, TEXT, TIMESTAMP WITHOUT TIME ZONE, INTEGER) CASCADE;
        DROP FUNCTION IF EXISTS "increment_response_rate_limits" (UUID, TEXT, TEXT, TIMESTAMP WITH TIME ZONE, INTEGER) CASCADE;
        DROP FUNCTION IF EXISTS "increment_response_rate_limits" (UUID, TEXT, TEXT, TIMESTAMP WITHOUT TIME ZONE, INTEGER) CASCADE;
        DROP FUNCTION IF EXISTS "increment_response_rate_limits_api" (UUID, TEXT, TEXT, TIMESTAMP WITH TIME ZONE, INTEGER) CASCADE;
        DROP FUNCTION IF EXISTS "increment_response_rate_limits_api" (UUID, TEXT, TEXT, TIMESTAMP WITHOUT TIME ZONE, INTEGER) CASCADE;
      ]]))
    end
  },

  cassandra = {
    up = [[
    ]],
  },
}
