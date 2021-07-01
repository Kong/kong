-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}


local semaphore = require("ngx.semaphore")


local table_insert = table.insert
local table_remove = table.remove
local setmetatable = setmetatable
local assert = assert


local _MT = { __index = _M, }


function _M.new()
  local self = {
    semaphore = assert(semaphore.new()),
  }

  return setmetatable(self, _MT)
end


function _M:enqueue(item)
  table_insert(self, item)
  self.semaphore:post()
end


function _M:dequeue(item)
  local res, err = self.semaphore:wait(5)
  if not res then
    return nil, err
  end

  return assert(table_remove(self, 1))
end


return _M
