local Migrations = {
  {
    name = "2015-12-03-161400_mashape-analytics-config",
    up = function(options, dao_factory)
      local schema = require "kong.plugins.mashape-analytics.schema"

      local plugins, err = dao_factory.plugins:find_by_keys {name = "mashape-analytics"}
      if err then
        return err
      end

      for _, plugin in ipairs(plugins) do
        plugin.config.host = plugin.config.host or schema.fields.host.default
        plugin.config.port = plugin.config.port or schema.fields.port.default
        plugin.config.path = plugin.config.path or schema.fields.path.default
        plugin.config.max_sending_queue_size = plugin.config.max_sending_queue_size or schema.fields.max_sending_queue_size.default
        local _, err = dao_factory.plugins:update(plugin)
        if err then
          return err
        end
      end
    end,
    down = function(options, dao_factory)
      local plugins, err = dao_factory.plugins:find_by_keys {name = "mashape-analytics"}
      if err then
        return err
      end

      for _, plugin in ipairs(plugins) do
        plugin.config.host = nil
        plugin.config.port = nil
        plugin.config.path = nil
        plugin.config.max_sending_queue_size = nil
        local _, err = dao_factory.plugins:update(plugin, true)
        if err then
          return err
        end
      end
    end
  }
}

return Migrations
