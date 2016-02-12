local runscope_serializer = require "kong.plugins.log-serializers.runscope"
local BasePlugin = require "kong.plugins.base_plugin"
local log = require "kong.plugins.runscope.log"

local ngx_log = ngx.log
local ngx_log_ERR = ngx.ERR
local string_find = string.find
local req_read_body = ngx.req.read_body
local req_get_headers = ngx.req.get_headers
local req_get_body_data = ngx.req.get_body_data
local req_get_post_args = ngx.req.get_post_args
local pcall = pcall

local RunscopeLogHandler = BasePlugin:extend()

function RunscopeLogHandler:new()
  RunscopeLogHandler.super.new(self, "runscope")
end

function RunscopeLogHandler:access(conf)
  RunscopeLogHandler.super.access(self)

  local req_body, res_body = "", ""
  local req_post_args = {}

  if conf.log_body then
    req_read_body()
    req_body = req_get_body_data()

    local headers = req_get_headers()
    local content_type = headers["content-type"]
    if content_type and string_find(content_type:lower(), "application/x-www-form-urlencoded", nil, true) then
      local status, res = pcall(req_get_post_args)
      if not status then
        if res == "requesty body in temp file not supported" then
          ngx_log(ngx_log_ERR, "[runscope] cannot read request body from temporary file. Try increasing the client_body_buffer_size directive.")
        else
          ngx_log(ngx_log_ERR, res)
        end
      else
        req_post_args = res
      end
    end
  end

  -- keep in memory the bodies for this request
  ngx.ctx.runscope = {
    req_body = req_body,
    res_body = res_body,
    req_post_args = req_post_args
  }
end

function RunscopeLogHandler:body_filter(conf)
 RunscopeLogHandler.super.body_filter(self)

  if conf.log_body then
    local chunk = ngx.arg[1]
    local runscope_data = ngx.ctx.runscope or {res_body = ""} -- minimize the number of calls to ngx.ctx while fallbacking on default value
    runscope_data.res_body = runscope_data.res_body..chunk
    ngx.ctx.runscope = runscope_data
  end
end

function RunscopeLogHandler:log(conf)
  RunscopeLogHandler.super.log(self)

  local message = runscope_serializer.serialize(ngx)
  log.execute(conf, message)
end

RunscopeLogHandler.PRIORITY = 1

return RunscopeLogHandler
