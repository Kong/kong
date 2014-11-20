-- Copyright (C) Mashape, Inc.


local _M = { _VERSION = '0.1' }


function _M.execute()
	ngx.log(ngx.DEBUG, "Header Filter")

	local api = ngx.ctx.api
	if api then
		if api.transformations.xml_to_json and ngx.header["content-type"] == "application/xml" then
			ngx.header.content_length = nil
			ngx.header.content_type = "application/json"
			ngx.ctx.xml_to_json = true
		end
	end
end


return _M
