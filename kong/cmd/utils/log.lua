local _LEVELS = {
  debug = 1,
  verbose = 2,
  info = 3,
  warn = 4,
  error = 5,
  quiet = 6
}

local _NGX_LEVELS = {
  [1] = ngx.DEBUG,
  -- verbose
  [3] = ngx.INFO,
  [4] = ngx.WARN,
  [5] = ngx.ERR,
  -- quiet
}

local r_levels = {}
for k, v in pairs(_LEVELS) do
  r_levels[v] = k
end

local log_lvl = _LEVELS.info
local old_lvl

local _M = {
  levels = _LEVELS
}

function _M.set_lvl(lvl)
  if r_levels[lvl] then
    log_lvl = lvl
  end
end

function _M.disable()
  if not old_lvl then
    old_lvl = log_lvl
    log_lvl = _LEVELS.quiet
  end
end

function _M.enable()
  log_lvl = old_lvl or log_lvl
  old_lvl = nil
end

function _M.log(lvl, ...)
  local format
  local args = {...}

  for i = 1, #args do
    args[i] = tostring(args[i])
  end

  if lvl >= log_lvl then
    format = table.remove(args, 1)
    if type(format) ~= "string" then
      error("expected argument #1 or #2 to be a string", 3)
    end

    local msg = string.format(format, unpack(args))

    if not ngx.IS_CLI then
      local ngx_lvl = _NGX_LEVELS[lvl]
      if ngx_lvl then
        ngx.log(ngx_lvl, msg)
      end

      return
    end

    if log_lvl < _LEVELS.info or lvl >= _LEVELS.warn then
      msg = string.format("%s [%s] %s", os.date("%Y/%m/%d %H:%M:%S"), r_levels[lvl], msg)
    end

    if lvl < _LEVELS.warn then
      print(msg)
    else
      io.stderr:write(msg .. "\n")
    end
  end
end

return setmetatable(_M, {
  __call = function(_, ...)
    return _M.log(_LEVELS.info, ...)
  end,
  __index = function(t, key)
    if _LEVELS[key] then
      return function(...)
        _M.log(_LEVELS[key], ...)
      end
    end
    return rawget(t, key)
  end
})
