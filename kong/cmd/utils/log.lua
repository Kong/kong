local _LEVELS = {
  debug = 1,
  verbose = 2,
  info = 3,
  warn = 4
}

local r_levels = {}
for k, v in pairs(_LEVELS) do
  r_levels[v] = k
end

local log_lvl = _LEVELS.info

local _M = {
  levels = _LEVELS
}

function _M.set_lvl(lvl)
  if r_levels[lvl] then
    log_lvl = lvl
  end
end

local function log(lvl, ...)
  local format
  local args = {...}
  if lvl >= log_lvl then
    format = table.remove(args, 1)
    if type(format) ~= "string" then
      error("expected argument #1 or #2 to be a string", 3)
    end

    local msg = string.format(format, unpack(args))
    if lvl ~= _LEVELS.info then
      msg = string.format("%s [%s] %s", os.date("%H:%M:%S"), r_levels[lvl], msg)
    end

    print(msg)
  end
end

return setmetatable(_M, {
  __call = function(_, ...)
    return log(_LEVELS.info, ...)
  end,
  __index = function(t, key)
    if _LEVELS[key] then
      return function(...)
        log(_LEVELS[key], ...)
      end
    end
    return rawget(t, key)
  end
})
