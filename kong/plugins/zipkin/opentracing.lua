--[[
This file is not a kong plugin; but the prototype for one.

A plugin that derives this should:
  - Implement a .new_tracer(cond) method that returns an opentracing tracer
  - The tracer must support the "http_headers" format.
  - Implement a :initialise_request(conf, ctx) method if it needs to do per-request initialisation
]]

local subsystem = ngx.config.subsystem
local fmt = string.format

local OpenTracingHandler = {
  VERSION = "0.2.0",
  -- We want to run first so that timestamps taken are at start of the phase
  -- also so that other plugins might be able to use our structures
  PRIORITY = 100000,
}

local tracer_cache = setmetatable({}, {__mode = "k"})


function OpenTracingHandler:get_tracer(conf)
  local tracer = tracer_cache[conf]
  if tracer == nil then
    assert(self.new_tracer, "derived class must implement .new_tracer()")
    tracer = self.new_tracer(conf)
    assert(type(tracer) == "table", ".new_tracer() must return an opentracing tracer object")
    tracer_cache[conf] = tracer
  end
  return tracer
end


function OpenTracingHandler:get_context(conf, ctx)
  local opentracing = ctx.opentracing
  if not opentracing then
    self:initialise_request(conf, ctx)
    opentracing = ctx.opentracing
  end
  return opentracing
end


-- Utility function to set either ipv4 or ipv6 tags
-- nginx apis don't have a flag to indicate whether an address is v4 or v6
local function ip_tag(addr)
  -- use the presence of "." to signal v4 (v6 uses ":")
  if addr:find(".", 1, true) then
    return "peer.ipv4"
  else
    return "peer.ipv6"
  end
end


-- adds the proxy span to the opentracing context, unless it already exists
local function get_or_add_proxy_span(opentracing, timestamp)
  if not opentracing.proxy_span then
    local request_span = opentracing.request_span
    opentracing.proxy_span = request_span:start_child_span(
      request_span.name .. " (proxy)",
      timestamp)
    opentracing.proxy_span:set_tag("span.kind", "client")
  end
  return opentracing.proxy_span
end


if subsystem == "http" then
  function OpenTracingHandler:initialise_request(conf, ctx)
    local tracer = self:get_tracer(conf)
    local req = kong.request
    local wire_context = tracer:extract("http_headers", req.get_headers()) -- could be nil
    local method = req.get_method()
    local forwarded_ip = kong.client.get_forwarded_ip()

    local request_span = tracer:start_span(method, {
      child_of = wire_context,
      start_timestamp = ngx.req.start_time(),
      tags = {
        component = "kong",
        ["span.kind"] = "server",
        ["http.method"] = method,
        ["http.path"] = req.get_path(),
        [ip_tag(forwarded_ip)] = forwarded_ip,
        ["peer.port"] = kong.client.get_forwarded_port(),
      }
    })
    ctx.opentracing = {
      tracer = tracer,
      wire_context = wire_context,
      request_span = request_span,
      proxy_span = nil,
      header_filter_finished = false,
    }
  end


  function OpenTracingHandler:rewrite(conf)
    local ctx = ngx.ctx
    local opentracing = self:get_context(conf, ctx)
    -- note: rewrite is logged on the request_span, not on the proxy span
    local rewrite_start = ctx.KONG_REWRITE_START / 1000
    opentracing.request_span:log("kong.rewrite", "start", rewrite_start)
  end


  function OpenTracingHandler:access(conf)
    local ctx = ngx.ctx
    local opentracing = self:get_context(conf, ctx)

    get_or_add_proxy_span(opentracing, ctx.KONG_ACCESS_START / 1000)

    -- Want to send headers to upstream
    local outgoing_headers = {}
    opentracing.tracer:inject(opentracing.proxy_span, "http_headers", outgoing_headers)
    local set_header = kong.service.request.set_header
    for k, v in pairs(outgoing_headers) do
      set_header(k, v)
    end
  end


  function OpenTracingHandler:header_filter(conf)
    local ctx = ngx.ctx
    local opentracing = self:get_context(conf, ctx)
    local header_filter_start =
      ctx.KONG_HEADER_FILTER_STARTED_AT and ctx.KONG_HEADER_FILTER_STARTED_AT / 1000
      or ngx.now()

    local proxy_span = get_or_add_proxy_span(opentracing, header_filter_start)
    proxy_span:log("kong.header_filter", "start", header_filter_start)
  end


  function OpenTracingHandler:body_filter(conf)
    local ctx = ngx.ctx
    local opentracing = self:get_context(conf, ctx)

    -- Finish header filter when body filter starts
    if not opentracing.header_filter_finished then
      local now = ngx.now()

      opentracing.proxy_span:log("kong.header_filter", "finish", now)
      opentracing.header_filter_finished = true
      opentracing.proxy_span:log("kong.body_filter", "start", now)
    end
  end

