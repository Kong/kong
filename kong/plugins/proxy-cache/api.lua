local STRATEGY_PATH = "kong.plugins.proxy-cache.strategies"


local kong = kong
local cluster_events = kong.cluster_events


local function broadcast_purge(plugin_id, cache_key)
  local data = string.format("%s:%s", plugin_id, cache_key or "nil")
  ngx.log(ngx.DEBUG, "[proxy-cache] broadcasting purge '", data, "'")
  return cluster_events:broadcast("proxy-cache:purge", data)
end


return {
  ["/proxy-cache"] = {
    resource = "proxy-cache",

    DELETE = function()
      for plugin, err in kong.db.plugins:each(1000,
        { cache_key = "proxy-cache", }) do
        if err then
          return kong.response.exit(500, { message = err })
        end

        local strategy = require(STRATEGY_PATH)({
          strategy_name = plugin.config.strategy,
          strategy_opts = plugin.config[plugin.config.strategy],
        })

        local ok, err = strategy:flush(true)
        if not ok then
          return kong.response.exit(500, { message = err })
        end

        if require(STRATEGY_PATH).LOCAL_DATA_STRATEGIES[plugin.config.strategy]
        then
          local ok, err = broadcast_purge(plugin.id, nil)
          if not ok then
            ngx.log(ngx.ERR, "failed broadcasting proxy cache purge to ",
                    "cluster: ", err)
          end
        end

      end

      return kong.response.exit(204)
    end
  },
  ["/proxy-cache/:cache_key"] = {
    resource = "proxy-cache",

    GET = function(self)
      for plugin, err in kong.db.plugins:each(1000,
        { cache_key = "proxy-cache", }) do
        if err then
          return kong.response.exit(500, { message = err })
        end

        local strategy = require(STRATEGY_PATH)({
          strategy_name = plugin.config.strategy,
          strategy_opts = plugin.config[plugin.config.strategy],
        })

        local cache_val, err = strategy:fetch(self.params.cache_key)
        if err and err ~= "request object not in cache" then
          return kong.response.exit(500, err)
        end

        if cache_val then
          return kong.response.exit(200, cache_val)
        end

      end

      -- fell through, not found
      return kong.response.exit(404)
    end,

    DELETE = function(self)
      for plugin, err in kong.db.plugins:each(1000,
        { cache_key = "proxy-cache", }) do
        if err then
          return kong.response.exit(500, { message = err })
        end

        local strategy = require(STRATEGY_PATH)({
          strategy_name = plugin.config.strategy,
          strategy_opts = plugin.config[plugin.config.strategy],
        })

        local cache_val, err = strategy:fetch(self.params.cache_key)
        if err and err ~= "request object not in cache" then
          return kong.response.exit(500, err)
        end

        if cache_val then
          local _, err = strategy:purge(self.params.cache_key)
          if err then
            return kong.response.exit(500, err)
          end

          if require(STRATEGY_PATH).LOCAL_DATA_STRATEGIES[plugin.config.strategy]
          then
            local ok, err = broadcast_purge(plugin.id, self.params.cache_key)
            if not ok then
              ngx.log(ngx.ERR,
                      "failed broadcasting proxy cache purge to cluster: ", err)
            end
          end

          return kong.response.exit(204)
        end

      end

      -- fell through, not found
      return kong.response.exit(404)
    end,
  },
  ["/proxy-cache/:plugin_id/caches/:cache_key"] = {
    resource = "proxy-cache",

    GET = function(self)
      local plugin, err = kong.db.plugins:select {
        id   = self.params.plugin_id,
      }
      if err then
        return kong.response.exit(500, err)
      end

      if not plugin then
        return kong.response.exit(404)
      end

      local conf = plugin.config
      local strategy = require(STRATEGY_PATH)({
        strategy_name = conf.strategy,
        strategy_opts = conf[conf.strategy],
      })

      local cache_val, err = strategy:fetch(self.params.cache_key)
      if err == "request object not in cache" then
        return kong.response.exit(404)
      elseif err then
        return kong.response.exit(500, err)
      end

      return kong.response.exit(200, cache_val)
    end,
    DELETE = function(self)
      local plugin, err = kong.db.plugins:select {
        id   = self.params.plugin_id,
      }
      if err then
        return kong.response.exit(500, err)
      end

      if not plugin then
        return kong.response.exit(404)
      end

      local conf = plugin.config
      local strategy = require(STRATEGY_PATH)({
        strategy_name = conf.strategy,
        strategy_opts = conf[conf.strategy],
      })

      local _, err = strategy:fetch(self.params.cache_key)
      if err == "request object not in cache" then
        return kong.response.exit(404)
      elseif err then
        return kong.response.exit(500, err)
      end

      local _, err = strategy:purge(self.params.cache_key)
      if err then
        return kong.response.exit(500, err)
      end

      if require(STRATEGY_PATH).LOCAL_DATA_STRATEGIES[conf.strategy] then
        local ok, err = broadcast_purge(plugin.id, self.params.cache_key)
        if not ok then
          ngx.log(ngx.ERR, "failed broadcasting proxy cache purge to cluster: ",
                  err)
        end
      end

      return kong.response.exit(204)
    end
  },
}
