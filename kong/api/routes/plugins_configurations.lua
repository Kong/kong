-- Copyright (C) Mashape, Inc.

local BaseController = require "kong.api.routes.base_controller"

local PluginsConfigurations = BaseController:extend()

function PluginsConfigurations:new()
  PluginsConfigurations.super.new(self, dao.plugins_configurations, "plugins_configurations")
end

return PluginsConfigurations
