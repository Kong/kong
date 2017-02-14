return {
  {
    name = "2017-01-31-160000_statsd_schema_changes",
    up = function(_, _, factory)

      local plugins, err = factory.plugins:find_all {name = "statsd"}
      if err then
        return err
      end
      
      local default_metrics = {
        request_count = {
          name = "request_count",
          stat_type = "counter",
          sample_rate = 1
        },
        latency = {
          name = "latency",
          stat_type = "timer"
        },
        request_size = {
          name = "request_size",
          stat_type = "timer"
        },
        status_count = {
          name = "status_count",
          stat_type = "counter",
          sample_rate = 1
        },
        response_size = {
          name = "response_size",
          stat_type = "timer"
        },
        unique_users = {
          name = "unique_users",
          stat_type = "set",
          consumer_identifier = "custom_id"
        },
        request_per_user = {
          name = "request_per_user",
          stat_type = "counter",
          sample_rate = 1,
          consumer_identifier = "custom_id"
        }
      }
      
      for _, plugin in ipairs(plugins) do
        local new_metrics = {}
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