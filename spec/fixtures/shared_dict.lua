-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- generate resty `--shdict` options executed by bin/busted

local dicts = {
  -- http shared dicts
  "kong 5m",
  "kong_locks 8m",
  "kong_healthchecks 5m",
  "kong_cluster_events 5m",
  "kong_rate_limiting_counters 12m",
  "kong_core_db_cache 16m",
  "kong_core_db_cache_miss 16m",
  "kong_db_cache 16m",
  "kong_db_cache_2 16m",
  "kong_db_cache_miss 12m",
  "kong_db_cache_miss_2 12m",
  "kong_dns_cache 5m",
  "kong_mock_upstream_loggers 10m",
  "kong_secrets 5m",
  "test_vault 5m",
  "prometheus_metrics 5m",
  "lmdb_mlcache 5m",
  "kong_test_cp_mock 1m",

  --- XXX EE http shared dicts
  "kong_counters 1m",
  "kong_vitals 1m",
  "kong_vitals_lists 1m",
  "kong_vitals_counters 50m",
  "kong_reports_consumers 10m",
  "kong_reports_routes 1m",
  "kong_reports_services 1m",
  "kong_reports_workspaces 1m",
  "kong_keyring 5m",
  "kong_test_rla_schema_abcd 1m",

  -- stream shared dicts
  "stream_kong 5m",
  "stream_kong_locks 8m",
  "stream_kong_healthchecks 5m",
  "stream_kong_cluster_events 5m",
  "stream_kong_rate_limiting_counters 12m",
  "stream_kong_core_db_cache 16m",
  "stream_kong_core_db_cache_miss 16m",
  "stream_kong_db_cache 16m",
  "stream_kong_db_cache_2 16m",
  "stream_kong_db_cache_miss 12m",
  "stream_kong_db_cache_miss_2 12m",
  "stream_kong_secrets 5m",
  "stream_prometheus_metrics 5m",

  --- XXX EE stream shared dicts
  "stream_kong_counters 50m",
  "stream_kong_vitals 1m",
  "stream_kong_vitals_lists 1m",
  "stream_kong_vitals_counters 50m",
  "stream_kong_keyring 5m",
}

for i, v in ipairs(dicts) do
  dicts[i] = " --shdict '" .. v .. "' "
end

return table.concat(dicts, " ")
