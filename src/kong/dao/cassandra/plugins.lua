local constants = require "constants"
local schemas = require "kong.dao.schemas"
local BaseDao = require "kong.dao.cassandra.base_dao"

local error_types = constants.DATABASE_ERROR_TYPES

local SCHEMA = {
  id = { type = "id" },
  api_id = { type = "id", required = true, foreign = true, queryable = true },
  application_id = { type = "id", foreign = true, queryable = true },
  name = { required = true, queryable = true },
  value = { type = "table", required = true },
  created_at = { type = "timestamp" }
}

local Plugins = BaseDao:extend()

function Plugins:new(database, properties)
  self._schema = SCHEMA
  self._deserialize = true
  self._queries = {
    insert = {
      params = { "id", "api_id", "application_id", "name", "value", "created_at" },
      query = [[ INSERT INTO plugins(id, api_id, application_id, name, value, created_at)
                  VALUES(?, ?, ?, ?, ?, ?); ]]
    },
    update = {
      params = { "application_id", "value", "created_at", "id" },
      query = [[ UPDATE plugins SET application_id = ?, value = ?, created_at = ? WHERE id = ?; ]]
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
      unique_application_id = {
        params = { "api_id", "application_id", "name" },
        query = [[ SELECT id FROM plugins WHERE api_id = ? AND application_id = ? AND name = ? ALLOW FILTERING; ]]
      },
      unique_no_application_id = {
        params = { "api_id", "name" },
        query = [[ SELECT id FROM plugins WHERE api_id = ? AND name = ? ALLOW FILTERING; ]]
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

  Plugins.super.new(self, database)
end

local function check_value_schema(t)
  local status, plugin_schema = pcall(require, "kong.plugins."..t.name..".schema")
  if not status then
    return false, self:_build_error(error_types.SCHEMA, "Plugin \""..object.name.."\" not found")
  end

  local valid, errors = schemas.validate(t.value, plugin_schema)
  if not valid then
    return false, self:_build_error(error_types.SCHEMA, err)
  else
    return true
  end
end

function Plugins:_check_unicity(t, is_updating)
  local unique_statement

  if not t.application_id then
    unique_statement = self._statements.__custom_checks.unique_no_application_id
  else
    unique_statement = self._statements.__custom_checks.unique_application_id
  end

  local unique, err = self:_check_unique(unique_statement, t, is_updating)
  if err then
    return false, err
  elseif not unique then
    return false, self:_build_error(error_types.UNIQUE, "Plugin already exists")
  else
    return true
  end
end

function Plugins:insert(t)
  local valid_schema, err = schemas.validate(t, self._schema)
  if not valid_schema then
    return nil, self:_build_error(error_types.SCHEMA, err)
  end

  -- Checking plugin unicity
  local ok, err = self:_check_unicity(t)
  if not ok then
    return nil, err
  end

  -- Checking value schema validation
  local ok, err = check_value_schema(t)
  if not ok then
    return nil, err
  end

  return Plugins.super.insert(self, t)
end

function Plugins:update(t)
  local valid_schema, err = schemas.validate(t, self._schema)
  if not valid_schema then
    return nil, self:_build_error(error_types.SCHEMA, err)
  end

  -- Checking plugin unicity
  local ok, err = self:_check_unicity(t, true)
  if not ok then
    return nil, err
  end

  -- Checking value schema validation
  local ok, err = check_value_schema(t)
  if not ok then
    return nil, err
  end

  return Plugins.super.update(self, t)
end

return Plugins
