-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
