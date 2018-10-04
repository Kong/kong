return {
  postgres = {
    up = [[
      ALTER TABLE IF EXISTS ONLY "ratelimiting_metrics"
        ALTER "period_date" TYPE TIMESTAMP WITH TIME ZONE USING "period_date" AT TIME ZONE 'UTC';
    ]],
  },

  cassandra = {
    up = [[
    ]],
  },
}
