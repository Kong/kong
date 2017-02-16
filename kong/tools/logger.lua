-- This class provides a slightly simpler way to output logs.
-- We can use
--   logger.error("error message: xxx")
-- instead of
--   ngx.log(ngx.ERR, "error message: xxx")
-- And we can directly know how many log levels from this module.
-- And it can avoid confusing ngx.ERR and ngx.ERROR, or ngx.log.ERR

-- The log levels declaration corresponding to nginx,
-- for details of nginx logging, please refer to:
--   http://nginx.org/en/docs/dev/development_guide.html#logging
local _LEVELS = {
  debug = ngx.DEBUG,
  info = ngx.INFO,
  notice = ngx.NOTICE,
  warn = ngx.WARN,
  error = ngx.ERR,
  crit = ngx.CRIT,
  alert = ngx.ALERT,
  emerg = ngx.EMERG,
}

local _M = {
  levels = _LEVELS
}

local function log(level, ...)
  ngx.log(level, ...)
end

return setmetatable(_M, {
  __call = function(t, ...)
    return log(t.levels.info, ...)
  end,
  __index = function(t, key)
    if t.levels[key] then
      return function(...)
        log(t.levels[key], ...)
      end
    end
    return rawget(t, key)
  end
})
