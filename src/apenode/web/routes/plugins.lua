-- Copyright (C) Mashape, Inc.

local PluginModel = require "apenode.models.plugin"
local BaseController = require "apenode.web.routes.base_controller"

local Plugins = BaseController:extend()

function Plugins:new()
  Plugins.super:new(PluginModel) -- call the base class constructor
end

return Plugins