local utils = require("kong.tools.utils")


local fmt = string.format


local _M = {}


_M.STRATEGIES   = {
  ["postgres"]  = true,
  ["cassandra"] = true,
  ["off"] = true,
}


function _M.new(kong_config, database, schemas, errors)
  local database = database or kong_config.database

  if not _M.STRATEGIES[database] then
    error("unknown strategy: " .. database, 2)
  end

  -- strategy-specific connector with :connect() :setkeepalive() :query() ...
  local Connector = require(fmt("kong.db.strategies.%s.connector", database))

  -- strategy-specific automated CRUD query builder with :insert() :select()
  local Strategy = require(fmt("kong.db.strategies.%s", database))

  local connector, err = Connector.new(kong_config)
  if not connector then
    return nil, nil, err
  end

  do
    local base_connector = require "kong.db.strategies.connector"
    local mt = getmetatable(connector)
    setmetatable(mt, {
      __index = function(t, k)
        -- explicit parent
        if k == "super" then
          return base_connector
        end

        return base_connector[k]
      end
    })
  end

  local strategies = {}

  for _, schema in pairs(schemas) do
    local strategy, err = Strategy.new(connector, schema, errors)
    if not strategy then
      return nil, nil, err
    end

    local custom_strat = fmt("kong.db.strategies.%s.%s", database, schema.name)
    local exists, mod = utils.load_module_if_exists(custom_strat)
    if exists and mod then
      local parent_mt = getmetatable(strategy)
      local mt = {
        __index = function(t, k)
          -- explicit parent
          if k == "super" then
            return parent_mt
          end

          -- override
          local f = mod[k]
          if f then
            return f
          end

          -- parent fallback
          return parent_mt[k]
        end
      }

      setmetatable(strategy, mt)
    end

    strategies[schema.name] = strategy
  end

  return connector, strategies
end


return _M

