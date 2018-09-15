return {
  postgres = {
    up = [[

    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS ratelimiting_metrics(
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
