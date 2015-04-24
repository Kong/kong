local BaseController = require "kong.api.routes.base_controller"

local Apis = BaseController:extend()

function Apis:new()
  Apis.super.new(self, dao.apis, "apis")
end

return Apis
