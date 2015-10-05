local BaseDao = require "kong.dao.cassandra.base_dao"
local apis_schema = require "kong.dao.schemas.apis"
local query_builder = require "kong.dao.cassandra.query_builder"

local Apis = BaseDao:extend()

function Apis:new(properties)
  self._table = "apis"
  self._schema = apis_schema
  Apis.super.new(self, properties)
end

function Apis:find_all()
  local apis = {}
  local select_q = query_builder.select(self._table)
  for rows, err in Apis.super.execute(self, select_q, nil, nil, {auto_paging=true}) do
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      table.insert(apis, row)
    end
  end

  return apis
end

return {apis = Apis}
