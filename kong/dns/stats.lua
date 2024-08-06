-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local tb_new = require("table.new")
local tb_nkeys = require("table.nkeys")


local pairs = pairs
local setmetatable = setmetatable


local _M = {}
local _MT = { __index = _M, }


function _M.new()
  local self = {
    -- pre-allocate 4 slots
    stats = tb_new(0, 4),
  }

  return setmetatable(self, _MT)
end


function _M:_get_stats(name)
  local stats = self.stats

  if not stats[name] then
    -- keys will be: query/query_last_time/query_fail_nameserver
    --               query_succ/query_fail/stale/runs/...
    -- 6 slots may be a approprate number
    stats[name] = tb_new(0, 6)
  end

  return stats[name]
end


function _M:incr(name, key)
  local stats = self:_get_stats(name)

  stats[key] = (stats[key] or 0) + 1
end


function _M:set(name, key, value)
  local stats = self:_get_stats(name)

  stats[key] = value
end


function _M:emit(fmt)
  local stats = self.stats
  local output = tb_new(0, tb_nkeys(stats))

  for k, v in pairs(stats) do
    output[fmt(k)] = v
  end

  return output
end


return _M
