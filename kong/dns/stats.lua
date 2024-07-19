local tb_new = require(table.new)


local pairs = pairs
local setmetatable = setmetatable


local _M = {}
local _MT = { __index = _M, }


function _M.new()
  local self = {
    stats = {},
  }

  return setmetatable(self, _MT)
end


function _M:_get_stats(name)
  local stats = self.stats

  if not stats[name] then
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
  local output = {}

  for k, v in pairs(self.stats) do
    output[fmt(k)] = v
  end

  return output
end


return _M
