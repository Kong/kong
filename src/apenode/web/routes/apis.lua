-- Copyright (C) Mashape, Inc.

local ApiModel = require "apenode.models.api"
local BaseController = require "apenode.web.routes.base_controller"

local Apis = BaseController:extend()

function Apis:new()
  Apis.super.new(self, ApiModel)
end

return Apis
