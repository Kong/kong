local BasePlugin = require "kong.plugins.base_plugin"

local UpstreamTimeout = BasePlugin:extend()


function UpstreamTimeout:access(conf)
	UpstreamTimeout.super.access(self)

	-- Needs option to revert to old timeout
	if conf.read_timeout then
		ngx.ctx.balancer_data.read_timeout = conf.read_timeout
	end
	if conf.send_timeout then
		ngx.ctx.balancer_data.send_timeout = conf.send_timeout
	end
	if conf.connect_timeout then
		ngx.ctx.balancer_data.connect_timeout = conf.connect_timeout
	end

end

UpstreamTimeout.PRIORITY = 400
UpstreamTimeout.VERSION = "1.0.0-0"

return UpstreamTimeout
