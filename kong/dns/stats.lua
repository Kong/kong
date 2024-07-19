local setmetatable = setmetatable


local _M = {}
local _MT = { __index = _M, }


function _M.new()
  local self = {
    stats = {},
  }

  return setmetatable(self, _MT)
end


function _M:incr(name, key)
  local stats = self.stats

  if not stats[name] then
    stats[name] = {}
  end

  stats[name][key] = (stats[name][key] or 0) + 1
end


function _M:set(name, key, value)
  local stats = self.stats

  if not stats[name] then
    stats[name] = {}
  end

  stats[name][key] = value
end


return _M
