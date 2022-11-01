local pdk_tracer = require "kong.pdk.tracing".new()
local utils = require "kong.tools.utils"
local tablepool = require "tablepool"
local tablex = require "pl.tablex"
local base = require "resty.core.base"
local cjson = require "cjson"
local ngx_re = require "ngx.re"

local ngx = ngx
local var = ngx.var
local type = type
local next = next
local pack = utils.pack
local unpack = utils.unpack
local insert = table.insert
local assert = assert
local pairs = pairs
local ipairs = ipairs
local new_tab = base.new_tab
local time_ns = utils.time_ns
local tablepool_release = tablepool.release
local get_method = ngx.req.get_method
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local concat = table.concat
local tonumber = tonumber
local setmetatable = setmetatable
local cjson_encode = cjson.encode
local _log_prefix = "[tracing] "
local split = ngx_re.split

local _M = {}
local tracer = pdk_tracer
local NOOP = function() end
local available_types = {}

local POOL_SPAN_STORAGE = "KONG_SPAN_STORAGE"

-- Record DB query
function _M.db_query(connector)
  local f = connector.query

  local function wrap(self, sql, ...)
    local span = tracer.start_span("query")
    span:set_attribute("db.system", kong.db and kong.db.strategy)
    span:set_attribute("db.statement", sql)
    -- raw query
    local ret = pack(f(self, sql, ...))
    -- ends span
    span:finish()

    return unpack(ret)
  end

  connector.query = wrap
end


-- Record Router span
function _M.router()
  return tracer.start_span("router")
end


--- Record OpenResty Balancer results.
-- The span includes the Lua-Land resolve DNS time
-- and the connection/response time between Nginx and upstream server.
function _M.balancer(ctx)
  local balancer_data = ctx.balancer_data
  if not balancer_data then
    return
  end

  local span
  local balancer_tries = balancer_data.tries
  local try_count = balancer_data.try_count
  local upstream_connect_time = split(var.upstream_connect_time, ", ", "jo")
  for i = 1, try_count do
    local try = balancer_tries[i]
    span = tracer.start_span("balancer try #" .. i, {
      span_kind = 3, -- client
      start_time_ns = try.balancer_start * 1e6,
      attributes = {
        ["net.peer.ip"] = try.ip,
        ["net.peer.port"] = try.port,
      }
    })

    if try.state then
      span:set_attribute("http.status_code", try.code)
      span:set_status(2)
    end

    -- last try
    if i == try_count and try.state == nil then
      local upstream_finish_time = ctx.KONG_BODY_FILTER_ENDED_AT and ctx.KONG_BODY_FILTER_ENDED_AT * 1e6
      span:finish(upstream_finish_time)

    else
      -- retrying
      if try.balancer_latency ~= nil then
        local try_upstream_connect_time = (tonumber(upstream_connect_time[i], 10) or 0) * 1000
        span:finish((try.balancer_start + try.balancer_latency + try_upstream_connect_time) * 1e6)
      else
        span:finish()
      end
    end
  end
end

-- Generator for different plugin phases
local function plugin_callback(phase)
  local name_memo = {}

  return function(plugin)
    local plugin_name = plugin.name
    local name = name_memo[plugin_name]
    if not name then
      name = phase .. " phase: " .. plugin_name
      name_memo[plugin_name] = name
    end

    return tracer.start_span(name)
  end
end

_M.plugin_rewrite = plugin_callback("rewrite")
_M.plugin_access = plugin_callback("access")
_M.plugin_header_filter = plugin_callback("header_filter")


--- Record HTTP client calls
-- This only record `resty.http.request_uri` method,
-- because it's the most common usage of lua-resty-http library.
function _M.http_client()
  local http = require "resty.http"
  local request_uri = http.request_uri

  local function wrap(self, uri, params)
    local method = params and params.method or "GET"
    local attributes = new_tab(0, 5)
    attributes["http.url"] = uri
    attributes["http.method"] = method
    attributes["http.flavor"] = params and params.version or "1.1"
    attributes["http.user_agent"] = params and params.headers and params.headers["User-Agent"]
        or http._USER_AGENT

    local http_proxy = self.proxy_opts and (self.proxy_opts.https_proxy or self.proxy_opts.http_proxy)
    if http_proxy then
      attributes["http.proxy"] = http_proxy
    end

    local span = tracer.start_span("HTTP " .. method .. " " .. uri, {
      span_kind = 3,
      attributes = attributes,
    })

    local res, err = request_uri(self, uri, params)
    if res then
      attributes["http.status_code"] = res.status -- number
    else
      span:record_error(err)
    end
    span:finish()

    return res, err
  end

  http.request_uri = wrap
end

--- Regsiter vailable_types
-- functions in this list will be replaced with NOOP
-- if tracing module is NOT enabled.
for k, _ in pairs(_M) do
  available_types[k] = true
end
_M.available_types = available_types


