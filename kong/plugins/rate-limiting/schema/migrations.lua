local Migrations = {
  {
    name = "2015-08-03-132400_init_ratelimiting",
    up = function(options, dao_factory)
      return dao_factory:execute_queries [[
        CREATE TABLE IF NOT EXISTS ratelimiting_metrics(
          api_id uuid,
          identifier text,
          period text,
          period_date timestamp,
          value counter,
          PRIMARY KEY ((api_id, identifier, period_date, period))
        );
      ]]
    end,
    down = function(options, dao_factory)
      return dao_factory:execute_queries [[
        DROP TABLE ratelimiting_metrics;
      ]]
    end
  }
}

return Migrations
