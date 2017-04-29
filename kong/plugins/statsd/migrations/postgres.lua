return {
  {
    name = "2017-01-31-160000_statsd_schema_changes",
    up = function(_, _, dao)
      local rows, err = dao.plugins:find_all {name = "statsd"}
      if err then return err end

      local default_metrics = {
        {
          name = "request_count",
          stat_type = "counter",
          sample_rate = 1
        },
        {
          name = "latency",
          stat_type = "timer"
        },
        {
          name = "request_size",
          stat_type = "timer"
        },
        {
          name = "status_count",
          stat_type = "counter",
          sample_rate = 1
        },
        {
          name = "response_size",
          stat_type = "timer"
        },
        {
          name = "unique_users",
          stat_type = "set",
          consumer_identifier = "custom_id"
        },
        {
          name = "request_per_user",
          stat_type = "counter",
          sample_rate = 1,
          consumer_identifier = "custom_id"
        },
        {
          name = "upstream_latency",
          stat_type = "timer"
        },
        {
          name = "kong_latency",
          stat_type = "timer"
        },
        {
          name = "status_count_per_user",
          stat_type = "counter",
          sample_rate = 1,
          consumer_identifier = "custom_id"
        }
      }


      for i = 1, #rows do
        local statsd = rows[i]

        -- Delete the old one to avoid conflicts when inserting the new one
        local _, err = dao.plugins:delete(statsd)
        if err then return err end

        local _, err = dao.plugins:insert {
          name = "statsd",
          api_id = statsd.api_id,
          enabled = statsd.enabled,
          config = {
            host = statsd.config.host,
            port = statsd.config.port,
            metrics = default_metrics
          }
        }
        if err then return err end
      end
    end
  }
}
