-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local STRATEGY_PATH = "kong.plugins.proxy-cache-advanced.strategies"

local require = require
local kong = kong
local fmt = string.format
local HTTP_INTERNAL_SERVER_ERROR_MSG = "An unexpected error occurred"


local function broadcast_purge(plugin_id, cache_key)
  local data = fmt("%s:%s", plugin_id, cache_key or "nil")
  kong.log.debug("broadcasting purge '", data, "'")
  return kong.cluster_events:broadcast("proxy-cache-advanced:purge", data)
end



local function each_by_name(entity, name)
  local iter = entity:each()  -- like each(page_size)
  local function iterator()
    local element, err = iter()
    if err then return nil, err end
    if element == nil then return end
    if element.name == name then return element, nil end
    return iterator()
  end

  return iterator
end


return {
  ["/proxy-cache-advanced"] = {
    DELETE = function()
      for row, err in each_by_name(kong.db.plugins, "proxy-cache-advanced") do
        if err then
          return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
        end

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
            kong.log.err("failed broadcasting proxy cache purge to cluster: ", err)
          end
        end
      end

      return kong.response.exit(204)
    end
  },
  ["/proxy-cache-advanced/:cache_key"] = {
    GET = function(self)
      for plugin, err in each_by_name(kong.db.plugins, "proxy-cache-advanced") do
        if err then
          return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
        end

        local conf = plugin.config
        local strategy = require(STRATEGY_PATH)({
          strategy_name = conf.strategy,
          strategy_opts = conf[conf.strategy],
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
      for plugin, err in each_by_name(kong.db.plugins, "proxy-cache-advanced") do
        if err then
          return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
        end

        local conf = plugin.config
        local strategy = require(STRATEGY_PATH)({
          strategy_name = conf.strategy,
          strategy_opts = conf[conf.strategy],
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

          if require(STRATEGY_PATH).LOCAL_DATA_STRATEGIES[conf.strategy] then
            local ok, err = broadcast_purge(plugin.id, self.params.cache_key)
            if not ok then
              kong.log.err("failed broadcasting proxy cache purge to cluster: ", err)
            end
          end

          return kong.response.exit(204)
        end
      end

      -- fell through, not found
      return kong.response.exit(404)
    end,
  },
  ["/proxy-cache-advanced/:plugin_id/caches/:cache_key"] = {
    GET = function(self)
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

      local cache_val, err = strategy:fetch(self.params.cache_key)
      if err == "request object not in cache" then
        return kong.response.exit(404)
      elseif err then
        return kong.response.exit(500, err)
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
        return kong.response.exit(500, err)
      end

      local _, err = strategy:purge(self.params.cache_key)
      if err then
        return kong.response.exit(500, err)
      end

      if require(STRATEGY_PATH).LOCAL_DATA_STRATEGIES[conf.strategy] then
        local ok, err = broadcast_purge(row.id, self.params.cache_key)
        if not ok then
          kong.log.err("failed broadcasting proxy cache purge to cluster: ", err)
        end
      end

      return kong.response.exit(204)
    end
  },
}
