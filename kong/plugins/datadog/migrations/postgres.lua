return {
  {
    name = "2017-06-09-160000_datadog_schema_changes",
    up = function(_, _, dao)

      local plugins, err = dao.plugins:find_all { name = "datadog" }
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
        local datadog = plugins[i]
        local _, err = dao.plugins:delete(datadog)
        if err then
          return err
        end

        local tags = datadog.config.tags or {}
        local new_metrics = {}
        if datadog.config.metrics then
          for _, metric in ipairs(datadog.config.metrics) do
            local new_metric = default_metrics[metric]
            if new_metric then
              new_metric.tags = tags[metric]
              table.insert(new_metrics, new_metric)
            end
          end
        end

        local _, err = dao.plugins:insert {
          name    = "datadog",
          api_id  = datadog.api_id,
          enabled = datadog.enabled,
          config  = {
            host    = datadog.config.host,
            port    = datadog.config.port,
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
