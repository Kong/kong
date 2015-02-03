local BaseDao = require "apenode.dao.cassandra.base_dao"
local schemas = require "apenode.dao.schemas"

local SCHEMA = {
  id = { type = "id" },
  api_id = { type = "id", required = true, exists = true },
  application_id = { type = "id", exists = true },
  name = { required = true },
  value = { type = "table", required = true },
  created_at = { type = "timestamp" }
}

local Plugins = BaseDao:extend()

function Plugins:new(database, properties)
  self._schema = SCHEMA
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
    __exists = {
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

function Plugins:insert(t)
  local valid_schema, errors = schemas.validate(t, self._schema)
  if not valid_schema then
    return nil, errors
  end

  local unique_statement

  if not t.application_id then
    unique_statement = self._statements.__custom_checks.unique_no_application_id
  else
    unique_statement = self._statements.__custom_checks.unique_application_id
  end

  local unique, err = self:check_unique(t, unique_statement)
  if err then
    return nil, err
  elseif not unique then
    return nil, "Plugin already exists"
  end

  return Plugins.super.insert(self, t)
end

return Plugins
