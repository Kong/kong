-- Copyright (C) Mashape, Inc.

local ApplicationModel = require "apenode.models.application"
local BaseController = require "apenode.web.routes.base_controller"

local Applications = BaseController:extend()

function Applications:new()
  Applications.super:new(ApplicationModel) -- call the base class constructor
end

return Applications