local Queue = require "kong.tools.queue"
local o11y_logs = require "kong.observability.logs"
local otlp = require "kong.observability.otlp"
local tracing_context = require "kong.observability.tracing.tracing_context"
local otel_utils = require "kong.plugins.opentelemetry.utils"
local clone = require "table.clone"

local table_concat = require "kong.tools.table".concat

local ngx = ngx
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG

local http_export_request = otel_utils.http_export_request
local get_headers = otel_utils.get_headers
local _log_prefix = otel_utils._log_prefix
local encode_logs = otlp.encode_logs
local prepare_logs = otlp.prepare_logs


local function http_export_logs(conf, logs_batch)
  local headers = get_headers(conf.headers)
  local payload = encode_logs(logs_batch, conf.resource_attributes)

  local ok, err = http_export_request({
    connect_timeout = conf.connect_timeout,
    send_timeout = conf.send_timeout,
    read_timeout = conf.read_timeout,
    endpoint = conf.logs_endpoint,
  }, payload, headers)

  if ok then
    ngx_log(ngx_DEBUG, _log_prefix, "exporter sent ", #logs_batch,
          " logs to ", conf.logs_endpoint)

  else
    ngx_log(ngx_ERR, _log_prefix, err)
  end

  return ok, err
end


local function log(conf)
  local worker_logs = o11y_logs.get_worker_logs()
  local request_logs = o11y_logs.get_request_logs()

  local worker_logs_len = #worker_logs
  local request_logs_len = #request_logs
  ngx_log(ngx_DEBUG, _log_prefix, "total request_logs in current request: ",
      request_logs_len, " total worker_logs in current request: ", worker_logs_len)

  if request_logs_len + worker_logs_len == 0 then
    return
  end

  local raw_trace_id = tracing_context.get_raw_trace_id()
  local flags = tracing_context.get_flags()
  local worker_logs_ready = prepare_logs(worker_logs)
  local request_logs_ready = prepare_logs(request_logs, raw_trace_id, flags)

  local queue_conf = clone(Queue.get_plugin_params("opentelemetry", conf))
  queue_conf.name = queue_conf.name .. ":logs"

  for _, log in ipairs(table_concat(worker_logs_ready, request_logs_ready)) do
    -- Check if the entry can be enqueued before calling `Queue.enqueue`
    -- This is done because newer logs are not more important than old ones.
    -- Enqueueing without checking would result in older logs being dropped
    -- which affects performance because it's done synchronously.
    if Queue.can_enqueue(queue_conf, log) then
      Queue.enqueue(
        queue_conf,
        http_export_logs,
        conf,
        log
      )
    end
  end
end


return {
  log = log,
}