-- Record inbound request
function _M.request(ctx)
  local req = kong.request
  local client = kong.client

  local method = get_method()
  local path = req.get_path()
  local span_name = method .. " " .. path
  local req_uri = ctx.request_uri or var.request_uri

  local start_time = ctx.KONG_PROCESSING_START
                 and ctx.KONG_PROCESSING_START * 1e6
                  or time_ns()

  local active_span = tracer.start_span(span_name, {
    span_kind = 2, -- server
    start_time_ns = start_time,
    attributes = {
      ["http.method"] = method,
      ["http.url"] = req_uri,
      ["http.host"] = var.host,
      ["http.scheme"] = ctx.scheme or var.scheme,
      ["http.flavor"] = ngx.req.http_version(),
      ["net.peer.ip"] = client.get_ip(),
    },
  })

  tracer.set_active_span(active_span)
end


local patch_dns_query
do
  local raw_func
  local patch_callback
  local name_memo = {}

  local function wrap(host, port)
    local name = name_memo[host]
    if not name then
      name = "DNS: " .. host
      name_memo[host] = name
    end

    local span = tracer.start_span(name)
    local ip_addr, res_port, try_list = raw_func(host, port)
    if span then
      span:set_attribute("dns.record.domain", host)
      span:set_attribute("dns.record.port", port)
      span:set_attribute("dns.record.ip", ip_addr)
      span:finish()
    end

    return ip_addr, res_port, try_list
  end

  --- Patch DNS query
  -- It will be called before Kong's config loader.
  --
  -- `callback` is a function that accept a wrap function,
  -- it could be used to replace the orignal func lazily.
  --
  -- e.g. patch_dns_query(func, function(wrap)
  --   toip = wrap
  -- end)
  function _M.set_patch_dns_query_fn(func, callback)
    raw_func = func
    patch_callback = callback
  end

  -- patch lazily
  patch_dns_query = function()
    patch_callback(wrap)
  end

  -- append available_types
  available_types.dns_query = true
end

-- runloop
function _M.runloop_log_before(ctx)
  -- add balancer
  _M.balancer(ctx)

  local active_span = tracer.active_span()
  -- check root span type to avoid encounter error
  if active_span and type(active_span.finish) == "function" then
    local end_time = ctx.KONG_BODY_FILTER_ENDED_AT
                  and ctx.KONG_BODY_FILTER_ENDED_AT * 1e6
    active_span:finish(end_time)
  end
end

-- serialize lazily
local lazy_format_spans
do
  local lazy_mt = {
    __tostring = function(spans)
      local detail_logs = new_tab(#spans, 0)
      for i, span in ipairs(spans) do
        insert(detail_logs, "\nSpan #" .. i .. " name=" .. span.name)

        if span.end_time_ns then
          insert(detail_logs, " duration=" .. (span.end_time_ns - span.start_time_ns) / 1e6 .. "ms")
        end

        if span.attributes then
          insert(detail_logs, " attributes=" .. cjson_encode(span.attributes))
        end
      end

      return concat(detail_logs)
    end
  }

  lazy_format_spans = function(spans)
    return setmetatable(spans, lazy_mt)
  end
end

-- clean up
function _M.runloop_log_after(ctx)
  -- Clears the span table and put back the table pool,
  -- this avoids reallocation.
  -- The span table MUST NOT be used after released.
  if type(ctx.KONG_SPANS) == "table" then
    ngx_log(ngx_DEBUG, _log_prefix, "collected " .. #ctx.KONG_SPANS .. " spans: ", lazy_format_spans(ctx.KONG_SPANS))

    for _, span in ipairs(ctx.KONG_SPANS) do
      if type(span) == "table" and type(span.release) == "function" then
        span:release()
      end
    end

    tablepool_release(POOL_SPAN_STORAGE, ctx.KONG_SPANS)
  end
end

function _M.init(config)
  local trace_types = config.opentelemetry_tracing
  local sampling_rate = config.opentelemetry_tracing_sampling_rate
  assert(type(trace_types) == "table" and next(trace_types))
  assert(sampling_rate >= 0 and sampling_rate <= 1)

  local enabled = trace_types[1] ~= "off"

  -- noop instrumentations
  -- TODO: support stream module
  if not enabled or ngx.config.subsystem == "stream" then
    for k, _ in pairs(available_types) do
      _M[k] = NOOP
    end

    -- remove root span generator
    _M.request = NOOP
  end

  if trace_types[1] ~= "all" then
    for k, _ in pairs(available_types) do
      if not tablex.find(trace_types, k) then
        _M[k] = NOOP
      end
    end
  end

  if enabled then
    -- global tracer
    tracer = pdk_tracer.new("instrument", {
      sampling_rate = sampling_rate,
    })
    tracer.set_global_tracer(tracer)

    -- global patch
    if _M.dns_query ~= NOOP then
      patch_dns_query()
    end
  end
end

return _M
