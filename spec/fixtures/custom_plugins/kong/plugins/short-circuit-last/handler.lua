local BasePlugin = require "kong.plugins.base_plugin"
local cjson = require "cjson"


local kong = kong
local req = ngx.req
local exit = ngx.exit
local error = error


local ShortCircuitLastHandler = BasePlugin:extend()


ShortCircuitLastHandler.PRIORITY = -math.huge


function ShortCircuitLastHandler:new()
  ShortCircuitLastHandler.super.new(self, "short-circuit-last")
end


function ShortCircuitLastHandler:access(conf)
  ShortCircuitLastHandler.super.access(self)
  return kong.response.exit(conf.status, {
    status  = conf.status,
    message = conf.message
  })
end


function ShortCircuitLastHandler:preread(conf)
  ShortCircuitLastHandler.super.preread(self)

  local tcpsock, err = req.socket()
  if err then
    error(err)
  end

  tcpsock:send(cjson.encode({
    status  = conf.status,
    message = conf.message
  }))

  -- TODO: this should really support delayed short-circuiting!
  return exit(conf.status)
end


return ShortCircuitLastHandler
