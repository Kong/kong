local plugins_configurations_schema = require "kong.dao.schemas.plugins_configurations"
local constants = require "kong.constants"
local BaseDao = require "kong.dao.cassandra.base_dao"
local cjson = require "cjson"

local PluginsConfigurations = BaseDao:extend()

function PluginsConfigurations:new(properties)
  self._entity = "Plugin configuration"
  self._schema = plugins_configurations_schema
  self._queries = {
    insert = {
      args_keys = { "id", "api_id", "consumer_id", "name", "value", "enabled", "created_at" },
      query = [[ INSERT INTO plugins_configurations(id, api_id, consumer_id, name, value, enabled, created_at)
                  VALUES(?, ?, ?, ?, ?, ?, ?); ]]
    },
    update = {
      args_keys = { "api_id", "consumer_id", "value", "enabled", "created_at", "id", "name" },
      query = [[ UPDATE plugins_configurations SET api_id = ?, consumer_id = ?, value = ?, enabled = ?, created_at = ? WHERE id = ? AND name = ?; ]]
    },
    select = {
      query = [[ SELECT * FROM plugins_configurations %s; ]]
    },
    select_one = {
      args_keys = { "id" },
      query = [[ SELECT * FROM plugins_configurations WHERE id = ?; ]]
    },
    delete = {
      args_keys = { "id" },
      query = [[ DELETE FROM plugins_configurations WHERE id = ?; ]]
    },
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

function PluginsConfigurations:find_distinct()
  -- Open session
  local session, err = PluginsConfigurations.super._open_session(self)
  if err then
    return nil, err
  end

  -- Execute query
  local distinct_names = {}
  for _, rows, page, err in session:execute(string.format(self._queries.select.query, ""), nil, {auto_paging=true}) do
    if err then
      return nil, err
    end
    for _, v in ipairs(rows) do
      -- Rows also contains other properites, so making sure it's a plugin
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

return PluginsConfigurations
