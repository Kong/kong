local prometheus = require "kong.plugins.prometheus.exporter"

local printable_metric_data = function()
  return table.concat(prometheus.metric_data(), "")
end

return {
  ["/metrics"] = {
    GET = function()
      prometheus.collect()
    end,
  },

  _stream = ngx.config.subsystem == "stream" and printable_metric_data or nil,
}
