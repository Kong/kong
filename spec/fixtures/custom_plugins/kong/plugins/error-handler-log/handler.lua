local BasePlugin = require "kong.plugins.base_plugin"


local ErrHandlerLog = BasePlugin:extend()


ErrHandlerLog.PRIORITY = 1000


function ErrHandlerLog:new()
  ErrHandlerLog.super.new(self, "error-handler-log")
end


function ErrHandlerLog:rewrite(conf)
  ErrHandlerLog.super.rewrite(self)

  local phases = ngx.ctx.err_handler_log_phases or {}
  table.insert(phases, "rewrite")
  ngx.ctx.err_handler_log_phases = phases
end


function ErrHandlerLog:access(conf)
  ErrHandlerLog.super.access(self)

  local phases = ngx.ctx.err_handler_log_phases or {}
  table.insert(phases, "access")
  ngx.ctx.err_handler_log_phases = phases
end


function ErrHandlerLog:header_filter(conf)
  ErrHandlerLog.super.header_filter(self)

  local phases = ngx.ctx.err_handler_log_phases or {}
  table.insert(phases, "header_filter")

  ngx.header["Content-Length"] = nil
  ngx.header["Log-Plugin-Phases"] = table.concat(phases, ",")

  local service = ((ngx.ctx.proxy_request_state or {}).routing or {}).service
  ngx.header["Log-Plugin-Service-Matched"] = service and service.name
end


function ErrHandlerLog:body_filter(conf)
  ErrHandlerLog.super.body_filter(self)

  if not ngx.arg[2] then
    ngx.arg[1] = "body_filter"
  end
end


return ErrHandlerLog
