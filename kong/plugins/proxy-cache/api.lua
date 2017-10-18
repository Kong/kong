local STRATEGY_PATH = "kong.plugins.proxy-cache.strategies"


local singletons = require "kong.singletons"


local cluster_events = singletons.cluster_events


local function broadcast_purge(plugin_id, cache_key)
  local data = string.format("%s:%s", plugin_id, cache_key or "nil")
  ngx.log(ngx.DEBUG, "[proxy-cache] broadcasting purge '", data, "'")
  return cluster_events:broadcast("proxy-cache:purge", data)
end


return {
  ["/proxy-cache"] = {
    resource = "proxy-cache",

    DELETE = function(_, dao, helpers)
      local rows, err = dao.plugins:find_all {
        name = "proxy-cache"
      }
      if err then
        return helpers.yield_error(err)
      end

      for _, row in ipairs(rows) do
        local conf = row.config
        local strategy = require(STRATEGY_PATH)({
          strategy_name = conf.strategy,
          strategy_opts = conf[conf.strategy],
        })

        strategy:flush(true)

        if require(STRATEGY_PATH).LOCAL_DATA_STRATEGIES[conf.strategy] then
          local ok, err = broadcast_purge(row.id, nil)
          if not ok then
            ngx.log(ngx.ERR, "failed broadcasting proxy cache purge to cluster: ",
                    err)
          end
        end
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end
  },
  ["/proxy-cache/:cache_key"] = {
    resource = "proxy-cache",

    GET = function(self, dao, helpers)
      local rows, err = dao.plugins:find_all {
        name = "proxy-cache",
      }
      if err then
        return helpers.yield_error(err)
      end

      for _, plugin in ipairs(rows) do
        local conf = plugin.config
        local strategy = require(STRATEGY_PATH)({
          strategy_name = conf.strategy,
          strategy_opts = conf[conf.strategy],
        })

        local cache_val, err = strategy:fetch(self.params.cache_key)
        if err and err ~= "request object not in cache" then
          return helpers.yield_error(err)
        end

        if cache_val then
          return helpers.responses.send_HTTP_OK(cache_val)
        end
      end

      -- fell through, not found
      return helpers.responses.send_HTTP_NOT_FOUND()
    end,

    DELETE = function(self, dao, helpers)
      local rows, err = dao.plugins:find_all {
        name = "proxy-cache",
      }
      if err then
        return helpers.yield_error(err)
      end

      for _, plugin in ipairs(rows) do
        local conf = plugin.config
        local strategy = require(STRATEGY_PATH)({
          strategy_name = conf.strategy,
          strategy_opts = conf[conf.strategy],
        })

        local cache_val, err = strategy:fetch(self.params.cache_key)
        if err and err ~= "request object not in cache" then
          return helpers.yield_error(err)
        end

        if cache_val then
          local _, err = strategy:purge(self.params.cache_key)
          if err then
            return helpers.yield_error(err)
          end

          if require(STRATEGY_PATH).LOCAL_DATA_STRATEGIES[conf.strategy] then
            local ok, err = broadcast_purge(plugin.id, self.params.cache_key)
            if not ok then
              ngx.log(ngx.ERR, "failed broadcasting proxy cache purge to cluster: ",
                      err)
            end
          end

          return helpers.responses.send_HTTP_NO_CONTENT()
        end
      end

      -- fell through, not found
      return helpers.responses.send_HTTP_NOT_FOUND()
    end,
  },
  ["/proxy-cache/:plugin_id/caches/:cache_key"] = {
    resource = "proxy-cache",

    GET = function(self, dao, helpers)
      local rows, err = dao.plugins:find_all {
        id   = self.params.plugin_id,
        name = "proxy-cache"
      }
      if err then
        return helpers.yield_error(err)
      end

      if #rows == 0 then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local conf = rows[1].config
      local strategy = require(STRATEGY_PATH)({
        strategy_name = conf.strategy,
        strategy_opts = conf[conf.strategy],
      })

      local cache_val, err = strategy:fetch(self.params.cache_key)
      if err == "request object not in cache" then
        return helpers.responses.send_HTTP_NOT_FOUND()
      elseif err then
        return helpers.yield_error(err)
      end

      return helpers.responses.send_HTTP_OK(cache_val)
    end,
    DELETE = function(self, dao, helpers)
      local rows, err = dao.plugins:find_all {
        id   = self.params.plugin_id,
        name = "proxy-cache"
      }
      if err then
        return helpers.yield_error(err)
      end

      if #rows == 0 then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local conf = rows[1].config
      local strategy = require(STRATEGY_PATH)({
        strategy_name = conf.strategy,
        strategy_opts = conf[conf.strategy],
      })

      local _, err = strategy:fetch(self.params.cache_key)
      if err == "request object not in cache" then
        return helpers.responses.send_HTTP_NOT_FOUND()
      elseif err then
        return helpers.yield_error(err)
      end

      local _, err = strategy:purge(self.params.cache_key)
      if err then
        return helpers.yield_error(err)
      end

      if require(STRATEGY_PATH).LOCAL_DATA_STRATEGIES[conf.strategy] then
        local ok, err = broadcast_purge(rows[1].id, self.params.cache_key)
        if not ok then
          ngx.log(ngx.ERR, "failed broadcasting proxy cache purge to cluster: ",
                  err)
        end
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end
  },
}
