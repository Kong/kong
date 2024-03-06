local utils = require "kong.tools.utils"
local tablex = require "pl.tablex"
local get_request = require("resty.core.base").get_request
local fastrace = require "kong.fastrace"

local ngx = ngx
local var = ngx.var
local type = type
local next = next
local pack = utils.pack
local unpack = utils.unpack
local assert = assert
local pairs = pairs
local get_method = ngx.req.get_method
local request_id_get = require "kong.tracing.request_id".get

local _M = {}
local NOOP = function() end
local available_types = {}

fastrace.init_trace_sender("127.0.0.1", 4902)

-- Record DB query
function _M.db_query(connector)
  local f = connector.query

  local function wrap(self, sql, ...)
    local ret
    if get_request() then
      ret = pack(f(self, sql, ...))
    else
      local BUFFER_SIZE = 2048
      local trace_buffer = fastrace.new_trace_buffer(BUFFER_SIZE)
      fastrace.enter_scope(trace_buffer, "kong.database.query")
      fastrace.add_string_attribute(trace_buffer, "db.statement", sql)
      fastrace.add_string_attribute(trace_buffer, "db.system", kong.db and kong.db.strategy)
      ret = pack(f(self, sql, ...))
      fastrace.exit_scope(trace_buffer)
      fastrace.finish_trace_buffer(trace_buffer)
    end

    return unpack(ret)
  end

  connector.query = wrap
end


-- Record Router span
function _M.enter_scope()
  return
end


-- Create a span without adding it to the KONG_SPANS list
function _M.create_span(...)
  return tracer.create_span(...)
end


-- Generator for different plugin phases
local function plugin_callback(phase)
  local name_memo = {}

  return function(plugin)
    local plugin_name = plugin.name
    local name = name_memo[plugin_name]
    if not name then
      name = "kong." .. phase .. ".plugin." .. plugin_name
      name_memo[plugin_name] = name
    end

    fastrace.enter_scope(ngx.ctx.trace_buffer, name)
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
    local trace_buffer = ngx.ctx.trace_buffer
    fastrace.enter_scope(trace_buffer, "kong.internal.request")
    fastrace.add_string_attribute(trace_buffer, "http.url", uri)
    fastrace.add_string_attribute(trace_buffer, "http.method", params.method or "GET")
    fastrace.add_string_attribute(trace_buffer, "http.flavor", params.version or "1.1")
    fastrace.add_string_attribute(trace_buffer, "http.user_agent", params.headers and params.headers["User-Agent"] or http._USER_AGENT)

    local http_proxy = self.proxy_opts and (self.proxy_opts.https_proxy or self.proxy_opts.http_proxy)
    if http_proxy then
      fastrace.add_string_attribute(trace_buffer, "http.proxy", http_proxy)
    end

    local res, err = request_uri(self, uri, params)
    if res then
      attributes["http.status_code"] = res.status -- number
    end
    fastrace.exit_scope(trace_buffer)

    return res, err
  end

  http.request_uri = wrap
end

--- Register available_types
-- functions in this list will be replaced with NOOP
-- if tracing module is NOT enabled.
for k, _ in pairs(_M) do
  available_types[k] = true
end
_M.available_types = available_types


-- Record inbound request
function _M.request(ctx)
  local client = kong.client

  local method = get_method()
  local scheme = ctx.scheme or var.scheme
  local host = var.host
  -- passing full URI to http.url attribute
  local req_uri = scheme .. "://" .. host .. (ctx.request_uri or var.request_uri)

  local http_flavor = ngx.req.http_version()
  if type(http_flavor) == "number" then
    http_flavor = string.format("%.1f", http_flavor)
  end

  local trace_buffer = fastrace.new_trace_buffer(8192)
  fastrace.enter_scope(trace_buffer, "kong")
  fastrace.add_string_attribute(trace_buffer, "http.method", method)
  fastrace.add_string_attribute(trace_buffer, "http.url", req_uri)
  fastrace.add_string_attribute(trace_buffer, "http.host", host)
  fastrace.add_string_attribute(trace_buffer, "http.scheme", scheme)
  fastrace.add_string_attribute(trace_buffer, "http.flavor", http_flavor)
  fastrace.add_string_attribute(trace_buffer, "http.client_ip", client.get_forwarded_ip())
  fastrace.add_string_attribute(trace_buffer, "net.peer.ip", client.get_ip())
  fastrace.add_string_attribute(trace_buffer, "kong.request.id", request_id_get())
  ngx.ctx.trace_buffer = trace_buffer
end


do
  local raw_func

  local function wrap(host, port, ...)
    if _M.dns_query ~= NOOP then
      fastrace.enter_scope(ngx.ctx.trace_buffer, "kong.dns")
    end

    local trace_buffer = ngx.ctx.trace_buffer

    local ip_addr, res_port, try_list = raw_func(host, port, ...)

    if _M.dns_query ~= NOOP then
      fastrace.add_string_attribute(trace_buffer, "dns.record.domain", host)
      fastrace.add_string_attribute(trace_buffer, "dns.record.port", tostring(port))
      if ip_addr then
        fastrace.add_string_attribute(trace_buffer, "dns.record.ip", ip_addr)
      end
      fastrace.exit_scope(trace_buffer)
    end

    return ip_addr, res_port, try_list
  end

  --- Get Wrapped DNS Query
  -- Called before Kong's config loader.
  --
  -- returns a wrapper for the provided input function `f`
  -- that stores dns info in the `kong.dns` span when the dns
  -- instrumentation is enabled.
  function _M.get_wrapped_dns_query(f)
    raw_func = f
    return wrap
  end

  -- append available_types
  available_types.dns_query = true
end


-- runloop
function _M.runloop_before_header_filter()
  local trace_buffer = ngx.ctx.trace_buffer
  fastrace.add_string_attribute(trace_buffer, "http.status_code", tostring(ngx.status))
  local r = ngx.ctx.route
  fastrace.add_string_attribute(trace_buffer, "http.route", r and r.paths and r.paths[1] or "")
end


function _M.runloop_log_before(ctx)
end

-- clean up
function _M.runloop_log_after(ctx)

  local trace_buffer = ngx.ctx.trace_buffer
  fastrace.exit_scope(trace_buffer)

  fastrace.finish_trace_buffer(trace_buffer)
  ngx.ctx.trace_buffer = nil
end

function _M.init(config)
  local trace_types = config.tracing_instrumentations
  local sampling_rate = config.tracing_sampling_rate
  assert(type(trace_types) == "table" and next(trace_types))
  assert(sampling_rate >= 0 and sampling_rate <= 1)

  local enabled = trace_types[1] ~= "off"

  if not enabled or ngx.config.subsystem == "stream" then
    for k, _ in pairs(available_types) do
      _M[k] = NOOP
    end

    _M.request = NOOP
  end

  if trace_types[1] ~= "all" then
    for k, _ in pairs(available_types) do
      if not tablex.find(trace_types, k) then
        _M[k] = NOOP
      end
    end
  end
end

return _M
