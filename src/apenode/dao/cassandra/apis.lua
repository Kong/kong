local BaseDao = require "apenode.dao.cassandra.base_dao"
local ApiModel = require "apenode.models.api"

local SCHEMA = {
  { _ = "id", type = "id" },
  { _ = "name", required = true, unique = true },
  { _ = "public_dns", required = true, unique = true,
    regex = "(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])" },
  { _ = "target_url", required = true },
  { _ = "created_at", type = "timestamp" }
}

local Apis = BaseDao:extend()

function Apis:new(database)
  self._schema = SCHEMA
  self._queries = {
    insert = [[
      INSERT INTO apis(id, name, public_dns, target_url, created_at) VALUES(?, ?, ?, ?, ?);
    ]],
    unique = {
      name = [[ SELECT id FROM apis WHERE name = ?; ]],
      public_dns = [[ SELECT id FROM apis WHERE public_dns = ?; ]]
    }
  }

  Apis.super.new(self, database)
end

return Apis
