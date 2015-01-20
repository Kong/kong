local BaseDao = require "apenode.dao.cassandra.base_dao"
local ApplicationsModel = require "apenode.models.application"

local Applications = BaseDao:extend()

function Applications:new(database, properties)
  Applications.super.new(self, database, ApplicationsModel._COLLECTION, ApplicationsModel._SCHEMA, properties)
end

return Applications
