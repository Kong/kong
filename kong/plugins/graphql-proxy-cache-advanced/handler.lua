-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local time             = ngx.time
local resp_get_headers = ngx.resp and ngx.resp.get_headers
local ngx_now          = ngx.now
local ngx_re_match     = ngx.re.match
local floor            = math.floor
local str_lower        = string.lower

local ee = require "kong.enterprise_edition"
local cache_key = require "kong.plugins.graphql-proxy-cache-advanced.cache_key"

local STRATEGY_PATH = "kong.plugins.graphql-proxy-cache-advanced.strategies"
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

  return not hop_by_hop_headers[n_header] and
         not (ngx_re_match(n_header, "ratelimit-remaining"))
end


local function signal_cache_req(cache_key, cache_status)
  ngx.ctx.gql_proxy_cache = {
    cache_key = cache_key,
  }

  kong.response.set_header("X-Cache-Status", cache_status or "Miss")
end


local _GqlCacheHandler = {}


_GqlCacheHandler.PRIORITY = 100
_GqlCacheHandler.VERSION = "0.2.2"


function _GqlCacheHandler:access(conf)
  local body_raw = kong.request.get_raw_body()
  local http_method = kong.request.get_method()

  -- skip it if there is no body in the request
  if not body_raw or http_method ~= 'POST' then
    return
  end

  local strategy = require(STRATEGY_PATH)({
    strategy_name = conf.strategy,
    strategy_opts = conf[conf.strategy],
  })

  local ctx = ngx.ctx
  local route_id = ctx.route and ctx.route.id

  -- build cache key
  local cache_key = cache_key.build_cache_key(route_id, body_raw,
      kong.request.get_headers(), conf.vary_headers)

  ngx.header["X-Cache-Key"] = cache_key

  -- check cache
  local res, err = strategy:fetch(cache_key)

  if err == "request object not in cache" then
    if not res then
      -- this request is cacheable but wasn't found in the data store
      -- make a note that we should store it in cache later,
      -- and pass the request upstream
      return signal_cache_req(cache_key)
    end
  elseif err then
    kong.log.err(err)
    return
  end

  if res.version ~= CACHE_VERSION then
    kong.log.notice("[proxy-cache] cache format mismatch, purging ", cache_key)
    strategy:purge(cache_key)
    return signal_cache_req(cache_key, "Bypass")
  end

  -- don't serve stale data
  if time() - res.timestamp > conf.cache_ttl then
    return signal_cache_req(cache_key, "Refresh")
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
  nctx.proxy_cache_hit = response_data -- TODO: deprecated

  local now = get_now()

  nctx.KONG_ACCESS_TIME = now - nctx.KONG_ACCESS_START
  nctx.KONG_ACCESS_ENDED_AT = now

  local proxy_latency = now - ngx.req.start_time() * 1000

  nctx.KONG_PROXY_LATENCY = proxy_latency
  nctx.KONG_PROXIED = true

  ee.handlers.log.after(nctx)

  for k in pairs(res.headers) do
    if not overwritable_header(k) then
      res.headers[k] = nil
    end
  end

  res.headers["Age"] = floor(time() - res.timestamp)
  res.headers["X-Cache-Status"] = "Hit"

  return kong.response.exit(res.status, res.body, res.headers)
end

function _GqlCacheHandler:header_filter(conf)
  local ctx = ngx.ctx.gql_proxy_cache
  if not ctx then
    return
  end

  ctx.res_headers = resp_get_headers(0, true)
  ctx.res_ttl = conf.cache_ttl
  ngx.ctx.gql_proxy_cache = ctx
end

function _GqlCacheHandler:body_filter(conf)
  local ctx = ngx.ctx.gql_proxy_cache
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

    local ok, err = strategy:store(ctx.cache_key, res, ctx.res_ttl)
    if not ok then
      kong.log.err("[proxy-cache] ", err)
    end
  else
    ngx.ctx.gql_proxy_cache = ctx
  end

end


return _GqlCacheHandler
