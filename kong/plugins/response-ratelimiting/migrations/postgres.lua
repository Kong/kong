return {
  {
    name = "2015-08-03-132400_init_response_ratelimiting",
    up = [[
      CREATE TABLE IF NOT EXISTS response_ratelimiting_metrics(
        api_id uuid,
        identifier text,
        period text,
        period_date timestamp,
        value integer,
        PRIMARY KEY (api_id, identifier, period_date, period)
      );
    ]],
    down = [[
      DROP TABLE response_ratelimiting_metrics;
    ]]
  }
}
