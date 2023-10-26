local semaphore = require("ngx.semaphore")


local assert = assert
local setmetatable = setmetatable
local table_insert = table.insert
local table_remove = table.remove


local _M = {}
local _MT = { __index = _M, }


function _M.new()
  local self = {
    sema = assert(semaphore.new()),
  }

  return setmetatable(self, _MT)
end


function _M:push(item)
  table_insert(self, item)
  self.sema:post()

  return true
end


function _M:pop(timeout)
  local ok, err = self.sema:wait(timeout or 1)
  if not ok then
    return nil, err
  end

  return table_remove(self, 1)
end


return _M
