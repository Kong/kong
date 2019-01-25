-- a plugin fixture to test a method on the admin api
local BasePlugin = require "kong.plugins.base_plugin"


local AdminApiMethod = BasePlugin:extend()


AdminApiMethod.PRIORITY = 1000


function AdminApiMethod:new()
  AdminApiMethod.super.new(self, "admin-api-method")
end


return AdminApiMethod
