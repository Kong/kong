local require     = require
local cache_key   = require "kong.plugins.proxy-cache.cache_key"
local utils       = require "kong.tools.utils"
local kong_meta   = require "kong.meta"
local mime_type   = require "kong.tools.mime_type"
local nkeys       = require "table.nkeys"


local ngx              = ngx
local kong             = kong
local type             = type
local pairs            = pairs
local tostring         = tostring
local tonumber         = tonumber
local max              = math.max
local floor            = math.floor
local lower            = string.lower
local concat           = table.concat
local time             = ngx.time
local resp_get_headers = ngx.resp and ngx.resp.get_headers
local ngx_re_gmatch    = ngx.re.gmatch
local ngx_re_sub       = ngx.re.gsub
local ngx_re_match     = ngx.re.match
local parse_http_time  = ngx.parse_http_time
local parse_mime_type  = mime_type.parse_mime_type


local tab_new = require("table.new")


local STRATEGY_PATH = "kong.plugins.proxy-cache.strategies"
local CACHE_VERSION = 1
local EMPTY = {}


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
  local n_header = lower(header)

  return not hop_by_hop_headers[n_header]
     and not ngx_re_match(n_header, "ratelimit-remaining")
end


local function parse_directive_header(h)
  if not h then
    return EMPTY
  end

  if type(h) == "table" then
    h = concat(h, ", ")
  end

  local t    = {}
  local res  = tab_new(3, 0)
  local iter = ngx_re_gmatch(h, "([^,]+)", "oj")

  local m = iter()
  while m do
    local _, err = ngx_re_match(m[0], [[^\s*([^=]+)(?:=(.+))?]],
                                "oj", nil, res)
    if err then
      kong.log.err(err)
    end

    -- store the directive token as a numeric value if it looks like a number;
    -- otherwise, store the string value. for directives without token, we just
    -- set the key to true
    t[lower(res[1])] = tonumber(res[2]) or res[2] or true

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


local function cacheable_request(conf, cc)
  -- TODO refactor these searches to O(1)
  do
    local method = kong.request.get_method()
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


local function cacheable_response(conf, cc)
  -- TODO refactor these searches to O(1)
  do
    local status = kong.response.get_status()
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

    local t, subtype, params = parse_mime_type(content_type)
    local content_match = false
    for i = 1, #conf.content_type do
      local expected_ct = conf.content_type[i]
      local exp_type, exp_subtype, exp_params = parse_mime_type(expected_ct)
      if exp_type then
        if (exp_type == "*" or t == exp_type) and
          (exp_subtype == "*" or subtype == exp_subtype) then
          local params_match = true
          for key, value in pairs(exp_params or EMPTY) do
            if value ~= (params or EMPTY)[key] then
              params_match = false
              break
            end
          end
          if params_match and
            (nkeys(params or EMPTY) == nkeys(exp_params or EMPTY)) then
            content_match = true
            break
          end
        end
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
local function signal_cache_req(ctx, cache_key, cache_status)
  ctx.proxy_cache = {
    cache_key = cache_key,
  }

  kong.response.set_header("X-Cache-Status", cache_status or "Miss")
end


local ProxyCacheHandler = {
  VERSION = kong_meta.version,
  PRIORITY = 100,
}


function ProxyCacheHandler:init_worker()
  -- catch notifications from other nodes that we purged a cache entry
  -- only need one worker to handle purges like this
  -- if/when we introduce inline LRU caching this needs to involve
  -- worker events as well
  local unpack = unpack

  kong.cluster_events:subscribe("proxy-cache:purge", function(data)
    kong.log.err("handling purge of '", data, "'")

    local plugin_id, cache_key = unpack(utils.split(data, ":"))
    local plugin, err = kong.db.plugins:select({
      id = plugin_id,
    })
    if err then
      kong.log.err("error in retrieving plugins: ", err)
      return
    end

    local strategy = require(STRATEGY_PATH)({
      strategy_name = plugin.config.strategy,
      strategy_opts = plugin.config[plugin.config.strategy],
    })

    if cache_key ~= "nil" then
      local ok, err = strategy:purge(cache_key)
      if not ok then
        kong.log.err("failed to purge cache key '", cache_key, "': ", err)
        return
      end

    else
      local ok, err = strategy:flush(true)
      if not ok then
        kong.log.err("error in flushing cache data: ", err)
      end
    end
  end)
end


