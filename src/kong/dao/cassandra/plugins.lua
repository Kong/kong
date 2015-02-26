local constants = require "kong.constants"
local schemas = require "kong.dao.schemas"
local BaseDao = require "kong.dao.cassandra.base_dao"
local cjson = require "cjson"

local error_types = constants.DATABASE_ERROR_TYPES

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
  application_id = { type = "id", foreign = true, queryable = true },
  name = { required = true, queryable = true, immutable = true },
  value = { type = "table", required = true, schema = load_value_schema },
  enabled = { type = "boolean", default = true },
  created_at = { type = "timestamp" }
}

local Plugins = BaseDao:extend()

function Plugins:new(properties)
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
    delete = {
      params = { "id" },
      query = [[ DELETE FROM plugins WHERE id = ?; ]]
    },
    __custom_checks = {
      unique = {
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

function Plugins:_check_unicity(t, is_updating)
  local unique, err = self:_check_unique(self._statements.__custom_checks.unique, t, is_updating)
  if err then
    return false, err
  elseif not unique then
    return false, self:_build_error(error_types.UNIQUE, "Plugin already exists")
  else
    return true
  end
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

-- @override
function Plugins:insert(t)
  if t.application_id == nil then
    t.application_id = constants.DATABASE_NULL_ID
  end

  local valid_schema, err = schemas.validate(t, self._schema)
  if not valid_schema then
    return nil, self:_build_error(error_types.SCHEMA, err)
  end

  -- Checking plugin unicity
  local ok, err = self:_check_unicity(t)
  if not ok then
    return nil, err
  end

  return Plugins.super.insert(self, t)
end

-- @override
function Plugins:update(t)
  if t.application_id == nil then
    t.application_id = constants.DATABASE_NULL_ID
  end

  local valid_schema, err = schemas.validate(t, self._schema, true)
  if not valid_schema then
    return nil, self:_build_error(error_types.SCHEMA, err)
  end

  -- Checking plugin unicity
  local ok, err = self:_check_unicity(t, true)
  if not ok then
    return nil, err
  end

  return Plugins.super.update(self, t)
end

return Plugins
