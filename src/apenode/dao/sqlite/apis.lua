local BaseDao = require "apenode.dao.sqlite.base_dao"
local ApiModel = require "apenode.models.api"

local Apis = BaseDao:extend()

function Apis:new(database)
  Apis.super:new(database, ApiModel._COLLECTION, ApiModel._SCHEMA)
end

return Apis
