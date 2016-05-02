return {
  {
    name = "2016-03-10-160000_req_trans_schema_changes",
    up = function(_, _, factory)

      local plugins, err = factory.plugins:find_all {name = "request-transformer"}
      if err then
        return err
      end

      for _, plugin in ipairs(plugins) do
        for _, action in ipairs {"remove", "add", "append", "replace"} do
          plugin.config[action] = plugin.config[action] or {}

          for _, location in ipairs {"body", "headers", "querystring"} do
            plugin.config[action][location] = plugin.config[action][location] or {}
          end

          if plugin.config[action].form ~= nil then
            plugin.config[action].body = plugin.config[action].form
            plugin.config[action].form = nil
          end
        end
        local _, err = factory.plugins:update(plugin, plugin, {full = true})
        if err then
          return err
        end
      end
    end,
    down = function(_, _, factory)
      local plugins, err = factory.plugins:find_all {name = "request-transformer"}
      if err then
        return err
      end

      for _, plugin in ipairs(plugins) do
        plugin.config.replace = nil
        plugin.config.append = nil

        for _, action in ipairs {"remove", "add"} do
          for _, location in ipairs {"body", "headers", "querystring"} do
            if plugin.config[action] ~= nil and next(plugin.config[action][location]) == nil then
              plugin.config[action][location] = nil
            end
          end

          if next(plugin.config[action].body) ~= nil then
            plugin.config[action].form = plugin.config[action].body
          end

          plugin.config[action].body = nil

          if next(plugin.config[action]) == nil then
            plugin.config[action] = nil
          end
        end
        local _, err = factory.plugins:update(plugin, plugin, {full = true})
        if err then
          return err
        end
      end
    end
  }
}
