local setmetatable = setmetatable
local log          = ngx.log


local DEBUG        = ngx.DEBUG
local NOTICE       = ngx.NOTICE
local WARN         = ngx.WARN
local ERR          = ngx.ERR


local function write_log(level, ...)
  return log(level, "[openid-connect] ", ...)
end


local logging = {
  debug = function(...)
    return write_log(DEBUG, ...)
  end,
  notice = function(...)
    return write_log(NOTICE, ...)
  end,
  warn = function(...)
    return write_log(WARN, ...)
  end,
  err = function(...)
    return write_log(ERR, ...)
  end,
}


return setmetatable(logging, {
  __call = function(_, ...)
    return logging.debug(...)
  end
})
