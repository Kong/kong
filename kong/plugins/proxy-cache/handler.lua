local BasePlugin  = require "kong.plugins.base_plugin"
local strategies  = require "kong.plugins.proxy-cache.strategies"


local floor            = math.floor
local md5              = ngx.md5
local get_method       = ngx.req.get_method
local resp_get_headers = ngx.resp.get_headers
local timer_at         = ngx.timer.at
local ngx_print        = ngx.print
local ngx_log          = ngx.log
local str_find         = string.find
local str_lower        = string.lower
local time             = ngx.time


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


local function cacheable_request(ngx, conf)
  -- TODO refactor these searches to O(1)
  local method = get_method()

  for i = 1, #conf.request_method do
    if conf.request_method[i] == method then
      return true
    end
  end

  return false
end


local function cacheable_response(ngx, conf)
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

    for i = 1, #conf.content_type do
      if conf.content_type[i] == content_type then
        return true
      end
    end

    return false
  end
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

  -- chunked responses have no content length, otherwise we set it ourselves
  -- TODO store the length as part of the entity so we dont have to recalculate
  if not res.headers["Transfer-Encoding"] or
     not str_find(res.headers["Transfer-Encoding"], "chunked", nil, true) then
    ngx.header["Content-Length"] = #res.body
  end

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

  -- if we know this request isnt cacheable, bail out
  if not cacheable_request(ngx, conf) then
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
    -- this request is cacheable but wasnt found in the data store
    -- make a note that we should store it in cache later,
    -- and pass the request upstream

    ngx.ctx.proxy_cache = {
      cache_key = cache_key,
    }

    ngx.header["X-Cache-Status"] = "Miss"
    return

  elseif err then
    ngx_log(ngx.ERR, "[proxy_cache] ", err)
    return
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

  -- if this is a cacheable request, gather the headers and mark it so
  if cacheable_response(ngx, conf) then
    ctx.res_headers = resp_get_headers(0, true)
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
      timestamp = time(),
    }

    if not strategies.DELAY_STRATEGY_STORE[conf.strategy] then
      local ok, err = strategy:store(ctx.cache_key, res, conf.cache_ttl)
      if not ok then
        ngx_log(ngx.ERR, "[proxy-cache] ", err)
      end

    else
      local ok, err = timer_at(0, async_store, strategy, ctx.cache_key,
                               res, conf.cache_ttl)
      if not ok then
        ngx_log(ngx.ERR, "[proxy-cache] ", err)
      end
    end
  else
    ngx.ctx.proxy_cache = ctx
  end
end

return ProxyCacheHandler
