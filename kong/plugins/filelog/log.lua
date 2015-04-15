-- Copyright (C) Mashape, Inc.

local cjson = require "cjson"

local _M = {}

function _M.execute()
  ngx.log(ngx.INFO, cjson.encode(ngx.ctx.log_message))
end

return _M
