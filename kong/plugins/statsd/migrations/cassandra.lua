return {
  {
    name = "2017-06-09-160000_statsd_schema_changes",
    up = function(_, _, dao)

      local plugins, err = dao.plugins:find_all { name = "statsd" }
      if err then
        return err
      end

      local default_metrics = {
        request_count = {
          name        = "request_count",
          stat_type   = "counter",
          sample_rate = 1,
        },
        latency = {
          name      = "latency",
          stat_type = "gauge",
          sample_rate = 1,
        },
        request_size = {
          name      = "request_size",
          stat_type = "gauge",
          sample_rate = 1,
        },
        status_count = {
          name        = "status_count",
          stat_type   = "counter",
          sample_rate = 1,
        },
        response_size = {
          name      = "response_size",
          stat_type = "timer",
        },
        unique_users = {
          name                = "unique_users",
          stat_type           = "set",
          consumer_identifier = "consumer_id",
        },
        request_per_user = {
          name                = "request_per_user",
          stat_type           = "counter",
          sample_rate         = 1,
          consumer_identifier = "consumer_id",
        },
        upstream_latency = {
          name      = "upstream_latency",
          stat_type = "gauge",
          sample_rate = 1,
        },
      }

      for i = 1, #plugins do
        local statsd = plugins[i]
        local _, err = dao.plugins:delete(statsd)
        if err then
          return err
        end

        local new_metrics = {}
        if statsd.config.metrics then
          for _, metric in ipairs(statsd.config.metrics) do
            local new_metric = default_metrics[metric]
            if new_metric then
              table.insert(new_metrics, new_metric)
            end
          end
        end

        local _, err = dao.plugins:insert {
          name    = "statsd",
          api_id  = statsd.api_id,
          enabled = statsd.enabled,
          config  = {
            host    = statsd.config.host,
            port    = statsd.config.port,
            metrics = new_metrics,
            prefix  = "kong",
          }
        }

        if err then
          return err
        end
      end
    end
  },
  down = function()
  end,
}
