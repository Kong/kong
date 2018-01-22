return {
  {
    name = "2015-08-03-132400_init_response_ratelimiting",
    up = [[
      CREATE TABLE IF NOT EXISTS response_ratelimiting_metrics(
        api_id uuid,
        identifier text,
        period text,
        period_date timestamp without time zone,
        value integer,
        PRIMARY KEY (api_id, identifier, period_date, period)
      );

      CREATE OR REPLACE FUNCTION increment_response_rate_limits(a_id uuid, i text, p text, p_date timestamp with time zone, v integer) RETURNS VOID AS $$
      BEGIN
        LOOP
          UPDATE response_ratelimiting_metrics SET value = value + v WHERE api_id = a_id AND identifier = i AND period = p AND period_date = p_date;
          IF found then
            RETURN;
          END IF;

          BEGIN
            INSERT INTO response_ratelimiting_metrics(api_id, period, period_date, identifier, value) VALUES(a_id, p, p_date, i, v);
            RETURN;
          EXCEPTION WHEN unique_violation THEN

          END;
        END LOOP;
      END;
      $$ LANGUAGE 'plpgsql';
    ]],
    down = [[
      DROP TABLE response_ratelimiting_metrics;
    ]]
  },
  {
    name = "2016-08-04-321512_response-rate-limiting_policies",
    up = function(_, _, dao)
      local rows, err = dao.plugins:find_all {name = "response-ratelimiting"}
      if err then
        return err
      end

      for i = 1, #rows do
        local response_rate_limiting = rows[i]

        -- Delete the old one to avoid conflicts when inserting the new one
        local _, err = dao.plugins:delete(response_rate_limiting)
        if err then
          return err
        end

        local _, err = dao.plugins:insert {
          name = "response-ratelimiting",
          api_id = response_rate_limiting.api_id,
          consumer_id = response_rate_limiting.consumer_id,
          enabled = response_rate_limiting.enabled,
          config = {
            second = response_rate_limiting.config.second,
            minute = response_rate_limiting.config.minute,
            hour = response_rate_limiting.config.hour,
            day = response_rate_limiting.config.day,
            month = response_rate_limiting.config.month,
            year = response_rate_limiting.config.year,
            block_on_first_violation = response_rate_limiting.config.block_on_first_violation,
            limit_by = "consumer",
            policy = "cluster",
            fault_tolerant = response_rate_limiting.config.continue_on_error
          }
        }
        if err then
          return err
        end
      end
    end
  },
  {
    name = "2017-12-19-120000_add_route_and_service_id_to_response_ratelimiting",
    up = [[
      ALTER TABLE response_ratelimiting_metrics DROP CONSTRAINT response_ratelimiting_metrics_pkey;
      ALTER TABLE response_ratelimiting_metrics ALTER COLUMN api_id SET DEFAULT '00000000000000000000000000000000';
      ALTER TABLE response_ratelimiting_metrics ADD COLUMN route_id uuid NOT NULL DEFAULT '00000000000000000000000000000000';
      ALTER TABLE response_ratelimiting_metrics ADD COLUMN service_id uuid NOT NULL DEFAULT '00000000000000000000000000000000';
      ALTER TABLE response_ratelimiting_metrics ADD PRIMARY KEY (api_id, route_id, service_id, identifier, period_date, period);

      CREATE OR REPLACE FUNCTION increment_response_rate_limits(
        r_id uuid, s_id uuid, i text, p text, p_date timestamp with time zone, v integer)
      RETURNS VOID AS $$
      BEGIN
        LOOP
          UPDATE response_ratelimiting_metrics
          SET value = value + v
          WHERE route_id = r_id
            AND service_id = s_id
            AND identifier = i
            AND period = p
            AND period_date = p_date;
          IF found then RETURN;
          END IF;

          BEGIN
            INSERT INTO response_ratelimiting_metrics(route_id, service_id, period,
                                                      period_date, identifier, value)
            VALUES(r_id, s_id, p, p_date, i, v);
            RETURN;
          EXCEPTION WHEN unique_violation THEN
          END;
        END LOOP;
      END;
      $$ LANGUAGE 'plpgsql';
      CREATE OR REPLACE FUNCTION increment_response_rate_limits_api(a_id uuid, i text, p text, p_date timestamp with time zone, v integer) RETURNS VOID AS $$
      BEGIN
        LOOP
          UPDATE response_ratelimiting_metrics SET value = value + v WHERE api_id = a_id AND identifier = i AND period = p AND period_date = p_date;
          IF found then
            RETURN;
          END IF;

          BEGIN
            INSERT INTO response_ratelimiting_metrics(api_id, period, period_date, identifier, value) VALUES(a_id, p, p_date, i, v);
            RETURN;
          EXCEPTION WHEN unique_violation THEN

          END;
        END LOOP;
      END;
      $$ LANGUAGE 'plpgsql';
    ]],
    down = nil,
  },
--  {
--    name = "2017-12-19-130000_remove_api_id_from_response_ratelimiting",
--    up = [[
--      ALTER TABLE response_ratelimiting_metrics DROP COLUMN api_id;
--    ]],
--    down = nil,
--  },
}
