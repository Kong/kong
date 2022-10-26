local semaphore = require "ngx.semaphore"

local table_insert = table.insert     -- luacheck: ignore
local table_remove = table.remove     -- luacheck: ignore

local _M = {}
local _MT = { __index = _M, }

function _M.new()
  return setmetatable({
    smph = semaphore.new(),
  }, _MT)
end

function _M:push(itm)
  table_insert(self, itm)
  return self.smph:post()
end

function _M:pop(timeout)
  local ok, err = self.smph:wait(timeout or 1)
  if not ok then
    return nil, err
  end

  return table_remove(self, 1)
end

return _M