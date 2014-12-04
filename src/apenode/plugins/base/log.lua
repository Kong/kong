-- Copyright (C) Mashape, Inc.

local cjson = require "cjson"
local utils = require "apenode.core.utils"

local _M = {}

function _M.execute()
  utils.create_timer(_M.log, ngx.ctx.log_message)
end

function _M.log(premature, message)
  -- TODO: Log the information
  ngx.log(ngx.DEBUG, cjson.encode(message))
end

return _M
