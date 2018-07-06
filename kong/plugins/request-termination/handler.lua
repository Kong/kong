local BasePlugin = require "kong.plugins.base_plugin"
local singletons = require "kong.singletons"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local meta = require "kong.meta"


local ngx = ngx


local server_header = meta._SERVER_TOKENS


local RequestTerminationHandler = BasePlugin:extend()


RequestTerminationHandler.PRIORITY = 2
RequestTerminationHandler.VERSION = "0.1.1"


local function flush(ctx)
  ctx = ctx or ngx.ctx

  local response = ctx.delayed_response

  local status       = response.status_code
  local content      = response.content
  local content_type = response.content_type
  if not content_type then
    content_type = "application/json; charset=utf-8";
  end

  ngx.status = status

  if singletons.configuration.enabled_headers[constants.HEADERS.SERVER] then
    ngx.header[constants.HEADERS.SERVER] = server_header

  else
    ngx.header[constants.HEADERS.SERVER] = nil
  end

  ngx.header["Content-Type"]   = content_type
  ngx.header["Content-Length"] = #content
  ngx.print(content)

  return ngx.exit(status)
end


function RequestTerminationHandler:new()
  RequestTerminationHandler.super.new(self, "request-termination")
end


function RequestTerminationHandler:access(conf)
  RequestTerminationHandler.super.access(self)

  local status  = conf.status_code
  local content = conf.body

  if content then
    local ctx = ngx.ctx
    if ctx.delay_response and not ctx.delayed_response then
      ctx.delayed_response = {
        status_code  = status,
        content      = content,
        content_type = conf.content_type,
      }

      ctx.delayed_response_callback = flush

      return
    end
  end

  return responses.send(status, conf.message)
end


return RequestTerminationHandler
