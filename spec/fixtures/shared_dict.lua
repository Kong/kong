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
  "kong_mock_upstream_loggers 10m",
  "kong_secrets 5m",
  "test_vault 5m",
  "prometheus_metrics 5m",
  "lmdb_mlcache 1m",
  "kong_test_cp_mock 1m",

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
}

for i, v in ipairs(dicts) do
  dicts[i] = " --shdict '" .. v .. "' "
end

return table.concat(dicts, " ")
