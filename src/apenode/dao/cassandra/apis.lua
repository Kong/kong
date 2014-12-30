local BaseDao = require "apenode.dao.cassandra.base_dao"
local ApiModel = require "apenode.models.api"

local Apis = BaseDao:extend()

function Apis:new(configuration)
  Apis.super.new(self, configuration, ApiModel._COLLECTION, ApiModel._SCHEMA)
end

return Apis
