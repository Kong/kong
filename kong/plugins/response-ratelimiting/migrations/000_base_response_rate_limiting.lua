return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "response_ratelimiting_metrics" (
        "identifier"   TEXT                         NOT NULL,
        "period"       TEXT                         NOT NULL,
        "period_date"  TIMESTAMP WITH TIME ZONE     NOT NULL,
        "service_id"   UUID                         NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
        "route_id"     UUID                         NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
        "value"        INTEGER,

        PRIMARY KEY ("identifier", "period", "period_date", "service_id", "route_id")
      );
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS response_ratelimiting_metrics(
        route_id    uuid,
        service_id  uuid,
        period_date timestamp,
        period      text,
        identifier  text,
        value       counter,
        PRIMARY KEY ((route_id, service_id, identifier, period_date, period))
      );
    ]],
  },
}
