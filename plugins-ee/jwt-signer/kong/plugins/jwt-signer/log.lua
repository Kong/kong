-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local setmetatable = setmetatable
local log          = ngx.log


local DEBUG        = ngx.DEBUG
local NOTICE       = ngx.NOTICE
local WARN         = ngx.WARN
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
  warn = function(...)
    return write_log(WARN, ...)
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
