local cache_key   = require "kong.plugins.proxy-cache.cache_key"
local utils       = require "kong.tools.utils"


local kong             = kong
local max              = math.max
local floor            = math.floor
local get_method       = ngx.req.get_method
local ngx_get_uri_args = ngx.req.get_uri_args
local ngx_get_headers  = ngx.req.get_headers
local resp_get_headers = ngx.resp and ngx.resp.get_headers
local ngx_log          = ngx.log
local ngx_now          = ngx.now
local ngx_re_gmatch    = ngx.re.gmatch
local ngx_re_sub       = ngx.re.gsub
local ngx_re_match     = ngx.re.match
local parse_http_time  = ngx.parse_http_time
local str_lower        = string.lower
local time             = ngx.time


local tab_new = require("table.new")


local STRATEGY_PATH = "kong.plugins.proxy-cache.strategies"
local CACHE_VERSION = 1


local function get_now()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end


-- http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html#sec13.5.1
-- note content-length is not strictly hop-by-hop but we will be
-- adjusting it here anyhow
local hop_by_hop_headers = {
  ["connection"]          = true,
  ["keep-alive"]          = true,
  ["proxy-authenticate"]  = true,
  ["proxy-authorization"] = true,
  ["te"]                  = true,
  ["trailers"]            = true,
  ["transfer-encoding"]   = true,
  ["upgrade"]             = true,
  ["content-length"]      = true,
}


local function overwritable_header(header)
  local n_header = str_lower(header)

  return     not hop_by_hop_headers[n_header]
         and not (ngx_re_match(n_header, "ratelimit-remaining"))
end


local function parse_directive_header(h)
  if not h then
    return {}
  end

  if type(h) == "table" then
    h = table.concat(h, ", ")
  end

  local t    = {}
  local res  = tab_new(3, 0)
  local iter = ngx_re_gmatch(h, "([^,]+)", "oj")

  local m = iter()
  while m do
    local _, err = ngx_re_match(m[0], [[^\s*([^=]+)(?:=(.+))?]],
                                "oj", nil, res)
    if err then
      ngx_log(ngx.ERR, "[proxy-cache] ", err)
    end

    -- store the directive token as a numeric value if it looks like a number;
    -- otherwise, store the string value. for directives without token, we just
    -- set the key to true
    t[str_lower(res[1])] = tonumber(res[2]) or res[2] or true

    m = iter()
  end

  return t
end


local function req_cc()
  return parse_directive_header(ngx.var.http_cache_control)
end


local function res_cc()
  return parse_directive_header(ngx.var.sent_http_cache_control)
end


