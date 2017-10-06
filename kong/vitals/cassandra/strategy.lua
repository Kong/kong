
--[[
-- This is a strategy stub, in place until we implement vitals for Cassandra
-- ]]
local _M = {}
local mt = { __index = _M }

function _M.new(dao_factory)
  local self = {
    db = dao_factory.db,
  }

  return setmetatable(self, mt)
end


function _M:init()
  return true
end


function _M:select_stats(query_type)
  return {}
end


function _M:insert_stats(data)
  return true
end


function _M:current_table_name()
  return nil
end


return _M
