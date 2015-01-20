local BaseDao = require "apenode.dao.cassandra.base_dao"
local ApiModel = require "apenode.models.api"

local Apis = BaseDao:extend()

function Apis:new(database, properties)
  Apis.super.new(self, database, ApiModel._COLLECTION, ApiModel._SCHEMA, properties)
end

return Apis
