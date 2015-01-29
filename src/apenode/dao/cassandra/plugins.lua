local BaseDao = require "apenode.dao.cassandra.base_dao"

local SCHEMA = {
  { _ = "api_id", type = "id", required = true, exists = true },
  { _ = "application_id", type = "id", exists = true },
  { _ = "name", required = true },
  { _ = "value", type = "table", required = true },
  { _ = "created_at", type = "timestamp" }
}

local Plugins = BaseDao:extend()

function Plugins:new(database, properties)
  self._schema = SCHEMA
  self._queries = {
    insert = [[
      INSERT INTO plugins(api_id, application_id, name, value, created_at)
        VALUES(?, ?, ?, ?, ?);
    ]],
    exists = {
      application_id = [[ SELECT id FROM applications WHERE id = ?; ]],
      api_id = [[ SELECT id FROM apis WHERE id = ?; ]]
    }
  }

  Plugins.super.new(self, database)
end

return Plugins
