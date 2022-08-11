local new_zipkin_reporter = require "kong.plugins.zipkin.reporter".new
local new_span = require "kong.plugins.zipkin.span".new
local utils = require "kong.tools.utils"
local propagation = require "kong.tracing.propagation"
local request_tags = require "kong.plugins.zipkin.request_tags"
local kong_meta = require "kong.meta"
local ngx_re = require "ngx.re"


local ngx = ngx
local ngx_var = ngx.var
local split = ngx_re.split
local subsystem = ngx.config.subsystem
local fmt = string.format
local rand_bytes = utils.get_rand_bytes

local ZipkinLogHandler = {
  VERSION = kong_meta.version,
  -- We want to run first so that timestamps taken are at start of the phase
  -- also so that other plugins might be able to use our structures
  PRIORITY = 100000,
}

local reporter_cache = setmetatable({}, { __mode = "k" })

local math_random        = math.random
local ngx_req_start_time = ngx.req.start_time
local ngx_now            = ngx.now


-- ngx.now in microseconds
local function ngx_now_mu()
  return ngx_now() * 1000000
end


-- ngx.req.start_time in microseconds
local function ngx_req_start_time_mu()
  return ngx_req_start_time() * 1000000
end


local function get_reporter(conf)
  if reporter_cache[conf] == nil then
    reporter_cache[conf] = new_zipkin_reporter(conf.http_endpoint,
                                               conf.default_service_name,
                                               conf.local_service_name,
                                               conf.connect_timeout,
                                               conf.send_timeout,
                                               conf.read_timeout)
  end
  return reporter_cache[conf]
end


local function tag_with_service_and_route(span)
  local service = kong.router.get_service()
  if service and service.id then
    span:set_tag("kong.service", service.id)
    if type(service.name) == "string" then
      span.service_name = service.name
      span:set_tag("kong.service_name", service.name)
    end
  end

  local route = kong.router.get_route()
  if route then
    if route.id then
      span:set_tag("kong.route", route.id)
    end
    if type(route.name) == "string" then
      span:set_tag("kong.route_name", route.name)
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

    local req_headers = req.get_headers()

    local header_type, trace_id, span_id, parent_id, should_sample, baggage =
      propagation.parse(req_headers, conf.header_type)

    local method = req.get_method()

    if should_sample == nil then
      should_sample = math_random() < conf.sample_ratio
    end

    if trace_id == nil then
      trace_id = rand_bytes(conf.traceid_byte_count)
    end

    local span_name = method
    local path = req.get_path()
    if conf.http_span_name == "method_path" then
      span_name = method .. ' ' .. path
    end

    local request_span = new_span(
      "SERVER",
      span_name,
      ngx_req_start_time_mu(),
      should_sample,
      trace_id,
      span_id,
      parent_id,
      baggage)

    local http_version = req.get_http_version()
    local protocol = http_version and 'HTTP/'..http_version or nil

    request_span.ip = kong.client.get_forwarded_ip()
    request_span.port = kong.client.get_forwarded_port()

    request_span:set_tag("lc", "kong")
    request_span:set_tag("http.method", method)
    request_span:set_tag("http.host", req.get_host())
    request_span:set_tag("http.path", path)
    if protocol then
      request_span:set_tag("http.protocol", protocol)
    end

    local static_tags = conf.static_tags
    if type(static_tags) == "table" then
      for i = 1, #static_tags do
        local tag = static_tags[i]
        request_span:set_tag(tag.name, tag.value)
      end
    end

    local req_tags, err = request_tags.parse(req_headers[conf.tags_header])
    if err then
      -- log a warning in case there were erroneous request tags. Don't throw the tracing away & rescue with valid tags, if any
      kong.log.warn(err)
    end
    if req_tags then
      for tag_name, tag_value in pairs(req_tags) do
        request_span:set_tag(tag_name, tag_value)
      end
    end

    ctx.zipkin = {
      request_span = request_span,
      header_type = header_type,
      proxy_span = nil,
      header_filter_finished = false,
    }
  end


  function ZipkinLogHandler:rewrite(conf) -- luacheck: ignore 212
    local zipkin = get_context(conf, kong.ctx.plugin)
    local ngx_ctx = ngx.ctx
    -- note: rewrite is logged on the request_span, not on the proxy span
    local rewrite_start_mu =
      ngx_ctx.KONG_REWRITE_START and ngx_ctx.KONG_REWRITE_START * 1000
      or ngx_now_mu()
    zipkin.request_span:annotate("krs", rewrite_start_mu)
  end


  function ZipkinLogHandler:access(conf) -- luacheck: ignore 212
    local zipkin = get_context(conf, kong.ctx.plugin)
    local ngx_ctx = ngx.ctx

    local access_start =
      ngx_ctx.KONG_ACCESS_START and ngx_ctx.KONG_ACCESS_START * 1000
      or ngx_now_mu()
    get_or_add_proxy_span(zipkin, access_start)

    propagation.set(conf.header_type, zipkin.header_type, zipkin.proxy_span, conf.default_header_type)
  end


  function ZipkinLogHandler:header_filter(conf) -- luacheck: ignore 212
    local zipkin = get_context(conf, kong.ctx.plugin)
    local ngx_ctx = ngx.ctx
    local header_filter_start_mu =
      ngx_ctx.KONG_HEADER_FILTER_START and ngx_ctx.KONG_HEADER_FILTER_START * 1000
      or ngx_now_mu()

    local proxy_span = get_or_add_proxy_span(zipkin, header_filter_start_mu)
    proxy_span:annotate("khs", header_filter_start_mu)
  end


  function ZipkinLogHandler:body_filter(conf) -- luacheck: ignore 212
    local zipkin = get_context(conf, kong.ctx.plugin)

    -- Finish header filter when body filter starts
    if not zipkin.header_filter_finished then
      local now_mu = ngx_now_mu()

      zipkin.proxy_span:annotate("khf", now_mu)
      zipkin.header_filter_finished = true
      zipkin.proxy_span:annotate("kbs", now_mu)
    end
  end

