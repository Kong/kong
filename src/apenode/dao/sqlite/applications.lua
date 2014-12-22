local BaseDao = require "apenode.dao.sqlite.base_dao"
local ApplicationsModel = require "apenode.models.application"

local Applications = BaseDao:extend()

function Applications:new(database)
  Applications.super.new(self, database, ApplicationsModel._COLLECTION, ApplicationsModel._SCHEMA)
end

return Applications
