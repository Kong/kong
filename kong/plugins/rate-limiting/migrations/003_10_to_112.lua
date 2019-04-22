return {
  postgres = {
    up = [[
      CREATE INDEX IF NOT EXISTS ratelimiting_metrics_idx ON ratelimiting_metrics (service_id, route_id, period_date, period);
    ]],
  },

  cassandra = {
    up = [[
    ]],
  },
}
