-- Copyright (C) Mashape, Inc.

local cjson = require "cjson"

local _M = {}

function _M.show_error(status, message)
  ngx.ctx.error = true
  _M.show_response(status, message)
end

function _M.show_response(status, message)
  ngx.header["X-Apenode-Version"] = configuration.version
  ngx.status = status
  if (type(message) == "table") then
    ngx.print(cjson.encode(message))
  else
    ngx.print(cjson.encode({message = message}))
  end
  ngx.exit(status)
end

function _M.create_timer(func, data)
  local ok, err = ngx.timer.at(0, func, data)
  if not ok then
    ngx.log(ngx.ERR, "failed to create timer: ", err)
    return
  end
end

function _M.success(message)
	_M.show_response(200, message)
end

function _M.notFound(message)
	message = message or "Not found"
	_M.show_error(404, message)
end

return _M