local function resource_ttl(res_cc)
  local max_age = res_cc["s-maxage"] or res_cc["max-age"]

  if not max_age then
    local expires = ngx.var.sent_http_expires

    -- if multiple Expires headers are present, last one wins
    if type(expires) == "table" then
      expires = expires[#expires]
    end

    local exp_time = parse_http_time(tostring(expires))
    if exp_time then
      max_age = exp_time - time()
    end
  end

  return max_age and max(max_age, 0) or 0
end


local function cacheable_request(ngx, conf, cc)
  -- TODO refactor these searches to O(1)
  do
    local method = get_method()

    local method_match = false
    for i = 1, #conf.request_method do
      if conf.request_method[i] == method then
        method_match = true
        break
      end
    end

    if not method_match then
      return false
    end
  end

  -- check for explicit disallow directives
  -- TODO note that no-cache isnt quite accurate here
  if conf.cache_control and (cc["no-store"] or cc["no-cache"] or
     ngx.var.authorization) then
    return false
  end

  return true
end


local function cacheable_response(ngx, conf, cc)
  -- TODO refactor these searches to O(1)
  do
    local status = ngx.status

    local status_match = false
    for i = 1, #conf.response_code do
      if conf.response_code[i] == status then
        status_match = true
        break
      end
    end

    if not status_match then
      return false
    end
  end

  do
    local content_type = ngx.var.sent_http_content_type

    -- bail if we cannot examine this content type
    if not content_type or type(content_type) == "table" or
       content_type == "" then

      return false
    end

    local content_match = false
    for i = 1, #conf.content_type do
      if conf.content_type[i] == content_type then
        content_match = true
        break
      end
    end

    if not content_match then
      return false
    end
  end

  if conf.cache_control and (cc["private"] or cc["no-store"] or cc["no-cache"])
  then
    return false
  end

  if conf.cache_control and resource_ttl(cc) <= 0 then
    return false
  end

  return true
end


-- indicate that we should attempt to cache the response to this request
local function signal_cache_req(cache_key, cache_status)
  ngx.ctx.proxy_cache = {
    cache_key = cache_key,
  }

  ngx.header["X-Cache-Status"] = cache_status or "Miss"
end


-- define our own response sender instead of using kong.tools.responses
-- as the included response generator always send JSON content
local function send_response(res)
  -- simulate the access.after handler
  --===========================================================
  local now = get_now()

  ngx.ctx.KONG_ACCESS_TIME = now - ngx.ctx.KONG_ACCESS_START
  ngx.ctx.KONG_ACCESS_ENDED_AT = now

  local proxy_latency = now - ngx.req.start_time() * 1000

  ngx.ctx.KONG_PROXY_LATENCY = proxy_latency

  ngx.ctx.KONG_PROXIED = true
  --===========================================================

  ngx.status = res.status

  -- TODO refactor this to not use pairs
  for k, v in pairs(res.headers) do
    if overwritable_header(k) then
      ngx.header[k] = v
    end
  end

  ngx.header["Age"] = floor(time() - res.timestamp)
  ngx.header["X-Cache-Status"] = "Hit"

  ngx.ctx.delayed_response = true
  ngx.ctx.delayed_response_callback = function()
    ngx.say(res.body)
  end
end


local ProxyCacheHandler = {
  VERSION  = "1.2.1",
  PRIORITY = 100,
}


function ProxyCacheHandler:init_worker()
  -- catch notifications from other nodes that we purged a cache entry
  local cluster_events = kong.cluster_events

  -- only need one worker to handle purges like this
  -- if/when we introduce inline LRU caching this needs to involve
  -- worker events as well
  cluster_events:subscribe("proxy-cache:purge", function(data)
    ngx.log(ngx.ERR, "[proxy-cache] handling purge of '", data, "'")

    local plugin_id, cache_key = unpack(utils.split(data, ":"))

    local plugin, err = kong.db.plugins:select({
      id = plugin_id,
    })
    if err then
      ngx_log(ngx.ERR, "[proxy-cache] error in retrieving plugins: ", err)
      return
    end

    local strategy = require(STRATEGY_PATH)({
      strategy_name = plugin.config.strategy,
      strategy_opts = plugin.config[plugin.config.strategy],
    })

    if cache_key ~= "nil" then
      local ok, err = strategy:purge(cache_key)
      if not ok then
        ngx_log(ngx.ERR, "[proxy-cache] failed to purge cache key '", cache_key,
              "': ", err)
        return
      end

    else
      local ok, err = strategy:flush(true)
      if not ok then
        ngx_log(ngx.ERR, "[proxy-cache] error in flushing cache data: ", err)
      end
    end
  end)
end


function ProxyCacheHandler:access(conf)
  local cc = req_cc()

  -- if we know this request isnt cacheable, bail out
  if not cacheable_request(ngx, conf, cc) then
    ngx.header["X-Cache-Status"] = "Bypass"
    return
  end

  local ctx = ngx.ctx
  local consumer_id = ctx.authenticated_consumer and ctx.authenticated_consumer.id
  local api_id = ctx.api and ctx.api.id
  local route_id = ctx.route and ctx.route.id

  local cache_key = cache_key.build_cache_key(consumer_id, api_id, route_id,
    get_method(),
    ngx_re_sub(ngx.var.request, "\\?.*", "", "oj"),
    ngx_get_uri_args(),
    ngx_get_headers(100),
    conf)

  ngx.header["X-Cache-Key"] = cache_key

  -- try to fetch the cached object from the computed cache key
  local strategy = require(STRATEGY_PATH)({
    strategy_name = conf.strategy,
    strategy_opts = conf[conf.strategy],
  })

  local res, err = strategy:fetch(cache_key)
  if err == "request object not in cache" then -- TODO make this a utils enum err

    -- this request wasn't found in the data store, but the client only wanted
    -- cache data. see https://tools.ietf.org/html/rfc7234#section-5.2.1.7
    if conf.cache_control and cc["only-if-cached"] then
      return kong.response.exit(ngx.HTTP_GATEWAY_TIMEOUT)
    end

    ngx.req.read_body()
    ngx.ctx.req_body = ngx.req.get_body_data()

    -- this request is cacheable but wasn't found in the data store
    -- make a note that we should store it in cache later,
    -- and pass the request upstream
    return signal_cache_req(cache_key)

  elseif err then
    ngx_log(ngx.ERR, "[proxy_cache] ", err)
    return
  end

  if res.version ~= CACHE_VERSION then
    ngx_log(ngx.NOTICE, "[proxy-cache] cache format mismatch, purging ",
            cache_key)
    strategy:purge(cache_key)
    return signal_cache_req(cache_key, "Bypass")
  end

  -- figure out if the client will accept our cache value
  if conf.cache_control then
    if cc["max-age"] and time() - res.timestamp > cc["max-age"] then
      return signal_cache_req(cache_key, "Refresh")
    end

    if cc["max-stale"] and time() - res.timestamp - res.ttl > cc["max-stale"]
    then
      return signal_cache_req(cache_key, "Refresh")
    end

    if cc["min-fresh"] and res.ttl - (time() - res.timestamp) < cc["min-fresh"]
    then
      return signal_cache_req(cache_key, "Refresh")
    end

  else
    -- don't serve stale data; res may be stored for up to `conf.storage_ttl` secs
    if time() - res.timestamp > conf.cache_ttl then
      return signal_cache_req(cache_key, "Refresh")
    end
  end

  -- expose response data for logging plugins
  ngx.ctx.proxy_cache_hit = {
    res = res,
    req = {
      body = res.req_body,
    },
    server_addr = ngx.var.server_addr,
  }

  -- we have cache data yo!
  return send_response(res)
end


function ProxyCacheHandler:header_filter(conf)
  local ctx = ngx.ctx.proxy_cache
  -- dont look at our headers if
  -- a). the request wasnt cachable or
  -- b). the request was served from cache
  if not ctx then
    return
  end

  local cc = res_cc()

  -- if this is a cacheable request, gather the headers and mark it so
  if cacheable_response(ngx, conf, cc) then
    ctx.res_headers = resp_get_headers(0, true)
    ctx.res_ttl = conf.cache_control and resource_ttl(cc) or conf.cache_ttl
    ngx.ctx.proxy_cache = ctx

  else
    ngx.header["X-Cache-Status"] = "Bypass"
    ngx.ctx.proxy_cache = nil
  end

  -- TODO handle Vary header
end


function ProxyCacheHandler:body_filter(conf)
  local ctx = ngx.ctx.proxy_cache
  if not ctx then
    return
  end

  local chunk = ngx.arg[1]
  local eof   = ngx.arg[2]

  ctx.res_body = (ctx.res_body or "") .. (chunk or "")

  if eof then
    local strategy = require(STRATEGY_PATH)({
      strategy_name = conf.strategy,
      strategy_opts = conf[conf.strategy],
    })

    local res = {
      status    = ngx.status,
      headers   = ctx.res_headers,
      body      = ctx.res_body,
      body_len  = #ctx.res_body,
      timestamp = time(),
      ttl       = ctx.res_ttl,
      version   = CACHE_VERSION,
      req_body  = ngx.ctx.req_body,
    }

    local ttl = conf.storage_ttl or conf.cache_control and ctx.res_ttl or
                conf.cache_ttl

    local ok, err = strategy:store(ctx.cache_key, res, ttl)
    if not ok then
      ngx_log(ngx.ERR, "[proxy-cache] ", err)
    end

  else
    ngx.ctx.proxy_cache = ctx
  end
end


return ProxyCacheHandler
