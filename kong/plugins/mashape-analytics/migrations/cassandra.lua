return {
  {
    name = "2015-12-03-161400_mashape-analytics-config",
    up = function(_, _, factory)
      local schema = require "kong.plugins.mashape-analytics.schema"

      local plugins, err = factory.plugins:find_all {name = "mashape-analytics"}
      if err then
        return err
      end

      for _, plugin in ipairs(plugins) do
        plugin.config.host = plugin.config.host or schema.fields.host.default
        plugin.config.port = plugin.config.port or schema.fields.port.default
        plugin.config.path = plugin.config.path or schema.fields.path.default
        plugin.config.max_sending_queue_size = plugin.config.max_sending_queue_size or schema.fields.max_sending_queue_size.default
        local _, err = factory.plugins:update(plugin, plugin, {full = true})
        if err then
          return err
        end
      end
    end,
    down = function(_, _, factory)
      local plugins, err = factory.plugins:find_all {name = "mashape-analytics"}
      if err then
        return err
      end

      for _, plugin in ipairs(plugins) do
        plugin.config.host = nil
        plugin.config.port = nil
        plugin.config.path = nil
        plugin.config.max_sending_queue_size = nil
        local _, err = factory.plugins:update(plugin, plugin, {full = true})
        if err then
          return err
        end
      end
    end
  }
}
