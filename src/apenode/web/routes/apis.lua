-- Copyright (C) Mashape, Inc.

local ApiModel = require "apenode.models.api"
local BaseController = require "apenode.web.routes.base_controller"

local Apis = {}
Apis.__index = Apis

setmetatable(Apis, {
  __index = BaseController, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function Apis:_init()
  BaseController:_init(ApiModel) -- call the base class constructor
end

return Apis