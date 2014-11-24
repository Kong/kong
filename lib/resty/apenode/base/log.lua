-- Copyright (C) Mashape, Inc.


local cjson = require "cjson"


local _M = { _VERSION = '0.1' }


function _M.execute(premature, message)
	-- TODO: Log the information
	ngx.log(ngx.DEBUG, cjson.encode(message))
end


return _M
