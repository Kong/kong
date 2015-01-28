local BaseDao = require "apenode.dao.cassandra.base_dao"
local PluginModel = require "apenode.models.plugin"

local SCHEMA = {
  { _ = "id", type = "id" },
  { _ = "api_id", type = "id", exists = true },
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
      INSERT INTO plugins(id, api_id, application_id, name, value, created_at)
        VALUES(?, ?, ?, ?, ?, ?);
    ]]
  }

  Plugins.super.new(self, database)
end

return Plugins
