-- Copyright (C) Mashape, Inc.


local cjson = require "cjson"


local _M = { _VERSION = '0.1' }


function _M.execute()
	ngx.log(ngx.DEBUG, "Log")

	local now = ngx.now()

	-- Creating the log variable that will be serialized
	local message = {
		request = {
			headers = ngx.req.get_headers(),
			size = ngx.var.request_length
		},
		response = {
			headers = ngx.resp.get_headers(),
			size = ngx.var.body_bytes_sent
		},
		application = ngx.ctx.application,
		api = ngx.ctx.api,
		ip = ngx.var.remote_addr,
		status = ngx.status,
		url = ngx.var.uri,
		created_at = now
	}

	local ok, err = ngx.timer.at(0, _M.log, message)
	if not ok then
		ngx.log(ngx.ERR, "Failed to create timer: ", err)
		return
	end

end


function _M.log(premature, message)
	-- TODO: Log the information
	ngx.log(ngx.DEBUG, cjson.encode(message))
end


return _M
