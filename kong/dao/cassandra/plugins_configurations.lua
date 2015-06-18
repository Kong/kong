local plugins_configurations_schema = require "kong.dao.schemas.plugins_configurations"
local query_builder = require "kong.dao.cassandra.query_builder"
local constants = require "kong.constants"
local BaseDao = require "kong.dao.cassandra.base_dao"
local cjson = require "cjson"

local PluginsConfigurations = BaseDao:extend()

function PluginsConfigurations:new(properties)
  self._table = "plugins_configurations"
  self._schema = plugins_configurations_schema

  PluginsConfigurations.super.new(self, properties)
end

-- @override
function PluginsConfigurations:_marshall(t)
  if type(t.value) == "table" then
    t.value = cjson.encode(t.value)
  end

  return t
end

-- @override
function PluginsConfigurations:_unmarshall(t)
  -- deserialize values (tables) string to json
  if type(t.value) == "string" then
    t.value = cjson.decode(t.value)
  end
  -- remove consumer_id if null uuid
  if t.consumer_id == constants.DATABASE_NULL_ID then
    t.consumer_id = nil
  end

  return t
end

-- @override
function PluginsConfigurations:update(t)
  if not t.consumer_id then
    t.consumer_id = constants.DATABASE_NULL_ID
  end
  return PluginsConfigurations.super.update(self, t)
end

function PluginsConfigurations:find_distinct()
  -- Open session
  local session, err = PluginsConfigurations.super._open_session(self)
  if err then
    return nil, err
  end

  local select_q = query_builder.select(self._table)

  -- Execute query
  local distinct_names = {}
  for _, rows, page, err in PluginsConfigurations.super.execute(self, select_q, nil, nil, {auto_paging=true}) do
    if err then
      return nil, err
    end
    for _, v in ipairs(rows) do
      -- Rows also contains other properties, so making sure it's a plugin
      if v.name then
        distinct_names[v.name] = true
      end
    end
  end

  -- Close session
  local socket_err = PluginsConfigurations.super._close_session(self, session)
  if socket_err then
    return nil, socket_err
  end

  local result = {}
  for k, _ in pairs(distinct_names) do
    table.insert(result, k)
  end

  return result, nil
end

return { plugins_configurations = PluginsConfigurations }
