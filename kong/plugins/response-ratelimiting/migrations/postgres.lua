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
  }
}
