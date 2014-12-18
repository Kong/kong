-- Copyright (C) Mashape, Inc.

local PluginModel = require "apenode.models.plugin"
local BaseController = require "apenode.web.routes.base_controller"

local Plugins = {}
Plugins.__index = Plugins

setmetatable(Plugins, {
  __index = BaseController, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function Plugins:_init()
  BaseController:_init(PluginModel) -- call the base class constructor
end

return Plugins