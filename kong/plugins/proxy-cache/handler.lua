local BasePlugin  = require "kong.plugins.base_plugin"
local strategies  = require "kong.plugins.proxy-cache.strategies"
local responses   = require "kong.tools.responses"


local max              = math.max
local floor            = math.floor
local md5              = ngx.md5
local get_method       = ngx.req.get_method
local resp_get_headers = ngx.resp.get_headers
local timer_at         = ngx.timer.at
local ngx_print        = ngx.print
local ngx_log          = ngx.log
local ngx_re_gmatch    = ngx.re.gmatch
local ngx_re_match     = ngx.re.match
local parse_http_time  = ngx.parse_http_time
local str_find         = string.find
local str_lower        = string.lower
local time             = ngx.time


local tab_new = require("table.new")


local STRATEGY_PATH = "kong.plugins.proxy-cache.strategies"


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
    local expires = ngx.var.expires

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

  if conf.cache_control and (cc["private"] or cc["no-store"] or cc["no-cache"]) then
    return false
  end

  if conf.cache_control and (not cc["public"] or resource_ttl(cc) <= 0) then
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


local function build_cache_key(prefix_uuid, method, request)
  return md5(prefix_uuid .. method .. request)
end


-- define our own response sender instead of using kong.tools.responses
-- as the included response generator always send JSON content
local function send_response(res)
  ngx.status = res.status

  -- TODO refactor this to not use pairs
  for k, v in pairs(res.headers) do
    if not hop_by_hop_headers[str_lower(k)] then
      ngx.header[k] = v
    end
  end

  ngx.header["Content-Length"] = res.body_len

  ngx.header["Age"] = floor(time() - res.timestamp)
  ngx.header["X-Cache-Status"] = "Hit"

  -- TODO handle Kong-specific headers

  ngx_print(res.body)
  return ngx.exit(res.status)
end


local function prefix_uuid()
  return ngx.ctx.authenticated_consumer    and
         ngx.ctx.authenticated_consumer.id or
         ngx.ctx.api                       and
         ngx.ctx.api.id                    or
         "default"
end


local function async_store(premature, strategy, key, res, ttl)
  if premature then
    return
  end

  local ok, err = strategy:store(key, res, ttl)
  if not ok then
    ngx_log(ngx.ERR, "[proxy-cache] ", err)
  end
end


local ProxyCacheHandler = BasePlugin:extend()


ProxyCacheHandler.PRIORITY = 100


function ProxyCacheHandler:new()
  ProxyCacheHandler.super.new(self, "proxy-cache")
end

function ProxyCacheHandler:access(conf)
  ProxyCacheHandler.super.access(self)

  local cc = req_cc()

  -- if we know this request isnt cacheable, bail out
  if not cacheable_request(ngx, conf, cc) then
    ngx.header["X-Cache-Status"] = "Bypass"
    return
  end

  -- try to fetch the cached object
  -- first we need a uuid of this; try the consumer uuid, then the api uuid,
  -- and finally a default value
  local cache_key = build_cache_key(prefix_uuid(), get_method(), ngx.var.request)
  ngx.header["X-Cache-Key"] = cache_key

  local strategy = require(STRATEGY_PATH)({
    strategy_name = conf.strategy,
    strategy_opts = conf[conf.strategy],
  })

  local res, err = strategy:fetch(cache_key)
  if err == "request object not in cache" then -- TODO make this a utils enum err

    -- this request wasn't found in the data store, but the client only wanted
    -- cache data. see https://tools.ietf.org/html/rfc7234#section-5.2.1.7
    if conf.cache_control and cc["only-if-cached"] then
      return responses.send(ngx.HTTP_GATEWAY_TIMEOUT)
    end

    -- this request is cacheable but wasn't found in the data store
    -- make a note that we should store it in cache later,
    -- and pass the request upstream
    return signal_cache_req(cache_key)

  elseif err then
    ngx_log(ngx.ERR, "[proxy_cache] ", err)
    return
  end

  -- figure out if the client will accept our cache value
  if conf.cache_control then
    if cc["max-age"] and time() - res.timestamp > cc["max-age"] then
      return signal_cache_req(cache_key, "Refresh")
    end

    if cc["max-stale"] and time() - res.timestamp - res.ttl > cc["max-stale"] then
      return signal_cache_req(cache_key, "Refresh")
    end

    if cc["min-fresh"] and res.ttl - (time() - res.timestamp) < cc["min-fresh"] then
      return signal_cache_req(cache_key, "Refresh")
    end

  else
    -- don't serve stale data; res may be stored for up to `conf.storage_ttl` secs
    if time() - res.timestamp > conf.cache_ttl then
      return signal_cache_req(cache_key, "Refresh")
    end
  end

  -- we have cache data yo!
  return send_response(res)
end


function ProxyCacheHandler:header_filter(conf)
  ProxyCacheHandler.super.header_filter(self)

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
  ProxyCacheHandler.super.body_filter(self)

  local ctx = ngx.ctx.proxy_cache
  if not ctx then
    return
  end

  local chunk = ngx.arg[1]
  local eof   = ngx.arg[2]

  ctx.res_body = (ctx.res_body or "") .. (chunk or "")

  local strategy = require(STRATEGY_PATH)({
    strategy_name = conf.strategy,
    strategy_opts = conf[conf.strategy],
  })

  if eof then
    local res = {
      status    = ngx.status,
      headers   = ctx.res_headers,
      body      = ctx.res_body,
      body_len  = #ctx.res_body,
      timestamp = time(),
      ttl       = ctx.res_ttl,
    }

    local ttl = conf.storage_ttl or conf.cache_control and ctx.res_ttl or
                conf.cache_ttl

    if not strategies.DELAY_STRATEGY_STORE[conf.strategy] then
      local ok, err = strategy:store(ctx.cache_key, res, ttl)
      if not ok then
        ngx_log(ngx.ERR, "[proxy-cache] ", err)
      end

    else
      local ok, err = timer_at(0, async_store, strategy, ctx.cache_key,
                               res, ttl)
      if not ok then
        ngx_log(ngx.ERR, "[proxy-cache] ", err)
      end
    end
  else
    ngx.ctx.proxy_cache = ctx
  end
end

return ProxyCacheHandler
