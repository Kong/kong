-- a plugin fixture to force one authentication failure

local BasePlugin = require "kong.plugins.base_plugin"

local FailOnceAuth = BasePlugin:extend()

FailOnceAuth.PRIORITY = 1000

function FailOnceAuth:new()
  FailOnceAuth.super.new(self, "fail-once-auth")
end

local failed = {}

function FailOnceAuth:access(conf)
  FailOnceAuth.super.access(self)

  if not failed[conf.service_id] then
    failed[conf.service_id] = true
    return kong.response.exit(401, { message = conf.message })
  end
end

return FailOnceAuth
