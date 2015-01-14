local BaseDao = require "apenode.dao.cassandra.base_dao"
local ApplicationsModel = require "apenode.models.application"

local Applications = BaseDao:extend()

function Applications:new(client)
  Applications.super.new(self, client, ApplicationsModel._COLLECTION, ApplicationsModel._SCHEMA)
end

return Applications
