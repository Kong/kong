-- Copyright (C) Mashape, Inc.

local BaseController = require "kong.web.routes.base_controller"

local Applications = BaseController:extend()

function Applications:new()
  Applications.super.new(self, dao.applications, "applications")
end

return Applications
