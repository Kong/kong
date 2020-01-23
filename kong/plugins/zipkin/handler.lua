local new_zipkin_reporter = require "kong.plugins.zipkin.reporter".new
local new_span = require "kong.plugins.zipkin.span".new
local to_hex = require "resty.string".to_hex

local subsystem = ngx.config.subsystem
local fmt = string.format
local char = string.char

local ZipkinLogHandler = {
  VERSION = "0.2.1",
  -- We want to run first so that timestamps taken are at start of the phase
  -- also so that other plugins might be able to use our structures
  PRIORITY = 100000,
}

local reporter_cache = setmetatable({}, { __mode = "k" })

local math_random = math.random

local baggage_mt = {
  __newindex = function()
    error("attempt to set immutable baggage", 2)
  end,
}


local function hex_to_char(c)
  return char(tonumber(c, 16))
end


local function from_hex(str)
  if str ~= nil then -- allow nil to pass through
    str = str:gsub("%x%x", hex_to_char)
  end
  return str
end


local function parse_http_headers(headers)
  local warn = kong.log.warn
  -- X-B3-Sampled: if an upstream decided to sample this request, we do too.
  local should_sample = headers["x-b3-sampled"]
  if should_sample == "1" or should_sample == "true" then
    should_sample = true
  elseif should_sample == "0" or should_sample == "false" then
    should_sample = false
  elseif should_sample ~= nil then
    warn("x-b3-sampled header invalid; ignoring.")
    should_sample = nil
  end

  -- X-B3-Flags: if it equals '1' then it overrides sampling policy
  -- We still want to warn on invalid sample header, so do this after the above
  local debug = headers["x-b3-flags"]
  if debug == "1" then
    should_sample = true
  elseif debug ~= nil then
    warn("x-b3-flags header invalid; ignoring.")
  end

  local had_invalid_id = false

  local trace_id = headers["x-b3-traceid"]
  if trace_id and ((#trace_id ~= 16 and #trace_id ~= 32) or trace_id:match("%X")) then
    warn("x-b3-traceid header invalid; ignoring.")
    had_invalid_id = true
  end

  local parent_id = headers["x-b3-parentspanid"]
  if parent_id and (#parent_id ~= 16 or parent_id:match("%X")) then
    warn("x-b3-parentspanid header invalid; ignoring.")
    had_invalid_id = true
  end

  local span_id = headers["x-b3-spanid"]
  if span_id and (#span_id ~= 16 or span_id:match("%X")) then
    warn("x-b3-spanid header invalid; ignoring.")
    had_invalid_id = true
  end

  if trace_id == nil or had_invalid_id then
    return nil
  end

  local baggage = {}
  trace_id = from_hex(trace_id)
  parent_id = from_hex(parent_id)
  span_id = from_hex(span_id)

  -- Process jaegar baggage header
  for k, v in pairs(headers) do
    local baggage_key = k:match("^uberctx%-(.*)$")
    if baggage_key then
      baggage[baggage_key] = ngx.unescape_uri(v)
    end
  end
  setmetatable(baggage, baggage_mt)

  return trace_id, span_id, parent_id, should_sample, baggage
end


local function get_reporter(conf)
  if reporter_cache[conf] == nil then
    reporter_cache[conf] = new_zipkin_reporter(conf.http_endpoint,
                                               conf.default_service_name)
  end
  return reporter_cache[conf]
end


local function tag_with_service_and_route(span)
  local service = kong.router.get_service()
  if service and service.id then
    span:set_tag("kong.service", service.id)
    local route = kong.router.get_route()
    if route and route.id then
      span:set_tag("kong.route", route.id)
    end
    if type(service.name) == "string" then
      span.service_name = service.name
    end
  end
end


-- adds the proxy span to the zipkin context, unless it already exists
local function get_or_add_proxy_span(zipkin, timestamp)
  if not zipkin.proxy_span then
    local request_span = zipkin.request_span
    zipkin.proxy_span = request_span:new_child(
      "CLIENT",
      request_span.name .. " (proxy)",
      timestamp
    )
  end
  return zipkin.proxy_span
end


local function timer_log(premature, reporter)
  if premature then
    return
  end

  local ok, err = reporter:flush()
  if not ok then
    kong.log.err("reporter flush ", err)
    return
  end
end



local initialize_request


local function get_context(conf, ctx)
  local zipkin = ctx.zipkin
  if not zipkin then
    initialize_request(conf, ctx)
    zipkin = ctx.zipkin
  end
  return zipkin
end


if subsystem == "http" then
  initialize_request = function(conf, ctx)
    local req = kong.request

    local trace_id, span_id, parent_id, should_sample, baggage =
      parse_http_headers(req.get_headers())
    local method = req.get_method()

    if should_sample == nil then
      should_sample = math_random() < conf.sample_ratio
    end

    local request_span = new_span(
      "SERVER",
      method,
      ngx.req.start_time(),
      should_sample,
      trace_id, span_id, parent_id,
      baggage)

    request_span.ip = kong.client.get_forwarded_ip()
    request_span.port = kong.client.get_forwarded_port()

    request_span:set_tag("lc", "kong")
    request_span:set_tag("http.method", method)
    request_span:set_tag("http.path", req.get_path())

    ctx.zipkin = {
      request_span = request_span,
      proxy_span = nil,
      header_filter_finished = false,
    }
  end


  function ZipkinLogHandler:rewrite(conf) -- luacheck: ignore 212
    local ctx = ngx.ctx
    local zipkin = get_context(conf, ctx)
    -- note: rewrite is logged on the request_span, not on the proxy span
    local rewrite_start = ctx.KONG_REWRITE_START / 1000
    zipkin.request_span:annotate("krs", rewrite_start)
  end


  function ZipkinLogHandler:access(conf) -- luacheck: ignore 212
    local ctx = ngx.ctx
    local zipkin = get_context(conf, ctx)

    get_or_add_proxy_span(zipkin, ctx.KONG_ACCESS_START / 1000)

    -- Want to send headers to upstream
    local proxy_span = zipkin.proxy_span
    local set_header = kong.service.request.set_header
    -- We want to remove headers if already present
    set_header("x-b3-traceid", to_hex(proxy_span.trace_id))
    set_header("x-b3-spanid", to_hex(proxy_span.span_id))
    if proxy_span.parent_id then
      set_header("x-b3-parentspanid", to_hex(proxy_span.parent_id))
    end
    local Flags = kong.request.get_header("x-b3-flags") -- Get from request headers
    if Flags then
      set_header("x-b3-flags", Flags)
    else
      set_header("x-b3-sampled", proxy_span.should_sample and "1" or "0")
    end
    for key, value in proxy_span:each_baggage_item() do
      -- XXX: https://github.com/opentracing/specification/issues/117
      set_header("uberctx-"..key, ngx.escape_uri(value))
    end
  end


  function ZipkinLogHandler:header_filter(conf) -- luacheck: ignore 212
    local ctx = ngx.ctx
    local zipkin = get_context(conf, ctx)
    local header_filter_start =
      ctx.KONG_HEADER_FILTER_STARTED_AT and ctx.KONG_HEADER_FILTER_STARTED_AT / 1000
      or ngx.now()

    local proxy_span = get_or_add_proxy_span(zipkin, header_filter_start)
    proxy_span:annotate("khs", header_filter_start)
  end


  function ZipkinLogHandler:body_filter(conf) -- luacheck: ignore 212
    local ctx = ngx.ctx
    local zipkin = get_context(conf, ctx)

    -- Finish header filter when body filter starts
    if not zipkin.header_filter_finished then
      local now = ngx.now()

      zipkin.proxy_span:annotate("khf", now)
      zipkin.header_filter_finished = true
      zipkin.proxy_span:annotate("kbs", now)
    end
  end

elseif subsystem == "stream" then

  initialize_request = function(conf, ctx)
    local request_span = new_span(
      "kong.stream",
      "SERVER",
      ngx.req.start_time(),
      math_random() < conf.sample_ratio
    )
    request_span.ip = kong.client.get_forwarded_ip()
    request_span.port = kong.client.get_forwarded_port()

    request_span:set_tag("lc", "kong")

    ctx.zipkin = {
      request_span = request_span,
      proxy_span = nil,
    }
  end


  function ZipkinLogHandler:preread(conf) -- luacheck: ignore 212
    local ctx = ngx.ctx
    local zipkin = get_context(conf, ctx)
    local preread_start = ctx.KONG_PREREAD_START / 1000

    local proxy_span = get_or_add_proxy_span(zipkin, preread_start)
    proxy_span:annotate("kps", preread_start)
  end
end


function ZipkinLogHandler:log(conf) -- luacheck: ignore 212
  local now = ngx.now()
  local ctx = ngx.ctx
  local zipkin = get_context(conf, ctx)
  local request_span = zipkin.request_span
  local proxy_span = get_or_add_proxy_span(zipkin, now)
  local reporter = get_reporter(conf)

  local proxy_finish =
    ctx.KONG_BODY_FILTER_ENDED_AT and ctx.KONG_BODY_FILTER_ENDED_AT / 1000 or now

  if ctx.KONG_REWRITE_TIME then
    -- note: rewrite is logged on the request span, not on the proxy span
    local rewrite_finish = (ctx.KONG_REWRITE_START + ctx.KONG_REWRITE_TIME) / 1000
    zipkin.request_span:annotate("krf", rewrite_finish)
  end

  if subsystem == "http" then
    -- add access_start here instead of in the access phase
    -- because the plugin access phase is skipped when dealing with
    -- requests which are not matched by any route
    -- but we still want to know when the access phase "started"
    local access_start = ctx.KONG_ACCESS_START / 1000
    proxy_span:annotate("kas", access_start)

    local access_finish =
      ctx.KONG_ACCESS_ENDED_AT and ctx.KONG_ACCESS_ENDED_AT / 1000 or proxy_finish
    proxy_span:annotate("kaf", access_finish)

    if not zipkin.header_filter_finished then
      proxy_span:annotate("khf", now)
      zipkin.header_filter_finished = true
    end

    proxy_span:annotate("kbf", now)

  else
    local preread_finish =
      ctx.KONG_PREREAD_ENDED_AT and ctx.KONG_PREREAD_ENDED_AT / 1000 or proxy_finish
    proxy_span:annotate("kpf", preread_finish)
  end

  local balancer_data = ctx.balancer_data
  if balancer_data then
    local balancer_tries = balancer_data.tries
    for i = 1, balancer_data.try_count do
      local try = balancer_tries[i]
      local name = fmt("%s (balancer try %d)", request_span.name, i)
      local span = request_span:new_child("CLIENT", name, try.balancer_start / 1000)
      span.ip = try.ip
      span.port = try.port

      span:set_tag("kong.balancer.try", i)
      if i < balancer_data.try_count then
        span:set_tag("error", true)
        span:set_tag("kong.balancer.state", try.state)
        span:set_tag("http.status_code", try.code)
      end

      tag_with_service_and_route(span)

      span:finish((try.balancer_start + try.balancer_latency) / 1000)
      reporter:report(span)
    end
    proxy_span:set_tag("peer.hostname", balancer_data.hostname) -- could be nil
    proxy_span.ip   = balancer_data.ip
    proxy_span.port = balancer_data.port
  end

  if subsystem == "http" then
    request_span:set_tag("http.status_code", kong.response.get_status())
  end
  if ctx.authenticated_consumer then
    request_span:set_tag("kong.consumer", ctx.authenticated_consumer.id)
  end
  if conf.include_credential and ctx.authenticated_credential then
    request_span:set_tag("kong.credential", ctx.authenticated_credential.id)
  end
  request_span:set_tag("kong.node.id", kong.node.get_id())

  tag_with_service_and_route(proxy_span)

  proxy_span:finish(proxy_finish)
  reporter:report(proxy_span)
  request_span:finish(now)
  reporter:report(request_span)

  local ok, err = ngx.timer.at(0, timer_log, reporter)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return ZipkinLogHandler
