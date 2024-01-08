--- resty options executed by bin/busted
return
  -- http shared dicts
  "--shdict 'kong 5m' " ..
  "--shdict 'kong_db_cache 16m' " ..
  "--shdict 'kong_db_cache_2 16m' " ..
  "--shdict 'kong_db_cache_miss 12m' " ..
  "--shdict 'kong_db_cache_miss_2 12m' " ..
  "--shdict 'kong_secrets 5m' " ..
  "--shdict 'kong_locks 8m' " ..
  "--shdict 'kong_cluster_events 5m' " ..
  "--shdict 'kong_healthchecks 5m' " ..
  "--shdict 'kong_rate_limiting_counters 12m' " ..
  "--shdict 'kong_mock_upstream_loggers 10m' " ..
  "--shdict 'stream_kong 5m' " ..

  -- stream shared dicts
  "--shdict 'stream_kong_db_cache 16m' " ..
  "--shdict 'stream_kong_db_cache_2 16m' " ..
  "--shdict 'stream_kong_db_cache_miss 12m' " ..
  "--shdict 'stream_kong_db_cache_miss_2 12m' " ..
  "--shdict 'stream_kong_locks 8m' " ..
  "--shdict 'stream_kong_cluster_events 5m' " ..
  "--shdict 'stream_kong_healthchecks 5m' " ..
  "--shdict 'stream_kong_rate_limiting_counters 12m' " ..
  "--shdict 'stream_prometheus_metrics 5m' "  ..

  -- other shared dicts
  "--shdict 'test_vault 5m' " ..
  "--shdict 'prometheus_metrics 5m' "
