-- Copyright (C) Mashape, Inc.


local cjson = require "cjson"


local _M = { _VERSION = '0.1' }


function _M.show_error(status, message)
	ngx.ctx.error = true
	ngx.status = status
	ngx.print(cjson.encode({status = status, message = message}))
	ngx.exit(status)
end


return _M