elseif subsystem == "stream" then

  initialize_request = function(conf, ctx)
    local request_span = new_span(
      "SERVER",
      "stream",
      ngx_req_start_time_mu(),
      math_random() < conf.sample_ratio,
      rand_bytes(conf.traceid_byte_count)
    )
    request_span.ip = kong.client.get_forwarded_ip()
    request_span.port = kong.client.get_forwarded_port()

    request_span:set_tag("lc", "kong")

    local static_tags = conf.static_tags
    if type(static_tags) == "table" then
      for i = 1, #static_tags do
        local tag = static_tags[i]
        request_span:set_tag(tag.name, tag.value)
      end
    end

    ctx.zipkin = {
      request_span = request_span,
      proxy_span = nil,
    }
  end


  function ZipkinLogHandler:preread(conf) -- luacheck: ignore 212
    local zipkin = get_context(conf, kong.ctx.plugin)
    local ngx_ctx = ngx.ctx
    local preread_start_mu =
      ngx_ctx.KONG_PREREAD_START and ngx_ctx.KONG_PREREAD_START * 1000
      or ngx_now_mu()

    local proxy_span = get_or_add_proxy_span(zipkin, preread_start_mu)
    proxy_span:annotate("kps", preread_start_mu)
  end
end


function ZipkinLogHandler:log(conf) -- luacheck: ignore 212
  local now_mu = ngx_now_mu()
  local zipkin = get_context(conf, kong.ctx.plugin)
  local ngx_ctx = ngx.ctx
  local request_span = zipkin.request_span
  local proxy_span = get_or_add_proxy_span(zipkin, now_mu)
  local reporter = get_reporter(conf)

  local proxy_finish_mu =
    ngx_ctx.KONG_BODY_FILTER_ENDED_AT and ngx_ctx.KONG_BODY_FILTER_ENDED_AT * 1000
    or now_mu

  if ngx_ctx.KONG_REWRITE_START and ngx_ctx.KONG_REWRITE_TIME then
    -- note: rewrite is logged on the request span, not on the proxy span
    local rewrite_finish_mu = (ngx_ctx.KONG_REWRITE_START + ngx_ctx.KONG_REWRITE_TIME) * 1000
    zipkin.request_span:annotate("krf", rewrite_finish_mu)
  end

  if subsystem == "http" then
    -- annotate access_start here instead of in the access phase
    -- because the plugin access phase is skipped when dealing with
    -- requests which are not matched by any route
    -- but we still want to know when the access phase "started"
    local access_start_mu =
      ngx_ctx.KONG_ACCESS_START and ngx_ctx.KONG_ACCESS_START * 1000
      or proxy_span.timestamp
    proxy_span:annotate("kas", access_start_mu)

    local access_finish_mu =
      ngx_ctx.KONG_ACCESS_ENDED_AT and ngx_ctx.KONG_ACCESS_ENDED_AT * 1000
      or proxy_finish_mu
    proxy_span:annotate("kaf", access_finish_mu)

    if not zipkin.header_filter_finished then
      proxy_span:annotate("khf", now_mu)
      zipkin.header_filter_finished = true
    end

    proxy_span:annotate("kbf", now_mu)

  else
    local preread_finish_mu =
      ngx_ctx.KONG_PREREAD_ENDED_AT and ngx_ctx.KONG_PREREAD_ENDED_AT * 1000
      or proxy_finish_mu
    proxy_span:annotate("kpf", preread_finish_mu)
  end

  local balancer_data = ngx_ctx.balancer_data
  if balancer_data then
    local balancer_tries = balancer_data.tries
    local upstream_connect_time = split(ngx_var.upstream_connect_time, ", ", "jo")
    for i = 1, balancer_data.try_count do
      local try = balancer_tries[i]
      local name = fmt("%s (balancer try %d)", request_span.name, i)
      local span = request_span:new_child("CLIENT", name, try.balancer_start * 1000)
      span.ip = try.ip
      span.port = try.port

      span:set_tag("kong.balancer.try", i)
      if i < balancer_data.try_count then
        span:set_tag("error", true)
        span:set_tag("kong.balancer.state", try.state)
        span:set_tag("http.status_code", try.code)
      end

      tag_with_service_and_route(span)

      if try.balancer_latency ~= nil then
        local try_connect_time = (tonumber(upstream_connect_time[i]) or 0) * 1000 -- ms
        span:finish((try.balancer_start + try.balancer_latency + try_connect_time) * 1000)
      else
        span:finish(now_mu)
      end
      reporter:report(span)
    end
    proxy_span:set_tag("peer.hostname", balancer_data.hostname) -- could be nil
    proxy_span.ip   = balancer_data.ip
    proxy_span.port = balancer_data.port
  end

  if subsystem == "http" then
    request_span:set_tag("http.status_code", kong.response.get_status())
  end
  if ngx_ctx.authenticated_consumer then
    request_span:set_tag("kong.consumer", ngx_ctx.authenticated_consumer.id)
  end
  if conf.include_credential and ngx_ctx.authenticated_credential then
    request_span:set_tag("kong.credential", ngx_ctx.authenticated_credential.id)
  end
  request_span:set_tag("kong.node.id", kong.node.get_id())

  tag_with_service_and_route(proxy_span)

  proxy_span:finish(proxy_finish_mu)
  reporter:report(proxy_span)
  request_span:finish(now_mu)
  reporter:report(request_span)

  local ok, err = ngx.timer.at(0, timer_log, reporter)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return ZipkinLogHandler
