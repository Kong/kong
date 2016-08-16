return {
  {
    name = "2015-08-03-132400_init_ratelimiting",
    up = [[
      CREATE TABLE IF NOT EXISTS ratelimiting_metrics(
        api_id uuid,
        identifier text,
        period text,
        period_date timestamp without time zone,
        value integer,
        PRIMARY KEY (api_id, identifier, period_date, period)
      );

      CREATE OR REPLACE FUNCTION increment_rate_limits(a_id uuid, i text, p text, p_date timestamp with time zone, v integer) RETURNS VOID AS $$
      BEGIN
        LOOP
          UPDATE ratelimiting_metrics SET value = value + v WHERE api_id = a_id AND identifier = i AND period = p AND period_date = p_date;
          IF found then
            RETURN;
          END IF;

          BEGIN
            INSERT INTO ratelimiting_metrics(api_id, period, period_date, identifier, value) VALUES(a_id, p, p_date, i, v);
            RETURN;
          EXCEPTION WHEN unique_violation THEN

          END;
        END LOOP;
      END;
      $$ LANGUAGE 'plpgsql';
    ]],
    down = [[
      DROP TABLE ratelimiting_metrics;
    ]]
  },
  {
    name = "2016-07-25-471385_ratelimiting_policies",
    up = function(_, _, dao)
      local rows, err = dao.plugins:find_all {name = "rate-limiting"}
      if err then return err end

      for i = 1, #rows do
        local rate_limiting = rows[i]

        -- Delete the old one to avoid conflicts when inserting the new one
        local _, err = dao.plugins:delete(rate_limiting)
        if err then return err end

        local _, err = dao.plugins:insert {
          name = "rate-limiting",
          api_id = rate_limiting.api_id,
          consumer_id = rate_limiting.consumer_id,
          enabled = rate_limiting.enabled,
          config = {
            second = rate_limiting.config.second,
            minute = rate_limiting.config.minute,
            hour = rate_limiting.config.hour,
            day = rate_limiting.config.day,
            month = rate_limiting.config.month,
            year = rate_limiting.config.year,
            limit_by = "consumer",
            policy = "cluster",
            fault_tolerant = rate_limiting.config.continue_on_error
          }
        }
        if err then return err end
      end
    end
  }
}
