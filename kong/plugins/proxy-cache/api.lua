local STRATEGY_PATH = "kong.plugins.proxy-cache.strategies"


return {
  ["/proxy-cache"] = {
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
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end
  },
  ["/proxy-cache/:plugin_id/caches/:cache_key"] = {
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

      return helpers.responses.send_HTTP_NO_CONTENT()
    end
  },
}
