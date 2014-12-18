-- Copyright (C) Mashape, Inc.

local ApplicationModel = require "apenode.models.application"
local BaseController = require "apenode.web.routes.base_controller"

local Applications = {}
Applications.__index = Applications

setmetatable(Applications, {
  __index = BaseController, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function Applications:_init()
  BaseController:_init(ApplicationModel) -- call the base class constructor
end

return Applications