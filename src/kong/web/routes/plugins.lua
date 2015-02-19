-- Copyright (C) Mashape, Inc.

local BaseController = require "kong.web.routes.base_controller"

local Plugins = BaseController:extend()

function Plugins:new()
  Plugins.super.new(self, dao.plugins, "plugins")
end

return Plugins
