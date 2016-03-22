-- ©2016 API Fortress Inc.
-- The plugin handler

local capturer = require "kong.plugins.apifortress.capturer"
local forward = require "kong.plugins.apifortress.forward"
local BasePlugin = require "kong.plugins.base_plugin"

local ApiFortressHandler = BasePlugin:extend()

function ApiFortressHandler:new()
  ApiFortressHandler.super.new(self, "apifortress-filter")
end
function ApiFortressHandler:access(conf)
	ngx.req.read_body()
end

function ApiFortressHandler:log(conf)
	ApiFortressHandler.super.log(self)
	forward.execute(conf)
end

function ApiFortressHandler:body_filter(config)
	ApiFortressHandler.super.body_filter(self)
	capturer.execute(config)
end
ApiFortressHandler.PRIORITY = 800

return ApiFortressHandler
