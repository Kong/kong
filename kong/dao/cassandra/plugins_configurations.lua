local plugins_configurations_schema = require "kong.dao.schemas.plugins_configurations"
local query_builder = require "kong.dao.cassandra.query_builder"
local constants = require "kong.constants"
local BaseDao = require "kong.dao.cassandra.base_dao"
local cjson = require "cjson"

local PluginsConfigurations = BaseDao:extend()

function PluginsConfigurations:new(properties)
  self._entity = "Plugin configuration"
  self._table = "plugins_configurations"
  self._schema = plugins_configurations_schema
  self._primary_key = {"id", "name"}
  self._queries = {
    __unique = {
      self = {
        args_keys = { "api_id", "consumer_id", "name" },
        query = [[ SELECT * FROM plugins_configurations WHERE api_id = ? AND consumer_id = ? AND name = ? ALLOW FILTERING; ]]
      }
    },
    __foreign = {
      api_id = {
        args_keys = { "api_id" },
        query = [[ SELECT id FROM apis WHERE id = ?; ]]
      },
      consumer_id = {
        args_keys = { "consumer_id" },
        query = [[ SELECT id FROM consumers WHERE id = ?; ]]
      }
    }
  }

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
function PluginsConfigurations:delete(where_t)
  return PluginsConfigurations.super.delete(self, {id = where_t.id})
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
  for _, rows, page, err in PluginsConfigurations.super._execute_kong_query(self, {query = select_q}, nil, {auto_paging=true}) do
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
