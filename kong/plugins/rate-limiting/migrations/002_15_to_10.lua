return {
  postgres = {
    up = [[
    ]],

    teardown = function(connector)
      assert(connector:connect_migrations())
      assert(connector:query [[
        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "ratelimiting_metrics"
           DROP CONSTRAINT IF EXISTS "ratelimiting_metrics_pkey" CASCADE;
        EXCEPTION WHEN UNDEFINED_COLUMN THEN
          -- Do nothing, accept existing state
        END$$;

        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "ratelimiting_metrics"
                     ADD PRIMARY KEY ("identifier", "period", "period_date", "service_id", "route_id");
        EXCEPTION WHEN UNDEFINED_COLUMN THEN
          -- Do nothing, accept existing state
        END$$;

        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "ratelimiting_metrics" DROP "api_id";
        EXCEPTION WHEN UNDEFINED_COLUMN THEN
          -- Do nothing, accept existing state
        END$$;
      ]])
    end,
  },

  cassandra = {
    up = [[
    ]],

    teardown = function(connector)
      assert(connector:connect_migrations())
      assert(connector:query([[
        DROP TABLE IF EXISTS ratelimiting_metrics;
        CREATE TABLE IF NOT EXISTS ratelimiting_metrics (
          identifier  text,
          period      text,
          period_date timestamp,
          service_id  uuid,
          route_id    uuid,
          value       counter,
          PRIMARY KEY ((identifier, period, period_date, service_id, route_id))
        );
      ]]))
    end,
  },
}
