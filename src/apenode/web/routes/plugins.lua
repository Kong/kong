-- Copyright (C) Mashape, Inc.

local BaseController = require "apenode.web.routes.base_controller"

local Plugins = BaseController:extend()

function Plugins:new()
  Plugins.super.new(self, dao.plugins, "plugins") -- call the base class constructor
end

return Plugins