function ProxyCacheHandler:access(conf)
  local cc = req_cc()

  -- if we know this request isnt cacheable, bail out
  if not cacheable_request(conf, cc) then
    kong.response.set_header("X-Cache-Status", "Bypass")
    return
  end

  local consumer = kong.client.get_consumer()
  local route = kong.router.get_route()
  local uri = ngx_re_sub(ngx.var.request, "\\?.*", "", "oj")
  local cache_key, err = cache_key.build_cache_key(consumer and consumer.id,
                                                   route    and route.id,
                                                   kong.request.get_method(),
                                                   uri,
                                                   kong.request.get_query(),
                                                   kong.request.get_headers(),
                                                   conf)
  if err then
    kong.log.err(err)
    return
  end

  kong.response.set_header("X-Cache-Key", cache_key)

  -- try to fetch the cached object from the computed cache key
  local strategy = require(STRATEGY_PATH)({
    strategy_name = conf.strategy,
    strategy_opts = conf[conf.strategy],
  })

  local ctx = kong.ctx.plugin
  local res, err = strategy:fetch(cache_key)
  if err == "request object not in cache" then -- TODO make this a utils enum err

    -- this request wasn't found in the data store, but the client only wanted
    -- cache data. see https://tools.ietf.org/html/rfc7234#section-5.2.1.7
    if conf.cache_control and cc["only-if-cached"] then
      return kong.response.exit(ngx.HTTP_GATEWAY_TIMEOUT)
    end

    ctx.req_body = kong.request.get_raw_body()

    -- this request is cacheable but wasn't found in the data store
    -- make a note that we should store it in cache later,
    -- and pass the request upstream
    return signal_cache_req(ctx, cache_key)

  elseif err then
    kong.log.err(err)
    return
  end

  if res.version ~= CACHE_VERSION then
    kong.log.notice("cache format mismatch, purging ", cache_key)
    strategy:purge(cache_key)
    return signal_cache_req(ctx, cache_key, "Bypass")
  end

  -- figure out if the client will accept our cache value
  if conf.cache_control then
    if cc["max-age"] and time() - res.timestamp > cc["max-age"] then
      return signal_cache_req(ctx, cache_key, "Refresh")
    end

    if cc["max-stale"] and time() - res.timestamp - res.ttl > cc["max-stale"]
    then
      return signal_cache_req(ctx, cache_key, "Refresh")
    end

    if cc["min-fresh"] and res.ttl - (time() - res.timestamp) < cc["min-fresh"]
    then
      return signal_cache_req(ctx, cache_key, "Refresh")
    end

  else
    -- don't serve stale data; res may be stored for up to `conf.storage_ttl` secs
    if time() - res.timestamp > conf.cache_ttl then
      return signal_cache_req(ctx, cache_key, "Refresh")
    end
  end

  -- we have cache data yo!
  -- expose response data for logging plugins
  local response_data = {
    res = res,
    req = {
      body = res.req_body,
    },
    server_addr = ngx.var.server_addr,
  }

  kong.ctx.shared.proxy_cache_hit = response_data

  local nctx = ngx.ctx
  nctx.KONG_PROXIED = true

  for k in pairs(res.headers) do
    if not overwritable_header(k) then
      res.headers[k] = nil
    end
  end

  res.headers["Age"] = floor(time() - res.timestamp)
  res.headers["X-Cache-Status"] = "Hit"

  return kong.response.exit(res.status, res.body, res.headers)
end


function ProxyCacheHandler:header_filter(conf)
  local ctx = kong.ctx.plugin
  local proxy_cache = ctx.proxy_cache
  -- don't look at our headers if
  -- a) the request wasn't cacheable, or
  -- b) the request was served from cache
  if not proxy_cache then
    return
  end

  local cc = res_cc()

  -- if this is a cacheable request, gather the headers and mark it so
  if cacheable_response(conf, cc) then
    proxy_cache.res_headers = resp_get_headers(0, true)
    proxy_cache.res_ttl = conf.cache_control and resource_ttl(cc) or conf.cache_ttl

  else
    kong.response.set_header("X-Cache-Status", "Bypass")
    ctx.proxy_cache = nil
  end

  -- TODO handle Vary header
end


function ProxyCacheHandler:body_filter(conf)
  local ctx = kong.ctx.plugin
  local proxy_cache = ctx.proxy_cache
  if not proxy_cache then
    return
  end

  local body = kong.response.get_raw_body()
  if body then
    local strategy = require(STRATEGY_PATH)({
      strategy_name = conf.strategy,
      strategy_opts = conf[conf.strategy],
    })

    local res = {
      status    = kong.response.get_status(),
      headers   = proxy_cache.res_headers,
      body      = body,
      body_len  = #body,
      timestamp = time(),
      ttl       = proxy_cache.res_ttl,
      version   = CACHE_VERSION,
      req_body  = ctx.req_body,
    }

    local ttl = conf.storage_ttl or conf.cache_control and proxy_cache.res_ttl or
                conf.cache_ttl

    local ok, err = strategy:store(proxy_cache.cache_key, res, ttl)
    if not ok then
      kong.log(err)
    end
  end
end


return ProxyCacheHandler
