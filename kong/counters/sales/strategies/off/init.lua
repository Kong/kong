-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}
local mt = { __index = _M }


function _M:new()
  local self = {}
  return setmetatable(self, mt)
end

function _M:init()
  return true
end

function _M:flush_data()
end

function _M:pull_data()
end


return _M