elseif subsystem == "stream" then

  function OpenTracingHandler:initialise_request(conf, ctx)
    local tracer = self:get_tracer(conf)
    local wire_context = nil
    local forwarded_ip = kong.client.get_forwarded_ip()
    local request_span = tracer:start_span("kong.stream", {
      child_of = wire_context,
      start_timestamp = ngx.req.start_time(),
      tags = {
        component = "kong",
        ["span.kind"] = "server",
        [ip_tag(forwarded_ip)] = forwarded_ip,
        ["peer.port"] = kong.client.get_forwarded_port(),
      }
    })
    ctx.opentracing = {
      tracer = tracer,
      wire_context = wire_context,
      request_span = request_span,
      proxy_span = nil,
    }
  end


  function OpenTracingHandler:preread(conf)
    local ctx = ngx.ctx
    local opentracing = self:get_context(conf, ctx)
    local preread_start = ctx.KONG_PREREAD_START / 1000

    local proxy_span = get_or_add_proxy_span(opentracing, preread_start)
    proxy_span:log("kong.preread", "start", preread_start)
  end
end


function OpenTracingHandler:log(conf)
  local now = ngx.now()
  local ctx = ngx.ctx
  local opentracing = self:get_context(conf, ctx)
  local request_span = opentracing.request_span
  local proxy_span = get_or_add_proxy_span(opentracing, now)

  local proxy_finish =
    ctx.KONG_BODY_FILTER_ENDED_AT and ctx.KONG_BODY_FILTER_ENDED_AT / 1000 or now

  if ctx.KONG_REWRITE_TIME then
    -- note: rewrite is logged on the request span, not on the proxy span
    local rewrite_finish = (ctx.KONG_REWRITE_START + ctx.KONG_REWRITE_TIME) / 1000
    opentracing.request_span:log("kong.rewrite", "finish", rewrite_finish)
  end

  if subsystem == "http" then
    -- add access_start here instead of in the access phase
    -- because the plugin access phase is skipped when dealing with
    -- requests which are not matched by any route
    -- but we still want to know when the access phase "started"
    local access_start = ctx.KONG_ACCESS_START / 1000
    proxy_span:log("kong.access", "start", access_start)

    local access_finish =
      ctx.KONG_ACCESS_ENDED_AT and ctx.KONG_ACCESS_ENDED_AT / 1000 or proxy_finish
    proxy_span:log("kong.access", "finish", access_finish)

    if not opentracing.header_filter_finished then
      proxy_span:log("kong.header_filter", "finish", now)
      opentracing.header_filter_finished = true
    end

    proxy_span:log("kong.body_filter", "finish", now)

  else
    local preread_finish =
      ctx.KONG_PREREAD_ENDED_AT and ctx.KONG_PREREAD_ENDED_AT / 1000 or proxy_finish
    proxy_span:log("kong.preread", "finish", preread_finish)
  end

  local balancer_data = ctx.balancer_data
  if balancer_data then
    local balancer_tries = balancer_data.tries
    for i = 1, balancer_data.try_count do
      local try = balancer_tries[i]
      local name = fmt("%s (balancer try %d)", request_span.name, i)
      local span = request_span:start_child_span(name, try.balancer_start / 1000)
      span:set_tag(ip_tag(try.ip), try.ip)
      span:set_tag("peer.port", try.port)
      span:set_tag("kong.balancer.try", i)
      if i < balancer_data.try_count then
        span:set_tag("error", true)
        span:set_tag("kong.balancer.state", try.state)
        span:set_tag("http.status_code", try.code)
      else
        span:set_tag("error", false)
      end
      span:finish((try.balancer_start + try.balancer_latency) / 1000)
    end
    proxy_span:set_tag("peer.hostname", balancer_data.hostname) -- could be nil
    if balancer_data.ip ~= nil then
       proxy_span:set_tag(ip_tag(balancer_data.ip), balancer_data.ip)
    end
    proxy_span:set_tag("peer.port", balancer_data.port)
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
  -- TODO: should we add these tags to the request span and/or the balancer spans?
  if ctx.service and ctx.service.id then
    proxy_span:set_tag("kong.service", ctx.service.id)
    if ctx.route and ctx.route.id then
      proxy_span:set_tag("kong.route", ctx.route.id)
    end
    if type(ctx.service.name) == "string" then
      proxy_span:set_tag("peer.service", ctx.service.name)
    end
  elseif ctx.api and ctx.api.id then
    proxy_span:set_tag("kong.api", ctx.api.id)
  end

  proxy_span:finish(proxy_finish)
  request_span:finish(now)
end


function OpenTracingHandler:extend()
  return setmetatable({ super = self }, { __index = self })
end


return OpenTracingHandler
