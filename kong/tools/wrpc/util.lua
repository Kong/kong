local semaphore = require "ngx.semaphore"

local table_insert = table.insert     -- luacheck: ignore
local table_remove = table.remove     -- luacheck: ignore
local table_unpack = table.unpack     -- luacheck: ignore
local select = select

local _M = {}

function _M.endswith(s, e) -- luacheck: ignore
  return s and e and e ~= "" and s:sub(#s - #e + 1, #s) == e
end

--- return same args in the same order, removing any nil args.
--- required for functions (like ngx.thread.wait) that complain
--- about nil args at the end.
function _M.safe_args(...)
  local out = {}
  for i = 1, select('#', ...) do
    out[#out + 1] = select(i, ...)
  end
  return table_unpack(out)
end

--- little helper to ease grabbing an unspecified number
--- of values after an `ok` flag
function _M.ok_wrapper(ok, ...)
  return ok, {n = select('#', ...), ...}
end

local queue = {}
queue.__index = queue

function queue.new()
  return setmetatable({
    smph = semaphore.new(),
  }, queue)
end

function queue:push(itm)
  table_insert(self, itm)
  return self.smph:post()
end

function queue:pop(timeout)
  local ok, err = self.smph:wait(timeout or 1)
  if not ok then
    return nil, err
  end

  return table_remove(self, 1)
end

_M.queue = queue

return _M