local BasePlugin = require "kong.plugins.base_plugin"
local req_get_uri_args = ngx.req.get_uri_args
local req_read_body = ngx.req.read_body
local req_get_body_data = ngx.req.get_body_data
local ngx_decode_args = ngx.decode_args

local req_get_method = ngx.req.get_method

local function decode_args(body)
  if body then
    return ngx_decode_args(body)
  end
  return {}
end

local AuthHandler = BasePlugin:extend()

function AuthHandler:new()
  AuthHandler.super.new(self, "auth")
end

function AuthHandler:access(conf)
  AuthHandler.super.access(self)
  local parameters;
  local method = req_get_method();
  if method == 'GET' then parameters = req_get_uri_args() else req_read_body() parameters = decode_args(req_get_body_data()) end
  local app_key = parameters['appKey'] or parameters['customerNo']

  ngx.ctx.method = method
  ngx.ctx.app = app_key
  ngx.ctx.parameters = parameters
end

AuthHandler.PRIORITY = 999
return AuthHandler
