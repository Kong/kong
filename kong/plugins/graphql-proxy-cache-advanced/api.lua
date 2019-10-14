local STRATEGY_PATH = "kong.plugins.graphql-proxy-cache-advanced.strategies"


local kong = kong
local cluster_events = kong.cluster_events

local HTTP_INTERNAL_SERVER_ERROR_MSG = "An unexpected error occurred"


local function broadcast_purge(plugin_id, cache_key)
  local data = string.format("%s:%s", plugin_id, cache_key or "nil")
  ngx.log(ngx.DEBUG, "[graphql-proxy-cache-advanced] broadcasting purge '", data, "'")
  return cluster_events:broadcast("graphql-proxy-cache-advanced:purge", data)
end


return {
  ["/graphql-proxy-cache-advanced"] = {
    resource = "graphql-proxy-cache-advanced",

    DELETE = function()
      local rows, err = kong.db.plugins:select_all {
        name = "graphql-proxy-cache-advanced"
      }
      if err then
        return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
      end

      for _, row in ipairs(rows) do
        local conf = row.config
        local strategy = require(STRATEGY_PATH)({
          strategy_name = conf.strategy,
          strategy_opts = conf[conf.strategy],
        })

        local ok, err = strategy:flush(true)
        if not ok then
          return kong.response.exit(500, { message = err })
        end

        if require(STRATEGY_PATH).LOCAL_DATA_STRATEGIES[conf.strategy] then
          local ok, err = broadcast_purge(row.id, nil)
          if not ok then
            ngx.log(ngx.ERR, "failed broadcasting gql proxy cache purge to cluster: ",
                err)
          end
        end
      end

      return kong.response.exit(204)
    end
  },
  ["/graphql-proxy-cache-advanced/:cache_key"] = {
    resource = "graphql-proxy-cache-advanced",

    GET = function(self)
      local rows, err = kong.db.plugins:select_all {
        name = "graphql-proxy-cache-advanced",
      }
      if err then
        return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
      end

      for _, plugin in ipairs(rows) do
        local conf = plugin.config
        local strategy = require(STRATEGY_PATH)({
          strategy_name = conf.strategy,
          strategy_opts = conf[conf.strategy],
        })

        local cache_val, err = strategy:fetch(self.params.cache_key)
        if err and err ~= "request object not in cache" then
          return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
        end

        if cache_val then
          return kong.response.exit(200, cache_val)
        end
      end

      -- fell through, not found
      return kong.response.exit(404)
    end,

    DELETE = function(self)
      local rows, err = kong.db.plugins:select_all {
        name = "graphql-proxy-cache-advanced",
      }
      if err then
        return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
      end

      for _, plugin in ipairs(rows) do
        local conf = plugin.config
        local strategy = require(STRATEGY_PATH)({
          strategy_name = conf.strategy,
          strategy_opts = conf[conf.strategy],
        })

        local cache_val, err = strategy:fetch(self.params.cache_key)
        if err and err ~= "request object not in cache" then
          return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
        end

        if cache_val then
          local _, err = strategy:purge(self.params.cache_key)
          if err then
            return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
          end

          if require(STRATEGY_PATH).LOCAL_DATA_STRATEGIES[conf.strategy] then
            local ok, err = broadcast_purge(plugin.id, self.params.cache_key)
            if not ok then
              ngx.log(ngx.ERR, "failed broadcasting gql proxy cache purge to cluster: ",
                  err)
            end
          end

          return kong.response.exit(204)
        end
      end

      -- fell through, not found
      return kong.response.exit(404)
    end,
  },
  ["/graphql-proxy-cache-advanced/:plugin_id/caches/:cache_key"] = {
    resource = "graphql-proxy-cache-advanced",

    GET = function(self)
      local row, err = kong.db.plugins:select {
        id   = self.params.plugin_id,
      }
      if err then
        return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
      end

      if not row then
        return kong.response.exit(404)
      end

      local conf = row.config
      local strategy = require(STRATEGY_PATH)({
        strategy_name = conf.strategy,
        strategy_opts = conf[conf.strategy],
      })

      local cache_val, err = strategy:fetch(self.params.cache_key)
      if err == "request object not in cache" then
        return kong.response.exit(404)
      elseif err then
        return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
      end

      return kong.response.exit(200, cache_val)
    end,
    DELETE = function(self)
      local row, err = kong.db.plugins:select {
        id   = self.params.plugin_id,
      }
      if err then
        return kong.response.exit(500, err)
      end

      if not row then
        return kong.response.exit(404)
      end

      local conf = row.config
      local strategy = require(STRATEGY_PATH)({
        strategy_name = conf.strategy,
        strategy_opts = conf[conf.strategy],
      })

      local _, err = strategy:fetch(self.params.cache_key)
      if err == "request object not in cache" then
        return kong.response.exit(404)
      elseif err then
        return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
      end

      local _, err = strategy:purge(self.params.cache_key)
      if err then
        return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
      end

      if require(STRATEGY_PATH).LOCAL_DATA_STRATEGIES[conf.strategy] then
        local ok, err = broadcast_purge(row.id, self.params.cache_key)
        if not ok then
          ngx.log(ngx.ERR, "failed broadcasting gql proxy cache purge to cluster: ",
              err)
        end
      end

      return kong.response.exit(204)
    end
  },
}
