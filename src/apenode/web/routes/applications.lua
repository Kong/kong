-- Copyright (C) Mashape, Inc.

local BaseController = require "apenode.web.routes.base_controller"

local Applications = BaseController:extend()

function Applications:new()
  Applications.super.new(self, dao.applications, "applications") -- call the base class constructor
end

return Applications