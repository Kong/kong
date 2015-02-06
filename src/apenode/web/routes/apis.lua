-- Copyright (C) Mashape, Inc.

local BaseController = require "apenode.web.routes.base_controller"

local Apis = BaseController:extend()

function Apis:new()
  Apis.super.new(self, dao.apis, "apis")
end

return Apis
