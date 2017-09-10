local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local meta = require "kong.meta"

local server_header = meta._NAME .. "/" .. meta._VERSION

local RequestTerminationHandler = BasePlugin:extend()

RequestTerminationHandler.PRIORITY = 7

function RequestTerminationHandler:new()
  RequestTerminationHandler.super.new(self, "request-termination")
end

function RequestTerminationHandler:access(conf)
  RequestTerminationHandler.super.access(self)

  local status_code = conf.status_code
  local content_type = conf.content_type
  local body = conf.body
  local message = conf.message
  if body then
    ngx.status = status_code

    if not content_type then
      content_type = "application/json; charset=utf-8";
    end
    ngx.header["Content-Type"] = content_type
    ngx.header["Server"] = server_header

    ngx.say(body)

    return ngx.exit(status_code)
   else
    return responses.send(status_code, message)
  end
end

return RequestTerminationHandler
