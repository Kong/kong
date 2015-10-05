local BaseDao = require "kong.dao.cassandra.base_dao"

local SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    consumer_id = { type = "id", required = true, foreign = "consumers:id", queryable = true },
    group = { type = "string", required = true }
  }
}

local ACLs = BaseDao:extend()

function ACLs:new(properties)
  self._table = "acls"
  self._schema = SCHEMA

  ACLs.super.new(self, properties)
end

return { acls = ACLs }
