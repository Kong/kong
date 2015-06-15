local BaseDao = require "kong.dao.cassandra.base_dao"
local query_builder = require "kong.dao.cassandra.query_builder"
local consumers_schema = require "kong.dao.schemas.consumers"

local Consumers = BaseDao:extend()

function Consumers:new(properties)
  self._entity = "Consumer"
  self._table = "consumers"
  self._schema = consumers_schema
  self._primary_key = {"id"}

  Consumers.super.new(self, properties)
end

-- @override
function Consumers:delete(where_t)
  local ok, err = Consumers.super.delete(self, where_t)
  if not ok then
    return false, err
  end

  local plugins_dao = self._factory.plugins_configurations
  local select_q, columns = query_builder.select(plugins_dao._table, {consumer_id = where_t.id}, self._primary_key)

  -- delete all related plugins configurations
  for _, rows, page, err in plugins_dao:_execute_kong_query({query = select_q, args_keys = columns}, {consumer_id=where_t.id}, {auto_paging=true}) do
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      local ok_del_plugin, err = plugins_dao:delete({id = row.id})
      if not ok_del_plugin then
        return nil, err
      end
    end
  end

  return ok
end

return { consumers = Consumers }
