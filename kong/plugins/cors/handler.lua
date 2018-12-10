local BasePlugin = require "kong.plugins.base_plugin"
local lrucache   = require "resty.lrucache"
local url        = require "socket.url"


local kong     = kong
local re_find  = ngx.re.find
local concat   = table.concat
local tostring = tostring
local ipairs   = ipairs


local HTTP_OK = 200


local CorsHandler = BasePlugin:extend()


CorsHandler.PRIORITY = 2000
CorsHandler.VERSION = "1.0.0"


-- per-plugin cache of normalized origins for runtime comparison
local mt_cache = { __mode = "k" }
local config_cache = setmetatable({}, mt_cache)


-- per-worker cache of parsed requests origins with 1000 slots
local normalized_req_domains = lrucache.new(10e3)


local function normalize_origin(domain)
  local parsed_obj = assert(url.parse(domain))
  if not parsed_obj.host then
    return domain
  end

  local port = parsed_obj.port
  if not port and parsed_obj.scheme then
    if parsed_obj.scheme == "http" then
      port = 80

    elseif parsed_obj.scheme == "https" then
      port = 443
    end
  end

  return (parsed_obj.scheme and parsed_obj.scheme .. "://" or "") ..
          parsed_obj.host .. (port and ":" .. port or "")
end


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
    local normalized_domains = config_cache[conf]
    if not normalized_domains then
      normalized_domains = {}

      for _, domain in ipairs(conf.origins) do
        table.insert(normalized_domains, normalize_origin(domain))
      end

      config_cache[conf] = normalized_domains
    end

    local normalized_req_origin = normalized_req_domains:get(req_origin)
    if not normalized_req_origin then
      normalized_req_origin = normalize_origin(req_origin)
      normalized_req_domains:set(req_origin, normalized_req_origin)
    end

    for _, normalized_domain in ipairs(normalized_domains) do
      local from, _, err = re_find(normalized_req_origin,
                                   normalized_domain .. "$", "ajo")
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

  return kong.response.exit(HTTP_OK)
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
