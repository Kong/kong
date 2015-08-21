local Migrations = {
  {
    name = "2015-08-03-132400_init_oauth2",
    up = function(options)
      return [[
        CREATE TABLE IF NOT EXISTS response_ratelimiting_metrics(
          api_id uuid,
          identifier text,
          period text,
          period_date timestamp,
          value counter,
          PRIMARY KEY ((api_id, identifier, period_date, period))
        );
      ]]
    end,
    down = function(options)
      return [[
        DROP TABLE response_ratelimiting_metrics;
      ]]
    end
  }
}

return Migrations
