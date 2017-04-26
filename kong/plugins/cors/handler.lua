local BasePlugin = require "kong.plugins.base_plugin"
local responses  = require "kong.tools.responses"


local req_get_method  = ngx.req.get_method
local re_find         = ngx.re.find
local concat          = table.concat
local tostring        = tostring
local ipairs          = ipairs


local CorsHandler = BasePlugin:extend()


CorsHandler.PRIORITY = 2000


local function configure_origin(ngx, conf)
  if not conf.origins then
    ngx.header["Access-Control-Allow-Origin"] = "*"
    ngx.ctx.cors_allow_all = true
    return
  end

  if #conf.origins == 1 then
    if conf.origins[1] == "*" then
      ngx.ctx.cors_allow_all = true

    else
      ngx.header["Vary"] = "Origin"
    end

    ngx.header["Access-Control-Allow-Origin"] = conf.origins[1]
    return
  end

  local req_origin = ngx.var.http_origin
  if req_origin then
    for _, domain in ipairs(conf.origins) do
      local from, _, err = re_find(req_origin,
                                   [[\Q]] .. domain .. [[\E$]],
                                   "jo")
      if err then
        ngx.log(ngx.ERR, "[cors] could not search for domain: ", err)
      end

      if from then
        ngx.header["Access-Control-Allow-Origin"] = req_origin
        ngx.header["Vary"] = "Origin"
        return
      end
    end
  end
end


local function configure_credentials(ngx, conf)
  if conf.credentials then
    if not ngx.ctx.cors_allow_all then
      ngx.header["Access-Control-Allow-Credentials"] = "true"
      return
    end

    -- Access-Control-Allow-Origin is '*', must change it because ACAC cannot
    -- be 'true' if ACAO is '*'.
    local req_origin = ngx.var.http_origin
    if req_origin then
      ngx.header["Access-Control-Allow-Origin"]      = req_origin
      ngx.header["Access-Control-Allow-Credentials"] = "true"
    end
  end
end


local function configure_headers(ngx, conf)
  if not conf.headers then
    ngx.header["Access-Control-Allow-Headers"] = ngx.var["http_access_control_request_headers"] or ""

  else
    ngx.header["Access-Control-Allow-Headers"] = concat(conf.headers, ",")
  end
end


local function configure_exposed_headers(ngx, conf)
  if conf.exposed_headers then
    ngx.header["Access-Control-Expose-Headers"] = concat(conf.exposed_headers, ",")
  end
end


local function configure_methods(ngx, conf)
  if not conf.methods then
    ngx.header["Access-Control-Allow-Methods"] = "GET,HEAD,PUT,PATCH,POST,DELETE"

  else
    ngx.header["Access-Control-Allow-Methods"] = concat(conf.methods, ",")
  end
end


local function configure_max_age(ngx, conf)
  if conf.max_age then
    ngx.header["Access-Control-Max-Age"] = tostring(conf.max_age)
  end
end


function CorsHandler:new()
  CorsHandler.super.new(self, "cors")
end


function CorsHandler:access(conf)
  CorsHandler.super.access(self)

  if req_get_method() == "OPTIONS" then
    if not conf.preflight_continue then
      configure_origin(ngx, conf)
      configure_credentials(ngx, conf)
      configure_headers(ngx, conf)
      configure_methods(ngx, conf)
      configure_max_age(ngx, conf)

      -- Don't add response headers because we already added them all
      ngx.ctx.skip_response_headers = true

      return responses.send_HTTP_NO_CONTENT()
    end

    -- Don't add any response header because we are delegating the preflight to
    -- the upstream API (conf.preflight_continue=true)
    ngx.ctx.skip_response_headers = true
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
