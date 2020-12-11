return {
  postgres = {
    up = [[
      -- new vitals tables
      CREATE TABLE IF NOT EXISTS vitals_stats_days (LIKE vitals_stats_minutes INCLUDING defaults INCLUDING constraints INCLUDING indexes);
    ]],
    teardown = function(connector)
      -- Risky migrations
    end
  },
  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_stats_days(
        node_id uuid,
        at timestamp,
        l2_hit int,
        l2_miss int,
        plat_min int,
        plat_max int,
        ulat_min int,
        ulat_max int,
        requests int,
        plat_count int,
        plat_total int,
        ulat_count int,
        ulat_total int,
        PRIMARY KEY(node_id, at)
      ) WITH CLUSTERING ORDER BY (at DESC);
    ]],
    teardown = function(connector)
      -- Risky migrations
    end
  }
}
