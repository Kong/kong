local constants = require "kong.constants"
local BaseDao = require "kong.dao.cassandra.base_dao"
local cjson = require "cjson"

local function load_value_schema(plugin_t)
  local status, plugin_schema = pcall(require, "kong.plugins."..plugin_t.name..".schema")
  if not status then
    return nil, "Plugin \""..plugin_t.name.."\" not found"
  end

  return plugin_schema
end

local SCHEMA = {
  id = { type = "id" },
  api_id = { type = "id", required = true, foreign = true, queryable = true },
  application_id = { type = "id", foreign = true, queryable = true, default = constants.DATABASE_NULL_ID },
  name = { required = true, queryable = true, immutable = true },
  value = { type = "table", required = true, schema = load_value_schema },
  enabled = { type = "boolean", default = true },
  created_at = { type = "timestamp" }
}

local Plugins = BaseDao:extend()

function Plugins:new(properties)
  self._entity = "Plugin"
  self._schema = SCHEMA
  self._queries = {
    insert = {
      params = { "id", "api_id", "application_id", "name", "value", "enabled", "created_at" },
      query = [[ INSERT INTO plugins(id, api_id, application_id, name, value, enabled, created_at)
                  VALUES(?, ?, ?, ?, ?, ?, ?); ]]
    },
    update = {
      params = { "api_id", "application_id", "value", "enabled", "created_at", "id", "name" },
      query = [[ UPDATE plugins SET api_id = ?, application_id = ?, value = ?, enabled = ?, created_at = ? WHERE id = ? AND name = ?; ]]
    },
    select = {
      query = [[ SELECT * FROM plugins %s; ]]
    },
    select_one = {
      params = { "id" },
      query = [[ SELECT * FROM plugins WHERE id = ?; ]]
    },
    select_distinct = {
      query = [[ SELECT DISTINCT name FROM plugins; ]]
    },
    delete = {
      params = { "id" },
      query = [[ DELETE FROM plugins WHERE id = ?; ]]
    },
    __unique = {
      self = {
        params = { "api_id", "application_id", "name" },
        query = [[ SELECT * FROM plugins WHERE api_id = ? AND application_id = ? AND name = ? ALLOW FILTERING; ]]
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

  Plugins.super.new(self, properties)
end

-- @override
function Plugins:_marshall(t)
  if type(t.value) == "table" then
    t.value = cjson.encode(t.value)
  end

  return t
end

-- @override
function Plugins:_unmarshall(t)
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

function Plugins:find_distinct()
  local plugins, err = Plugins.super._execute(self, self._statements.select_distinct)
  return plugins, err
end

return Plugins
