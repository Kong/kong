local prometheus = require "kong.plugins.prometheus.exporter"


return {
  ["/metrics"] = {
    GET = function()
      prometheus.collect()
    end,
  },
}
