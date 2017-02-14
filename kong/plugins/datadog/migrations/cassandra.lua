return {
  {
    name = "2017-02-09-160000_datadog_schema_changes",
    up = function(_, _, factory)

      local plugins, err = factory.plugins:find_all {name = "datadog"}
      if err then
        return err
      end
      
      local default_metrics = {
        request_count = {
          name = "request_count",
          stat_type = "counter",
          sample_rate = 1,
          tags = {"app:kong"}
        },
        latency = {
          name = "latency",
          stat_type = "timer",
          tags = {"app:kong"}
        },
        request_size = {
          name = "request_size",
          stat_type = "timer",
          tags = {"app:kong"}
        },
        status_count = {
          name = "status_count",
          stat_type = "counter",
          sample_rate = 1,
          tags = {"app:kong"}
        },
        response_size = {
          name = "response_size",
          stat_type = "timer",
          tags = {"app:kong"}
        },
        unique_users = {
          name = "unique_users",
          stat_type = "set",
          consumer_identifier = "consumer_id",
          tags = {"app:kong"}
        },
        request_per_user = {
          name = "request_per_user",
          stat_type = "counter",
          sample_rate = 1,
          consumer_identifier = "consumer_id",
          tags = {"app:kong"}
        },
        upstream_latency = {
          name = "upstream_latency",
          stat_type = "timer",
          tags = {"app:kong"}
        },
        kong_latency = {
          name = "kong_latency",
          stat_type = "timer",
          tags = {"app:kong"}
        },
        status_count_per_user = {
          name = "status_count_per_user",
          stat_type = "counter",
          sample_rate = 1,
          consumer_identifier = "consumer_id",
          tags = {"app:kong"}
        }
      }
      
      for _, plugin in ipairs(plugins) do
        local new_metrics = {}
        plugin.config.tags = nil
        plugin.config.timeout = nil
        if plugin.config.metrics ~=nil then
          for _, metric in ipairs(plugin.config.metrics) do
            table.insert(new_metrics, default_metrics[metric])
          end
          plugin.config.metrics = new_metrics
          local _, err = factory.plugins:update(plugin, plugin, {full = true})
          if err then
            return err
          end
        end
      end
    end
  }
}
