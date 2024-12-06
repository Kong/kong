-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Queue                 = require "kong.tools.queue"
local telemetry_dispatcher  = require "kong.clustering.telemetry_dispatcher"
local otlp                  = require "kong.observability.otlp"
local at_instrumentation    = require "kong.enterprise_edition.debug_session.instrumentation"
local utils                 = require "kong.enterprise_edition.debug_session.utils"
local cjson                 = require "cjson.safe"
local http                  = require "resty.http"
local clustering_tls        = require "kong.clustering.tls"
local gzip                  = require "kong.tools.gzip"

local kong_version          = require "kong.meta".core_version
local to_hex                = require "resty.string".to_hex

local encode_traces         = otlp.encode_traces
local encode_span           = otlp.transform_span
local log                   = utils.log
local fmt                   = string.format

local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN
local ngx_DEBUG = ngx.DEBUG
local ANALYTICS_TRACING_PATH = "/v1/analytics/tracing?node_id=%s&node_hostname=%s&node_version=%s"
local SOCKET_TIMEOUT = 5000
local REQ_RES_CONTENTS_ID = "reqres"


local function get_queue_conf(name)
  local max_batch_size
  if name == "traces" then
    max_batch_size = 200
  elseif name == "contents" then
    -- contents must not be batched
    -- due to their potentially large size
    max_batch_size = 1
  end

  return {
    name = string.format("debug-session:%s", name),
    log_tag = string.format("debug-sessions:%s-tag", name),
    max_batch_size = max_batch_size,
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
  at_instrumentation.foreach_span(function(span)
    local queue_conf = get_queue_conf("traces")

    if not Queue.can_enqueue(queue_conf) then
      log(ngx_WARN, "Buffer size limit reached for debug_session traces reports. ",
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


local function report_contents_http(_, contents)
  local conf = assert(kong.configuration)
  local cmek_endpoint = assert(conf.cluster_cmek_endpoint, "KONG_CLUSTER_CMEK_ENDPOINT is not set")
  local cluster_control_plane = assert(conf.cluster_control_plane)
  local cluster_cert = assert(clustering_tls.get_cluster_cert(conf))
  local cluster_cert_key = assert(clustering_tls.get_cluster_cert_key(conf))

  local uri = "https://" .. cmek_endpoint

  local bod, err = cjson.encode(contents)
  if not bod then
    return nil, err
  end
  bod, err = gzip.deflate_gzip(bod)
  if not bod then
    return nil, err
  end

  -- strip until the frist dot
  local cluster_prefix = cluster_control_plane:match("([^.]*)")
  local httpc = http.new()
  httpc:set_timeout(SOCKET_TIMEOUT)
  local ok, err = httpc:request_uri(uri, {
    method = "POST",
    body = bod,
    headers = {
      ["User-Agent"] = fmt("kong/%s", kong_version),
      ["Content-Type"] = "application/json",
      ["Content-Encoding"] = "gzip",
      ["Content-Length"] = #bod,
      ["X-Client-Cluster-Prefix"] = cluster_prefix,
      ["X-Node-Id"] = kong.node.get_id(),
    },
    ssl_verify = true,
    ssl_client_cert = cluster_cert.cdata,
    ssl_client_priv_key = cluster_cert_key,
  })

  return ok ~= nil, err
end


local _M = {}
_M.__index = _M


function _M:new()
  local telemetry_endpoint = kong.configuration.cluster_telemetry_endpoint
  local server_name, port = telemetry_endpoint:match("([^:]+):?(%d*)")
  local scheme = port:sub(-3) == "443" and "wss://" or "ws://"
  local endpoint = scheme .. telemetry_endpoint

  local path = string.format(ANALYTICS_TRACING_PATH, kong.node.get_id(),
                                                     kong.node.get_hostname(),
                                                     kong.version)

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
  local spans = at_instrumentation.get_spans()
  return spans and #spans > 0
end


function _M:report_traces(session_id)
  report_traces_ws({
    encoding_func = encode_traces,
    session_id = session_id,
    dispatcher = self.dispatcher,
  })
end


function _M:report_contents(contents)
  if not contents then
    return
  end

  local queue_conf = get_queue_conf("contents")

  if not Queue.can_enqueue(queue_conf) then
    log(ngx_WARN, "Buffer size limit reached for debug_session contents reports. ",
        "The current limit is ", queue_conf.max_entries)
    return
  end

  local root_span = at_instrumentation.get_root_span()
  local trace_id = root_span and root_span.trace_id
  if not trace_id then
    log(ngx_ERR, "trace id is not set")
    return
  end
  trace_id = to_hex(trace_id)

  local contents_id = trace_id .. ":" .. REQ_RES_CONTENTS_ID
  local prepared_contents = {
    [contents_id] = contents
  }

  local ok, err = Queue.enqueue(
    queue_conf,
    report_contents_http,
    {},
    prepared_contents
  )

  if not ok then
    log(ngx_ERR, "Failed to enqueue content report: ", err)
  end
end


-- for unit testing
_M._encode_and_send = encode_and_send
_M._dispatcher_send = dispatcher_send

return _M
