-- Copyright (C) Mashape, Inc.


-- Define the plugins to load here, in the appropriate order
local plugins = {
	base = require "resty.apenode.base.handler", -- The base handler must be the first one
	transformations = require "resty.apenode.transformations.handler"
}


local _M = { _VERSION = '0.1' }


function _M.init()
	for k, v in pairs(plugins) do -- Iterate over all the plugins
		v.init()
	end
end


function _M.access()
	ngx.ctx.start = ngx.now() -- Setting a property that will be available for every plugin
	for k, v in pairs(plugins) do -- Iterate over all the plugins
		v.access()
	end
	ngx.ctx.proxy_start = ngx.now() -- Setting a property that will be available for every plugin
end


function _M.content()
	for k, v in pairs(plugins) do -- Iterate over all the plugins
		v.content()
	end
end


function _M.rewrite()
	for k, v in pairs(plugins) do -- Iterate over all the plugins
		v.rewrite()
	end
end


function _M.header_filter()
	ngx.ctx.proxy_end = ngx.now() -- Setting a property that will be available for every plugin
	if not ngx.ctx.error then
		for k, v in pairs(plugins) do -- Iterate over all the plugins
			v.header_filter()
		end
	end
end


function _M.body_filter()
	for k, v in pairs(plugins) do -- Iterate over all the plugins
		v.body_filter()
	end
end


function _M.log()
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

	ngx.ctx.log_message = message

	for k, v in pairs(plugins) do -- Iterate over all the plugins
		v.log()
	end
end


return _M
