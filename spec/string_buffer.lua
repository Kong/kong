-- this is a backport of `string.buffer` module of LuaJIT
-- for older version of Kong code to run tests with new helper functions
-- this implementation only promise the same behavior as the original but not the same performance
-- and the methods decode()/encode() are not implemented

local ffi = require "ffi"
local tbl_new = require "table.new"
local tbl_clr = require "table.clear"

local _M = {}
_M.__index = _M

function _M.new(size)
  local buf = tbl_new(size or 0, 0)
  buf.n = 0
  return setmetatable(buf, _M)
end

function _M:put(...)
  local n = select("#", ...)
  if n == 0 then
    return
  end

  local buf = self
  local offset = self.n
  self.n = offset + n

  for i = 1, n do
    local item = select(i, ...)
    buf[offset + i] = tostring(item)
  end

  return buf
end

function _M:putf(fmt, ...)
  return self:put(string.format(fmt, ...))
end

function _M:putcdata(cdata, len)
  return self:put(ffi.string(cdata, len))
end

function _M:set(str, len)
  self:reset()
  if len then
    return self:putcdata(str, len)
  else
    return self:put(str)
  end
end

function _M:reserve()
end

function _M:commit()
end

function _M:reset()
  tbl_clr(self)
  self.n = 0
  return self
end

function _M:tostring()
  local result = table.concat(self)
  self:reset()
  self[1] = result
  self.n = 1
  return result
end

_M.__tostring = _M.tostring

function _M:ref()
  return ffi.cast("const char *", self:tostring())
end

function _M:__len()
  return #self:tostring()
end

function _M:skip(len)
  self[1] = self:tostring():sub(len + 1)
end

function _M:get(...)
  local str = self:tostring()
  local n = select("#", ...)

  local offset = 0
  local results = {}
  for i = 1, n do
    local len = select(i, ...)
    local result = str:sub(offset + 1, offset + len)
    offset = offset + len
    results[i] = result
  end

  self[1] = str:sub(offset + 1)

  return unpack(results)
end

_M.free = _M.reset

return _M
