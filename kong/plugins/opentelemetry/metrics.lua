local otlp = require "kong.plugins.opentelemetry.otlp"
local Queue = require "kong.tools.queue"
local clone = require "table.clone"
local otel_utils = require "kong.plugins.opentelemetry.utils"

local ngx = ngx
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG

local _log_prefix = otel_utils._log_prefix
local encode_data = otlp.transform_metric
local encode_metrics = otlp.encode_metrics
local http_export_request = otel_utils.http_export_request
local get_headers = otel_utils.get_headers


local function http_export_metrics(conf, metrics)
  local headers = get_headers(conf.headers)
  local payload = encode_metrics(metrics, conf.resource_attributes)

  local ok, err = http_export_request({
    connect_timeout = conf.connect_timeout,
    send_timeout = conf.send_timeout,
    read_timeout = conf.read_timeout,
    endpoint = conf.metrics_endpoint,
  }, payload, headers)

  if ok then
    ngx_log(ngx_DEBUG, _log_prefix, "exporter sent ", #metrics,
          " metrics to ", conf.metrics_endpoint)
  else
    ngx_log(ngx_ERR, _log_prefix, err)
  end
  return ok, err
end


local function log(conf, metrics)
  --
  local queue_conf = clone(Queue.get_plugin_params("opentelemetry", conf))
  queue_conf.name = queue_conf.name .. ":metrics"

  local metrics_counter = 0
  local metric_seg_start = 0
  local string_div = 2
  local metric_seg_end, div = string.find(metrics, "# HELP", string_div, true)
  string_div = div +1

  while metric_seg_start ~= metric_seg_end do
    metrics_counter = metrics_counter + 1
    local metric = string.sub(metrics, metric_seg_start, metric_seg_end-1)

    local ok, err = Queue.enqueue(
      queue_conf,
      http_export_metrics,
      conf,
      encode_data(metric)
    )
    if not ok then
      kong.log.err("Failed to enqueue span to log server: ", err)
    end

    metric_seg_start = metric_seg_end
    metric_seg_end, div = string.find(metrics, "# HELP", string_div, true)

    if not metric_seg_end then
      metric_seg_end = #metrics
    else
      string_div  = div+1
    end

  end
  ngx_log(ngx_DEBUG, _log_prefix, "total metrics in current request: ", metrics_counter)
end


return {
  log = log
}
