local setmetatable = setmetatable
local log          = ngx.log


local DEBUG        = ngx.DEBUG
local NOTICE       = ngx.NOTICE
local ERR          = ngx.ERR
local CRIT         = ngx.CRIT


local function write_log(level, ...)
  return log(level, "[jwt-signer] ", ...)
end


local logging = {
  debug = function(...)
    return write_log(DEBUG, ...)
  end,
  notice = function(...)
    return write_log(NOTICE, ...)
  end,
  err = function(...)
    return write_log(ERR, ...)
  end,
  crit = function(...)
    return write_log(CRIT, ...)
  end,
}


return setmetatable(logging, {
  __call = function(_, ...)
    return logging.debug(...)
  end
})
