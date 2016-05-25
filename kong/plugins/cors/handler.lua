local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"

local CorsHandler = BasePlugin:extend()

CorsHandler.PRIORITY = 2000

local OPTIONS = "OPTIONS"

local function configure_origin(ngx, conf)
  if conf.origin == nil then
    ngx.header["Access-Control-Allow-Origin"] = "*"
  else
    ngx.header["Access-Control-Allow-Origin"] = conf.origin
    ngx.header["Vary"] = "Origin"
  end
end

local function configure_credentials(ngx, conf)
  if (conf.credentials) then
    ngx.header["Access-Control-Allow-Credentials"] = "true"
  end
end

local function configure_headers(ngx, conf, headers)
  if conf.headers == nil then
    ngx.header["Access-Control-Allow-Headers"] = headers["access-control-request-headers"] or ""
  else
    ngx.header["Access-Control-Allow-Headers"] = table.concat(conf.headers, ",")
  end
end

local function configure_exposed_headers(ngx, conf)
  if conf.exposed_headers ~= nil then
    ngx.header["Access-Control-Expose-Headers"] = table.concat(conf.exposed_headers, ",")
  end
end

local function configure_methods(ngx, conf)
  if conf.methods == nil then
    ngx.header["Access-Control-Allow-Methods"] = "GET,HEAD,PUT,PATCH,POST,DELETE"
  else
    ngx.header["Access-Control-Allow-Methods"] = table.concat(conf.methods, ",")
  end
end

local function configure_max_age(ngx, conf)
  if conf.max_age ~= nil then
    ngx.header["Access-Control-Max-Age"] = tostring(conf.max_age)
  end
end

function CorsHandler:new()
  CorsHandler.super.new(self, "cors")
end

function CorsHandler:access(conf)
  CorsHandler.super.access(self) 
  
  if ngx.req.get_method() == OPTIONS then
    if not conf.preflight_continue then
      configure_origin(ngx, conf)
      configure_credentials(ngx, conf)
      configure_headers(ngx, conf, ngx.req.get_headers())
      configure_methods(ngx, conf)
      configure_max_age(ngx, conf)
      ngx.ctx.skip_response_headers = true -- Don't add response headers because we already added them all
      return responses.send_HTTP_NO_CONTENT()
    else
      -- Don't add any response header because we are delegating the preflight to the upstream API (conf.preflight_continue=true)
      ngx.ctx.skip_response_headers = true
    end
  end
end

function CorsHandler:header_filter(conf)
  CorsHandler.super.header_filter(self)
  
  if not ngx.ctx.skip_response_headers then
    configure_origin(ngx, conf)
    configure_credentials(ngx, conf)
    configure_exposed_headers(ngx, conf)
  end
end

return CorsHandler