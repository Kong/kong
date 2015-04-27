local stringy = require "stringy"

local _M = {}

local function configure_origin(ngx, conf)
  print("ORIGIN CHECK")
  print(conf.origin)
  if not conf.origin or stringy.strip(conf.origin) == "" then
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
    ngx.header["Access-Control-Allow-Headers"] = headers['access-control-request-headers'] or ""
  else
    ngx.header["Access-Control-Allow-Headers"] = conf.headers
  end
end

local function configure_exposed_headers(ngx, conf)
  if conf.exposed_headers ~= nil then
    ngx.header["Access-Control-Expose-Headers"] = conf.exposed_headers
  end
end

local function configure_methods(ngx, conf)
  if conf.methods ~= nil then
    ngx.header["Access-Control-Allow-Methods"] = conf.methods
  else
    ngx.header["Access-Control-Allow-Methods"] = "GET,HEAD,PUT,PATCH,POST,DELETE"
  end
end

local function configure_max_age(ngx, conf)
  if conf.max_age ~= nil then
    ngx.header["Access-Control-Max-Age"] = tostring(conf.max_age)
  end
end

function _M.execute(conf)
  local request = ngx.req
  local method = request.get_method()
  local headers = request.get_headers()

  configure_origin(ngx, conf)
  configure_credentials(ngx, conf)

  if method == "OPTIONS" then
    -- Preflight
    configure_headers(ngx, conf, headers)
    configure_methods(ngx, conf)
    configure_max_age(ngx, conf)

    if not conf.preflight_continue then
      utils.no_content()
    end
  else
    configure_exposed_headers(ngx, conf)
  end
end

return _M