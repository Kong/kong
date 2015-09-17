local BaseDao = require "kong.dao.cassandra.base_dao"
local consumers_schema = require "kong.dao.schemas.consumers"

local Consumers = BaseDao:extend()

function Consumers:new(properties)
  self._table = "consumers"
  self._schema = consumers_schema

  Consumers.super.new(self, properties)
end

return {consumers = Consumers}
