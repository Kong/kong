local BasePlugin = require "kong.plugins.base_plugin"


local kong     = kong
local re_find  = ngx.re.find
local concat   = table.concat
local tostring = tostring
local ipairs   = ipairs


local NO_CONTENT = 204


local CorsHandler = BasePlugin:extend()


CorsHandler.PRIORITY = 2000
CorsHandler.VERSION = "1.0.0"


local function configure_origin(conf)
  local n_origins = conf.origins ~= nil and #conf.origins or 0
  local set_header = kong.response.set_header

  if n_origins == 0 then
    set_header("Access-Control-Allow-Origin", "*")
    return true
  end

  if n_origins == 1 then
    if conf.origins[1] == "*" then
      set_header("Access-Control-Allow-Origin", "*")
      return true
    end

    set_header("Vary", "Origin")

    -- if this doesnt look like a regex, set the ACAO header directly
    -- otherwise, we'll fall through to an iterative search and
    -- set the ACAO header based on the client Origin
    local from, _, err = re_find(conf.origins[1], "^[A-Za-z0-9.:/-]+$", "jo")
    if err then
      kong.log.err("could not inspect origin for type: ", err)
    end

    if from then
      set_header("Access-Control-Allow-Origin", conf.origins[1])
      return false
    end
  end

  local req_origin = kong.request.get_header("origin")
  if req_origin then
    for _, domain in ipairs(conf.origins) do
      local from, _, err = re_find(req_origin, domain, "jo")
      if err then
        kong.log.err("could not search for domain: ", err)
      end

      if from then
        set_header("Access-Control-Allow-Origin", req_origin)
        set_header("Vary", "Origin")
        return false
      end
    end
  end
  return false
end


local function configure_credentials(conf, allow_all)
  local set_header = kong.response.set_header

  if not conf.credentials then
    return
  end

  if not allow_all then
    set_header("Access-Control-Allow-Credentials", true)
    return
  end

  -- Access-Control-Allow-Origin is '*', must change it because ACAC cannot
  -- be 'true' if ACAO is '*'.
  local req_origin = kong.request.get_header("origin")
  if req_origin then
    set_header("Access-Control-Allow-Origin", req_origin)
    set_header("Access-Control-Allow-Credentials", true)
    set_header("Vary", "Origin")
  end
end


function CorsHandler:new()
  CorsHandler.super.new(self, "cors")
end


function CorsHandler:access(conf)
  CorsHandler.super.access(self)

  if kong.request.get_method() ~= "OPTIONS" then
    return
  end

  -- don't add any response header because we are delegating the preflight to
  -- the upstream API (conf.preflight_continue=true), or because we already
  -- added them all
  kong.ctx.plugin.skip_response_headers = true

  if conf.preflight_continue then
    return
  end

  local allow_all = configure_origin(conf)
  configure_credentials(conf, allow_all)

  local set_header = kong.response.set_header

  if conf.headers and #conf.headers > 0 then
    set_header("Access-Control-Allow-Headers", concat(conf.headers, ","))

  else
    local acrh = kong.request.get_header("Access-Control-Request-Headers")
    if acrh then
      set_header("Access-Control-Allow-Headers", acrh)
    else
      kong.response.clear_header("Access-Control-Allow-Headers")
    end
  end

  local methods = conf.methods and concat(conf.methods, ",")
                  or "GET,HEAD,PUT,PATCH,POST,DELETE"
  set_header("Access-Control-Allow-Methods", methods)

  if conf.max_age then
    set_header("Access-Control-Max-Age", tostring(conf.max_age))
  end

  return kong.response.exit(NO_CONTENT)
end


function CorsHandler:header_filter(conf)
  CorsHandler.super.header_filter(self)

  if kong.ctx.plugin.skip_response_headers then
    return
  end

  local allow_all = configure_origin(conf)
  configure_credentials(conf, allow_all)

  if conf.exposed_headers and #conf.exposed_headers > 0 then
    kong.response.set_header("Access-Control-Expose-Headers",
                             concat(conf.exposed_headers, ","))
  end
end


return CorsHandler
