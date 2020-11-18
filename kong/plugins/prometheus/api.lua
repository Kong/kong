local prometheus = require "kong.plugins.prometheus.exporter"

return {
  ["/metrics"] = {
    GET = function()
      prometheus.collect()
    end,
  },

  _stream = ngx.config.subsystem == "stream" and prometheus.metric_data or nil,
}
