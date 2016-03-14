return {
  {
    name = "2015-08-21_init_response-rate-limiting",
    up = [[
      CREATE TABLE IF NOT EXISTS response_ratelimiting_metrics(
        api_id uuid,
        identifier text,
        period text,
        period_date timestamp,
        value counter,
        PRIMARY KEY ((api_id, identifier, period_date, period))
      );
    ]],
    down = [[
      DROP TABLE response_ratelimiting_metrics;
    ]]
  }
}
