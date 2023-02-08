-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local BatchQueue = require "kong.tools.batch_queue"
local http = require "resty.http"
local encoder = require "kong.plugins.datadog-tracing.encoder"
local propagation = require "kong.tracing.propagation"
local meta = require "kong.meta"
local new_tab = require "table.new"

local ngx = ngx
local kong = kong
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG
local ngx_now = ngx.now
local ngx_update_time = ngx.update_time
local ngx_req = ngx.req
local ngx_get_headers = ngx_req.get_headers
local propagation_parse = propagation.parse
local propagation_set = propagation.set
local transform_span = encoder.transform_span
local encode_spans = encoder.encode_spans
local insert = table.insert


local DD_AGENT_HOST = os.getenv("KONG_DATADOG_AGENT_HOST") or os.getenv("DD_AGENT_HOST") or "localhost"
local DD_AGENT_PORT = tonumber(os.getenv("KONG_DATADOG_AGENT_PORT") or os.getenv("DD_AGENT_PORT") or "8126")

local default_trace_url = string.format("http://%s:%d/v0.4/traces", DD_AGENT_HOST, DD_AGENT_PORT)

local _log_prefix = "[dd-tracing] "

local DatadogHandler = {
  VERSION = meta.core_version,
  PRIORITY = 13,
}

local default_headers = {
  ["Content-Type"] = "application/msgpack",
}

-- worker-level spans queue
local queues = {} -- one queue per unique plugin config

local function http_export_request(conf, encoded_data)
  local endpoint = conf.endpoint or default_trace_url

  local httpc = http.new()
  httpc:set_timeouts(conf.connect_timeout, conf.send_timeout, conf.read_timeout)
  local res, err = httpc:request_uri(endpoint, {
    method = "POST",
    body = encoded_data,
    headers = default_headers,
  })
  if not res then
    return false, "failed to send request: " .. err

  elseif res and res.status ~= 200 then
    return false, "response error: " .. tostring(res.status) .. ", body: " .. tostring(res.body)
  end

  return true
end


local function http_export(conf, spans)
  local start = ngx_now()
  local payload = encode_spans(spans)

  local ok, err = http_export_request(conf, payload)

  ngx_update_time()
  local duration = ngx_now() - start
  ngx_log(ngx_DEBUG, _log_prefix, "exporter sent " .. #spans ..
    " traces to " .. conf.endpoint .. " in " .. duration .. " seconds")

  if not ok then
    ngx_log(ngx_ERR, _log_prefix, err)
  end

  return ok, err
end

local function process_span(span, segment, conf, origin)
  if span.should_sample == false or kong.ctx.plugin.should_sample == false then
    -- ignore
    return
  end

  -- overwrite
  local trace_id = kong.ctx.plugin.trace_id
  if trace_id then
    span.trace_id = trace_id
  end

  local dd_span = transform_span(span, conf.service_name, origin)

  insert(segment, dd_span)
end


-- Service / Route and Consumer are indentified in the access phase
function DatadogHandler:access(conf)
  local headers = ngx_get_headers()
  local root_span = ngx.ctx.KONG_SPANS and ngx.ctx.KONG_SPANS[1]

  local origin = headers["x-datadog-origin"]
  kong.ctx.plugin.origin = origin

  if root_span then
    -- Set datadog tags (currently only 'env')
    if conf.environment then
      root_span:set_attribute("env", conf.environment)
    end

    local service = kong.router.get_service()
    if service and service.id then
      root_span:set_attribute("kong.service_id", service.id)
      if type(service.name) == "string" then
        root_span:set_attribute("kong.service_name", service.name)
      end
    end

    local route = kong.router.get_route()
    if route then
      if route.id then
        root_span:set_attribute("kong.route_id", route.id)
      end
      if type(route.name) == "string" then
        root_span:set_attribute("kong.route_name", route.name)
      end
    end

  else
    -- make propagation running with tracing instrumetation not enabled
    local tracer = kong.tracing.new("dd-tracing")
    root_span = tracer.start_span("root")

    -- the span created only for the propagation and will be bypassed to the exporter
    kong.ctx.plugin.should_sample = false
  end

  local header_type, trace_id, span_id, parent_id, should_sample, _ = propagation_parse(headers)
  if should_sample == false then
    root_span.should_sample = should_sample
  end

  -- overwrite trace id
  if trace_id then
    root_span.trace_id = trace_id
    kong.ctx.plugin.trace_id = trace_id
  end

  -- overwrite root span's parent_id
  if span_id then
    root_span.parent_id = span_id

  elseif parent_id then
    root_span.parent_id = parent_id
  end

  if origin then
    kong.service.request.set_header("x-datadog-origin", origin)
  end

  propagation_set("preserve", header_type, root_span, "datadog")
end


function DatadogHandler:log(conf)
  local ngx_ctx = ngx.ctx

  ngx_log(ngx_DEBUG, _log_prefix, "total spans in current request: ", ngx_ctx.KONG_SPANS and #ngx_ctx.KONG_SPANS)

  if not ngx_ctx.KONG_SPANS or #ngx_ctx.KONG_SPANS == 0 then
    return
  end

  if ngx_ctx.authenticated_consumer then
    local root_span = ngx_ctx.KONG_SPANS and ngx_ctx.KONG_SPANS[1]
    root_span:set_attribute("kong.consumer", ngx_ctx.authenticated_consumer.id)
  end

  local queue_id = conf.__key__
  local q = queues[queue_id]
  if not q then
    local process = function(entries)
      return http_export(conf, entries)
    end

    local opts = {
      batch_max_size = conf.batch_span_count,
      process_delay  = conf.batch_flush_delay,
    }

    local err
    q, err = BatchQueue.new("datadog-tracing", process, opts)
    if not q then
      kong.log.err("could not create queue: ", err)
      return
    end
    queues[queue_id] = q
  end

  local segment = new_tab(0, #ngx_ctx.KONG_SPANS)
  kong.tracing.process_span(process_span, segment, conf, kong.ctx.plugin.origin)

  q:add(segment)
end

return DatadogHandler
