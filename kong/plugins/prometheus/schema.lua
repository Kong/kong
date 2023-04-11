local typedefs = require "kong.db.schema.typedefs"

local function validate_shared_dict()
  if not ngx.shared.prometheus_metrics then
    return nil,
           "ngx shared dict 'prometheus_metrics' not found"
  end
  return true
end


return {
  name = "prometheus",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          { per_consumer = { description = "A boolean value that determines if per-consumer metrics should be\ncollected.\nIf enabled, the `kong_http_requests_total` and `kong_bandwidth_bytes`\nmetrics fill in the consumer label when available.", type = "boolean", default = false }, },
          { status_code_metrics = { description = "A boolean value that determines if status code metrics should be\ncollected.\nIf enabled, `http_requests_total`, `stream_sessions_total` metrics will be exported.", type = "boolean", default = false }, },
          { latency_metrics = { description = "A boolean value that determines if status code metrics should be\ncollected.\nIf enabled, `kong_latency_ms`, `upstream_latency_ms` and `request_latency_ms`\nmetrics will be exported.", type = "boolean", default = false }, },
          { bandwidth_metrics = { description = "A boolean value that determines if status code metrics should be\ncollected.\nIf enabled, `bandwidth_bytes` and `stream_sessions_total` metrics will be exported.", type = "boolean", default = false }, },
          { upstream_health_metrics = { description = "A boolean value that determines if status code metrics should be\ncollected.\nIf enabled, `upstream_target_health` metric will be exported.", type = "boolean", default = false }, },
        },
        custom_validator = validate_shared_dict,
    }, },
  },
}
