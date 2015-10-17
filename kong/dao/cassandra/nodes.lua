local BaseDao = require "kong.dao.cassandra.base_dao"
local nodes_schema = require "kong.dao.schemas.nodes"
local query_builder = require "kong.dao.cassandra.query_builder"

local ipairs = ipairs
local table_insert = table.insert

local Nodes = BaseDao:extend()

function Nodes:new(properties, events_handler)
  self._table = "nodes"
  self._schema = nodes_schema
  Nodes.super.new(self, properties, events_handler)
end

function Nodes:find_all()
  local nodes = {}
  local select_q = query_builder.select(self._table)

  for rows, err in self:execute(select_q, nil, {auto_paging = true}) do
    if err then
      return nil, err
    elseif rows ~= nil then
      for _, row in ipairs(rows) do
        table_insert(nodes, row)
      end
    end
  end

  return nodes
end

return {nodes = Nodes}