local CassandraDAO = require "kong.dao.cassandra.dao"
local nodes_schema = require "kong.dao.schemas.nodes"
local query_builder = require "kong.dao.cassandra.query_builder"

local ipairs = ipairs
local table_insert = table.insert

local NodesDAO = CassandraDAO:extend()

function NodesDAO:new(...)
  NodesDAO.super.new(self, nodes_schema, ...)
end

function NodesDAO:find_all()
  local nodes = {}
  local select_q = query_builder.select(self.table)

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

return {nodes = NodesDAO}
