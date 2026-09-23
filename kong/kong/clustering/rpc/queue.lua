local semaphore = require("ngx.semaphore")
local table_new = require("table.new")
local rpc_utils = require("kong.clustering.rpc.utils")


local assert = assert
local setmetatable = setmetatable
local math_min = math.min
local is_timeout = rpc_utils.is_timeout


local _M = {}
local _MT = { __index = _M, }


local DEFAULT_QUEUE_LEN = 128


function _M.new(max_len)
  local self = {
    semaphore = assert(semaphore.new()),
    max = max_len,

    elts = table_new(math_min(max_len, DEFAULT_QUEUE_LEN), 0),
    first = 0,
    last = -1,
  }

  return setmetatable(self, _MT)
end


function _M:push(item)
  local last = self.last

  if last - self.first + 1 >= self.max then
    return nil, "queue overflow"
  end

  last = last + 1
  self.last = last
  self.elts[last] = item

  self.semaphore:post()

  return true
end


function _M:pop(timeout)
  local ok, err = self.semaphore:wait(timeout)
  if not ok then
    if is_timeout(err) then
      return nil
    end

    return nil, err
  end

  local first = self.first

  -- queue can not be empty because semaphore succeed
  assert(first <= self.last)

  local item = self.elts[first]
  self.elts[first] = nil
  self.first = first + 1

  return item
end


return _M
