-- a plugin fixture to test post-processing on the admin api
local BasePlugin = require "kong.plugins.base_plugin"


local AdminApiPostProcess = BasePlugin:extend()


AdminApiPostProcess.PRIORITY = 1000


function AdminApiPostProcess:new()
  AdminApiPostProcess.super.new(self, "admin-api-post-process")
end


return AdminApiPostProcess
