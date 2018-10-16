return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "response_ratelimiting_metrics" (
        "identifier"   TEXT                         NOT NULL,
        "period"       TEXT                         NOT NULL,
        "period_date"  TIMESTAMP WITHOUT TIME ZONE  NOT NULL,
        "service_id"   UUID                         NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
        "route_id"     UUID                         NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
        "api_id"       UUID                         NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
        "value"        INTEGER,

        PRIMARY KEY ("identifier", "period", "period_date", "service_id", "route_id", "api_id")
      );

      CREATE OR REPLACE FUNCTION "increment_response_rate_limits" (a_id UUID, i TEXT, p TEXT, p_date TIMESTAMP WITH TIME ZONE, v INTEGER) RETURNS void
      LANGUAGE plpgsql
      AS $$
        BEGIN
          LOOP
            UPDATE response_ratelimiting_metrics
               SET value = value + v
             WHERE identifier = i
               AND period = p
               AND period_date = p_date
               AND api_id = a_id;

            IF FOUND THEN
              RETURN;
            END IF;

            BEGIN
              INSERT INTO response_ratelimiting_metrics (identifier, period, period_date, api_id, value)
                   VALUES (i, p, p_date, a_id, v);
              RETURN;
            EXCEPTION WHEN unique_violation THEN

            END;
          END LOOP;
        END;
        $$;

      CREATE OR REPLACE FUNCTION increment_response_rate_limits (r_id UUID, s_id UUID, i TEXT, p TEXT, p_date TIMESTAMP WITH TIME ZONE, v INTEGER) RETURNS void
      LANGUAGE plpgsql
      AS $$
        BEGIN
          LOOP
            UPDATE response_ratelimiting_metrics
               SET value = value + v
             WHERE identifier = i
               AND period = p
               AND period_date = p_date
               AND service_id = s_id
               AND route_id = r_id;

            IF FOUND THEN
              RETURN;
            END IF;

            BEGIN
              INSERT INTO response_ratelimiting_metrics (identifier, period, period_date, service_id, route_id, value)
                   VALUES (i, p, p_date, r_id, s_id, v);
              RETURN;
            EXCEPTION WHEN unique_violation THEN

            END;
          END LOOP;
        END;
        $$;

      CREATE OR REPLACE FUNCTION increment_response_rate_limits_api (a_id UUID, i TEXT, p TEXT, p_date TIMESTAMP WITH TIME ZONE, v INTEGER) RETURNS void
      LANGUAGE plpgsql
      AS $$
        BEGIN
          LOOP
            UPDATE response_ratelimiting_metrics
               SET value = value + v
             WHERE identifier = i
               AND period = p
               AND period_date = p_date
               AND api_id = a_id;

            IF FOUND THEN
              RETURN;
            END IF;

            BEGIN
              INSERT INTO response_ratelimiting_metrics (identifier, period, period_date, api_id, value)
                   VALUES (i, p, p_date, a_id, v);
              RETURN;
            EXCEPTION WHEN unique_violation THEN

            END;
          END LOOP;
        END;
        $$;
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS response_ratelimiting_metrics(
        route_id    uuid,
        service_id  uuid,
        api_id      uuid,
        period_date timestamp,
        period      text,
        identifier  text,
        value       counter,
        PRIMARY KEY ((route_id, service_id, api_id, identifier, period_date, period))
      );
    ]],
  },
}
