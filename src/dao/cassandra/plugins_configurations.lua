local constants = require "kong.constants"
local BaseDao = require "kong.dao.cassandra.base_dao"
local cjson = require "cjson"

local function load_value_schema(plugin_t)
  if plugin_t.name then
    local status, plugin_schema = pcall(require, "kong.plugins."..plugin_t.name..".schema")
    if status then
      return plugin_schema
    end
  end

  return nil, "Plugin \""..(plugin_t.name and plugin_t.name or "").."\" not found"
end

local SCHEMA = {
  id = { type = constants.DATABASE_TYPES.ID },
  api_id = { type = constants.DATABASE_TYPES.ID, required = true, foreign = true, queryable = true },
  application_id = { type = constants.DATABASE_TYPES.ID, foreign = true, queryable = true, default = constants.DATABASE_NULL_ID },
  name = { type = "string", required = true, queryable = true, immutable = true },
  value = { type = "table", required = true, schema = load_value_schema },
  enabled = { type = "boolean", default = true },
  created_at = { type = constants.DATABASE_TYPES.TIMESTAMP }
}

local PluginsConfigurations = BaseDao:extend()

function PluginsConfigurations:new(properties)
  self._entity = "Plugin"
  self._schema = SCHEMA
  self._queries = {
    insert = {
      params = { "id", "api_id", "application_id", "name", "value", "enabled", "created_at" },
      query = [[ INSERT INTO plugins_configurations(id, api_id, application_id, name, value, enabled, created_at)
                  VALUES(?, ?, ?, ?, ?, ?, ?); ]]
    },
    update = {
      params = { "api_id", "application_id", "value", "enabled", "created_at", "id", "name" },
      query = [[ UPDATE plugins_configurations SET api_id = ?, application_id = ?, value = ?, enabled = ?, created_at = ? WHERE id = ? AND name = ?; ]]
    },
    select = {
      query = [[ SELECT * FROM plugins_configurations %s; ]]
    },
    select_one = {
      params = { "id" },
      query = [[ SELECT * FROM plugins_configurations WHERE id = ?; ]]
    },
    delete = {
      params = { "id" },
      query = [[ DELETE FROM plugins_configurations WHERE id = ?; ]]
    },
    __unique = {
      self = {
        params = { "api_id", "application_id", "name" },
        query = [[ SELECT * FROM plugins_configurations WHERE api_id = ? AND application_id = ? AND name = ? ALLOW FILTERING; ]]
      }
    },
    __foreign = {
      api_id = {
        params = { "api_id" },
        query = [[ SELECT id FROM apis WHERE id = ?; ]]
      },
      application_id = {
        params = { "application_id" },
        query = [[ SELECT id FROM applications WHERE id = ?; ]]
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
  -- remove application_id if null uuid
  if t.application_id == constants.DATABASE_NULL_ID then
    t.application_id = nil
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
  for _, rows, page, err in session:execute(self._statements.select.query, nil, {auto_paging=true}) do
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
  for k,_ in pairs(distinct_names) do
    table.insert(result, k)
  end

  return result, nil
end

return PluginsConfigurations
