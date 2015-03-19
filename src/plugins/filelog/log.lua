-- Copyright (C) Mashape, Inc.

local cjson = require "cjson"

local _M = {}

local function log(premature, message)
  ngx.log(ngx.INFO, cjson.encode(message))
end

function _M.execute()
  local ok, err = ngx.timer.at(0, log, ngx.ctx.log_message)
  if not ok then
    ngx.log(ngx.ERR, "failed to create timer: ", err)
  end
end

return _M
