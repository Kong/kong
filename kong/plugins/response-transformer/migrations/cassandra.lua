return {
  {
    name = "2016-03-10-160000_resp_trans_schema_changes",
    up = function(_, _, factory)

      local plugins, err = factory.plugins:find_all {name = "response-transformer"}
      if err then
        return err
      end

      for _, plugin in ipairs(plugins) do
        for _, action in ipairs {"remove", "add", "append", "replace"} do
          plugin.config[action] = plugin.config[action] or {}

          for _, location in ipairs {"json", "headers"} do
            plugin.config[action][location] = plugin.config[action][location] or {}
          end
        end
        local _, err = factory.plugins:update(plugin, plugin, {full = true})
        if err then
          return err
        end
      end
    end,
    down = function(_, _, factory)
      local plugins, err = factory.plugins:find_all {name = "response-transformer"}
      if err then
        return err
      end

      for _, plugin in ipairs(plugins) do
        plugin.config.replace = nil
        plugin.config.append = nil

        for _, action in ipairs {"remove", "add"} do
          for _, location in ipairs {"json", "headers"} do
            if plugin.config[action] ~= nil and next(plugin.config[action][location]) == nil then
              plugin.config[action][location] = nil
            end
          end

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
