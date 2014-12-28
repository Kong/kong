local BaseDao = require "apenode.dao.sqlite.base_dao"
local ApplicationsModel = require "apenode.models.application"

local Applications = BaseDao:extend()

function Applications:new(configuration)
  Applications.super.new(self, configuration, ApplicationsModel._COLLECTION, ApplicationsModel._SCHEMA)
end

return Applications
