-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Queue                 = require "kong.tools.queue"
local telemetry_dispatcher  = require "kong.clustering.telemetry_dispatcher"
local otlp                  = require "kong.observability.otlp"
local debug_instrumentation = require "kong.enterprise_edition.debug_session.instrumentation"
local utils                 = require "kong.enterprise_edition.debug_session.utils"

local encode_traces         = otlp.encode_traces
local encode_span           = otlp.transform_span
local log                   = utils.log

local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN
local ngx_DEBUG = ngx.DEBUG


local function get_queue_conf(name)
  -- TODO: infer or simplify the queue conf
  return {
    name = string.format("debug-session:%s", name),
    log_tag = string.format("debug-sessions:%s-tag", name),
    max_batch_size = 200,
    max_coalescing_delay = 1,
    max_entries = 100,
    max_bytes = nil,
    initial_retry_delay = 0.1,
    max_retry_time = 60,
    max_retry_delay = 60,
    concurrency_limit = 1,
  }
end


local function dispatcher_send(dispatcher, payload)
  if dispatcher:is_initialized() and not dispatcher:is_connected() then
    dispatcher:stop()
  end
  -- if it wasn't initialized or it's not connected, needs an init
  if not dispatcher:is_initialized() or not dispatcher:is_connected() then
    dispatcher:init_connection()
  end
  -- if not yet connected, skip this report
  if not dispatcher:is_connected() then
    return false, "dispatcher is not connected"
  end

  return dispatcher:send(payload)
end


local function encode_and_send(conf, data)
  local encoding_func = conf.encoding_func
  local dispatcher = conf.dispatcher

  local resource_attributes = {
    ["session.id"] = conf.session_id,
  }
  local payload = encoding_func(data, resource_attributes)

  local ok, err = dispatcher_send(dispatcher, payload)
  if ok then
    log(ngx_DEBUG, "websocket exporter sent ", #data, " items")
  else
    log(ngx_ERR, err)
  end
  return ok, err
end


local function report_traces_ws(conf)
  debug_instrumentation.foreach_span(function(span)
    local queue_conf = get_queue_conf("traces")

    if not Queue.can_enqueue(queue_conf) then
      log(ngx_WARN, "Buffer size limit reached for debug_session reports. ",
          "The current limit is ", queue_conf.max_entries)
      return
    end

    local ok, err = Queue.enqueue(
      queue_conf,
      encode_and_send,
      conf,
      encode_span(span)
    )

    if not ok then
      log(ngx_ERR, "Failed to enqueue span to rpc endpoint: ", err)
    end
  end)
end


local _M = {}
_M.__index = _M


function _M:new()
  local telemetry_endpoint = kong.configuration.cluster_telemetry_endpoint
  local server_name, port = telemetry_endpoint:match("([^:]+):?(%d*)")
  local scheme = port:sub(-3) == "443" and "wss://" or "ws://"
  local endpoint = scheme .. telemetry_endpoint

  local path = string.format(
    "/v1/analytics/tracing?node_id=%s&node_hostname=%s&node_version=%s",
    kong.node.get_id(), kong.node.get_hostname(), kong.version
  )

  local obj = {
    dispatcher = assert(telemetry_dispatcher.new({
      name = "debug_session",
      server_name = server_name,
      uri = endpoint .. path,
      pb_def_empty = "opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest",
    })),
  }

  setmetatable(obj, _M)
  return obj
end


function _M:init()
  self.dispatcher:init_connection()
end


function _M:stop()
  if not self.dispatcher then
    return nil, "not initialized"
  end
  self.dispatcher:stop()
end


function _M:has_traces()
  local spans = debug_instrumentation.get_spans()
  return spans and #spans > 0
end


function _M:report_traces(session_id)
  report_traces_ws({
    encoding_func = encode_traces,
    session_id = session_id,
    dispatcher = self.dispatcher,
  })
end


-- for unit testing
_M._encode_and_send = encode_and_send
_M._dispatcher_send = dispatcher_send

return _M
